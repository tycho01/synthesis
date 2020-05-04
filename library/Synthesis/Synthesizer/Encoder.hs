{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE NoStarIsType #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}

module Synthesis.Synthesizer.Encoder (module Synthesis.Synthesizer.Encoder) where

import Data.Bifunctor (first, second)
import Data.Int (Int64) 
import Data.Char (ord)
import Data.HashMap.Lazy (HashMap, (!))
import GHC.Generics (Generic)
import GHC.TypeNats (Nat, KnownNat, type (*))
import Util (fstOf3)

import           Torch.Typed.Tensor
import qualified Torch.Typed.Tensor
import           Torch.Typed.Functional
import           Torch.Typed.Factories
import           Torch.Typed.Aux
import           Torch.Typed.Parameter
import qualified Torch.Typed.Parameter
import           Torch.Autograd
import           Torch.HList
import qualified Torch.NN                      as A
import qualified Torch.Functional              as F
import qualified Torch.Functional.Internal     as I
import qualified Torch.Tensor                  as D
import qualified Torch.Device                  as D
import qualified Torch.DType                   as D
import           Torch.Typed.NN.Recurrent.LSTM

import Synthesis.Orphanage ()
import Synthesis.Data (Expr)
import Synthesis.Utility (pp)
import Synthesis.Synthesizer.Utility
import Synthesis.Synthesizer.Params

data LstmEncoderSpec
    (device :: (D.DeviceType, Nat))
    (t :: Nat)
    (batch_size :: Nat)
    (maxChar :: Nat)
    (h :: Nat)
 where LstmEncoderSpec :: {
        lstmSpec :: LSTMSpec maxChar h NumLayers Dir 'D.Float device
    } -> LstmEncoderSpec device t batch_size maxChar h
 deriving (Show)

data LstmEncoder
    (device :: (D.DeviceType, Nat))
    (t :: Nat)
    (batch_size :: Nat)
    (maxChar :: Nat)
    (h :: Nat)
 where LstmEncoder :: {
    inModel  :: LSTMWithInit maxChar h NumLayers Dir 'ConstantInitialization 'D.Float device,
    outModel :: LSTMWithInit maxChar h NumLayers Dir 'ConstantInitialization 'D.Float device
    } -> LstmEncoder device t batch_size maxChar h
 deriving (Show, Generic)

instance A.Parameterized (LstmEncoder device t batch_size maxChar h)

instance (KnownDevice device, RandDTypeIsValid device 'D.Float, KnownNat maxChar, KnownNat h) => A.Randomizable (LstmEncoderSpec device t batch_size maxChar h) (LstmEncoder device t batch_size maxChar h) where
    sample LstmEncoderSpec {..} = do
        in_model  :: LSTMWithInit maxChar h NumLayers Dir 'ConstantInitialization 'D.Float device <- A.sample spec
        out_model :: LSTMWithInit maxChar h NumLayers Dir 'ConstantInitialization 'D.Float device <- A.sample spec
        return $ LstmEncoder in_model out_model
            -- TODO: consider LearnedInitialization
            where spec :: LSTMWithInitSpec maxChar h NumLayers Dir 'ConstantInitialization 'D.Float device = LSTMWithZerosInitSpec lstmSpec

lstmBatch
    :: forall batch_size t maxChar r3nnBatch device h
     . (KnownNat batch_size, KnownNat t, KnownNat maxChar, KnownNat h)
    => LstmEncoder device t batch_size maxChar h
    -> Tensor device 'D.Float '[batch_size, t, maxChar]
    -> Tensor device 'D.Float '[batch_size, t, maxChar]
    -> Tensor device 'D.Float '[batch_size, t * (2 * Dirs * h)]
lstmBatch LstmEncoder{..} in_vec out_vec = feat_vec where
    lstm' = \model -> fstOf3 . lstmWithDropout @'BatchFirst model
    emb_in  :: Tensor device 'D.Float '[batch_size, t, h * Dirs] = lstm'  inModel  in_vec
    emb_out :: Tensor device 'D.Float '[batch_size, t, h * Dirs] = lstm' outModel out_vec
    -- | For each pair, it then concatenates the topmost hidden representation at every time step to produce a 4HT-dimensional feature vector per I/O pair
    feat_vec :: Tensor device 'D.Float '[batch_size, t * (2 * Dirs * h)] =
            -- reshape $ cat @2 $ emb_in :. emb_out :. HNil
            asUntyped (D.reshape [natValI @batch_size, natValI @t * (2 * natValI @Dirs * natValI @h)]) $ cat @2 $ emb_in :. emb_out :. HNil

-- | NSPS paper's Baseline LSTM encoder
-- | to adjust their encoder to the domain of synthesizing Haskell I've made one change: sampling embedded features to guarantee a static output size
lstmEncoder
    :: forall batch_size t maxChar r3nnBatch device h
     . (KnownDevice device, KnownNat batch_size, KnownNat r3nnBatch, KnownNat t, KnownNat maxChar, KnownNat h)
    => LstmEncoder device t batch_size maxChar h
    -> HashMap Char Int
    -> [(Expr, Either String Expr)]
    -> IO (Tensor device 'D.Float '[r3nnBatch, t * (2 * Dirs * h)])
lstmEncoder encoder charMap io_pairs = do
    let LstmEncoder{..} = encoder
    let t_ :: Int = natValI @t
    let batch_size_ :: Int = natValI @batch_size
    let max_char :: Int = natValI @maxChar

    -- TODO: use tree encoding (R3NN) also for expressions instead of just converting to string
    let str_pairs :: [(String, String)] = first pp . second (show . second pp) <$> io_pairs
    -- convert char to one-hot encoding (byte -> 256 1/0s as float) as third lstm dimension
    let str2tensor :: Int -> String -> Tensor device 'D.Float '[1, t, maxChar] = \len -> Torch.Typed.Tensor.toDType @'D.Float . UnsafeMkTensor . D.toDevice (deviceVal @device) . flip I.one_hot max_char . D.asTensor . padRight 0 len . fmap ((fromIntegral :: Int -> Int64) . (+1) . (!) charMap)
    let vec_pairs :: [(Tensor device 'D.Float '[1, t, maxChar], Tensor device 'D.Float '[1, t, maxChar])] = first (str2tensor t_) . second (str2tensor t_) <$> str_pairs

    -- pre-vectored
    -- stack input vectors and pad to static dataset size
    let stackPad :: [D.Tensor] -> [Tensor device 'D.Float '[batch_size, t, maxChar]] =
            fmap UnsafeMkTensor . batchTensor batch_size_ . stack' 0
            -- batchTensor' @0 . UnsafeMkTensor . stack' 0  -- ambiguous shape
    let  in_vecs :: [Tensor device 'D.Float '[batch_size, t, maxChar]] =
            stackPad $ toDynamic . fst <$> vec_pairs
    let out_vecs :: [Tensor device 'D.Float '[batch_size, t, maxChar]] =
            stackPad $ toDynamic . snd <$> vec_pairs
    -- print $ "out_vecs"
    -- print $ "out_vecs: " ++ show (D.shape . toDynamic <$> out_vecs)

    let feat_vecs :: [Tensor device 'D.Float '[batch_size, t * (2 * Dirs * h)]] =
            uncurry (lstmBatch encoder) <$> zip in_vecs out_vecs
    -- print $ "feat_vecs"
    -- print $ "feat_vecs: " ++ show (D.shape . toDynamic <$> feat_vecs)
    --  :: Tensor device 'D.Float '[n', t * (2 * Dirs * h)]
    let feat_vec :: D.Tensor = F.cat (F.Dim 0) $ toDynamic <$> feat_vecs
    -- print $ "feat_vec: " ++ show (D.shape $ toDynamic feat_vec)

    -- | to allow R3NN a fixed number of samples for its LSTMs, I'm sampling the actual features to make up for potentially multiple type instances giving me a variable number of i/o samples.
    -- | I opted to pick sampling with replacement, which both more naturally handles sample sizes exceeding the number of items, while also seeming to match the spirit of mini-batching by providing more stochastic gradients.
    -- | for my purposes, being forced to pick a fixed sample size means simpler programs with few types may potentially be learned more easily than programs with e.g. a greater number of type instances.
    -- | there should be fancy ways to address this like giving more weight to hard programs (/ samples).
    sampled_feats :: Tensor device 'D.Float '[r3nnBatch, t * (2 * Dirs * h)]
            <- sampleTensor @0 @r3nnBatch (length io_pairs) feat_vec

    return sampled_feats

-- | 5.1.2 Cross Correlation encoder

-- | To help the model discover input substrings that are copied to the output, we designed an novel I/O example encoder to compute the cross correlation between each input and output example representation.
-- | We used the two output tensors of the LSTM encoder (discussed above) as inputs to this encoder.
-- | For each example pair, we first slide the output feature block over the input feature block and compute the dot product between the respective position representation.
-- | Then, we sum over all overlapping time steps.
-- | Features of all pairs are then concatenated to form a 2∗(T−1)-dimensional vector encoding for all example pairs.
-- | There are 2∗(T−1) possible alignments in total between input and output feature blocks.

-- Cross Correlation encoder
-- rotate, rotateT
-- h1_in, h1_out
-- dot(a, b)
-- mm(a, b)
-- matmul(a, b) performs matrix multiplications if both arguments are 2D and computes their dot product if both arguments are 1D
-- bmm(a, b)
-- bdot(a, b): (a*b).sum(-1)  -- https://github.com/pytorch/pytorch/issues/18027
-- htan activation fn

-- | We also designed the following variants of this encoder.

-- | Diffused Cross Correlation Encoder:
-- | This encoder is identical to the Cross Correlation encoder except that instead of summing over overlapping time steps after the element-wise dot product, we simply concatenate the vectors corresponding to all time steps, resulting in a final representation that contains 2∗(T−1)∗T features for each example pair.

-- | LSTM-Sum Cross Correlation Encoder:
-- | In this variant of the Cross Correlation encoder, instead of doing an element-wise dot product, we run a bidirectional LSTM over the concatenated feature blocks of each alignment.
-- | We represent each alignment by the LSTM hidden representation of the final time step leading to a total of 2∗H∗2∗(T−1) features for each example pair.

-- | Augmented Diffused Cross Correlation Encoder:
-- | For this encoder, the output of each character position of the Diffused Cross Correlation encoder is combined with the character embedding at this position, then a basic LSTM encoder is run over the combined features to extract a 4∗H-dimensional vector for both the input and the output streams.
-- | The LSTM encoder output is then concatenated with the output of the Diffused Cross Correlation encoder forming a (4∗H+T∗(T−1))-dimensional feature vector for each example pair.
