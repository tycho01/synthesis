{-# LANGUAGE ExplicitNamespaces #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}

module Synthesis.Synthesizer.Params (module Synthesis.Synthesizer.Params) where

import GHC.TypeNats (type (+))
import Torch.Typed.Aux

-- TODO: consider which hyperparams have been / should be shared across networks

-- | left-hand symbols: just Expression in our lambda-calculus DSL
type LhsSymbols = 1

-- | number of features for R3NN expansions/symbols. must be an even number for H.
type M = 20

-- | must use a static batch size i/o making it dynamic by SynthesizerConfig...
type EncoderBatch = 8
encoderBatch :: Int
encoderBatch = natValI @EncoderBatch
type R3nnBatch = 8
r3nnBatch :: Int
r3nnBatch = natValI @R3nnBatch

-- left/right MLPs
-- hard-coded
type Hidden0 = 20
hidden0 :: Int
hidden0 = natValI @Hidden0
-- hard-coded
type Hidden1 = 20
hidden1 :: Int
hidden1 = natValI @Hidden1

-- Encoder
-- hard-coded
-- | H is the topmost LSTM hidden dimension
type H = 30
h :: Int
h = natValI @H

-- R3NN
-- static LSTM can't deal with dynamic number of layers, as it unrolls on compile (init/use)
type NumLayers = 3
