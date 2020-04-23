{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}

-- | self-defined types
module Synthesis.Data (module Synthesis.Data) where

import Data.HashMap.Lazy (HashMap)
import Data.Csv
import GHC.Generics (Generic)
import Language.Haskell.Exts.Syntax
import Language.Haskell.Exts.SrcLoc (SrcSpanInfo)

-- these verbose types annoy me so let's alias them

-- | SrcSpanInfo, stuff I don't care about that `haskell-src-exts` forces upon
-- | me by making it a mandatory (type/actual) parameter to all node types...
type L = SrcSpanInfo

-- | Type node
type Tp = Type L

-- | Expression node, where my branches consist of function application, my leaves of typed holes or variables.
type Expr = Exp L

-- | things I wanna transfer between generation and synthesis sessions
data TaskFnDataset = TaskFnDataset
  { generationCfg :: GenerationConfig
  , dsl :: HashMap String Expr
  , generatedTypes :: HashMap Int [String]  -- i.e. typesByArity
  , fnTypes :: HashMap Expr Tp
  , fnInTypeInstanceOutputs :: HashMap Expr (HashMap [Tp] [(Expr, Either String Expr)])
  , restInstantiationInputs :: HashMap Tp [Expr]
  , datasets :: ([Expr], [Expr], [Expr])
  , exprBlocks :: [(String, Expr)]
  , longestString :: Int
  , charMap :: HashMap Char Int
  } deriving (Show, Generic)

data GenerationConfig = GenerationConfig
  { taskPath :: String
  , crashOnError :: Bool
  , seed :: Int
  -- type generation
  , nestLimit :: Int
  , maxInstances :: Int
  -- sample generation
  , numInputs :: Int
  , numMin :: Integer
  , numMax :: Integer
  , listMin :: Int
  , listMax :: Int
  -- function generation
  , maxWildcardDepth :: Int
  , genMaxHoles :: Int
  -- dataset generation
  , training :: Double
  , validation :: Double
  , test :: Double
  } deriving (Show, Generic)

data SynthesizerConfig = SynthesizerConfig
  { taskPath :: String
  , seed :: Int
  , numEpochs :: Int
  , modelPath :: String
  -- , encoderBatch :: Int
  -- , r3nnBatch :: Int
  , bestOf :: Int
  , dropoutRate :: Double
  , evalFreq :: Int
  , learningRate :: Float
  , checkWindow :: Int
  , convergenceThreshold :: Float
  , synthMaxHoles :: Int
  , resultFolder :: String
  } deriving (Show, Generic)

data ViewDatasetConfig = ViewDatasetConfig
  { taskPath :: String
  } deriving (Show, Generic)

data EvalResult = EvalResult { epoch     :: !Int
                              , lossTrain :: !Float
                              , lossTest  :: !Float
                              , errTest   :: !Float
                              }

instance ToNamedRecord EvalResult where
    toNamedRecord (EvalResult epoch lossTrain lossTest errTest) =
        namedRecord [ "epoch"     .= epoch
                    , "lossTrain" .= lossTrain
                    , "lossTest"  .= lossTest
                    , "errTest"   .= errTest
                    ]

evalResultHeader :: Header = header ["epoch", "lossTrain", "lossTest", "errTest"]
