{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE TupleSections #-}

-- | utility functions specifically related to types
module Synthesis.Types (module Synthesis.Types) where

import Data.Bifunctor (first, second)
import Data.HashMap.Lazy
  ( HashMap,
    toList,
  )
import Data.List (nubBy)
import Data.Maybe (fromMaybe)
import Language.Haskell.Exts.Extension
  ( Extension (..),
    KnownExtension (..),
  )
import Language.Haskell.Exts.Parser
  ( ParseMode (..),
    ParseResult (..),
    defaultParseMode,
    parseWithMode,
  )
import Language.Haskell.Exts.Pretty (Pretty)
import Language.Haskell.Exts.SrcLoc
  ( SrcSpan (..),
    SrcSpanInfo (..),
    srcInfoPoints,
    srcInfoSpan,
  )
import Language.Haskell.Exts.Syntax
  ( Asst (..),
    Binds (..),
    Boxed (..),
    Context (..),
    Decl (..),
    Exp (..),
    Literal (..),
    Name (..),
    Pat (..),
    Promoted (..),
    QName (..),
    QOp (..),
    Rhs (..),
    SpecialCon (..),
    TyVarBind (..),
    Type (..),
    IPName (..),
  )
import Synthesis.Data
import Synthesis.Utility

-- | dummy source span info, because I don't care
l :: L
l = SrcSpanInfo {srcInfoSpan = spn, srcInfoPoints = []}
  where
    spn = SrcSpan "<unknown>.hs" 1 1 1 1

-- | create a typed expression without value, intended for checking types
undef :: Tp -> Expr
undef = expTypeSig (var "undefined")

-- | create a qname node
qName :: String -> QName L
qName = UnQual l . Ident l

-- | create a variable node
var :: String -> Expr
var = Var l . qName

-- | \$
dollar :: QOp L
dollar = symbol "$"

-- | .
dot :: QOp L
dot = symbol "."

-- | create a monomorphic type node
tyCon :: String -> Tp
tyCon = TyCon l . qName

-- | create a type variable node
tyVar :: String -> Tp
tyVar = TyVar l . Ident l

-- | create a polymorphic type node
tyApp :: Tp -> Tp -> Tp
tyApp = TyApp l

-- -- | wrap `tyApp` such as to ensure lists get normalized to use tyList
-- -- | deprecated, not in use -- could be used in randomType to normalize
-- tyApp_ :: Tp -> Tp -> Tp
-- tyApp_ a b = case pp a of
--   "[]" -> tyList b
--   _ -> tyApp a b

-- | annotate an expression node with a type signature
expTypeSig :: Expr -> Tp -> Expr
expTypeSig = ExpTypeSig l

-- | type for a function
tyFun :: Tp -> Tp -> Tp
tyFun = TyFun l

-- | type constraint
tyForall :: Maybe [TyVarBind L] -> Maybe (Context L) -> Tp -> Tp
tyForall = TyForall l

-- -- | star type node: *
-- -- | deprecated, not in use
-- star :: Tp
-- star = TyStar l

-- | wildcard type node: _
wildcard :: Tp
wildcard = TyWildCard l Nothing

-- | unit type: ()
unit :: Tp
unit = TyCon l $ Special l $ UnitCon l

-- | parenthesized type
tyParen :: Tp -> Tp
tyParen = TyParen l

-- | let-expression
letIn :: HashMap String Expr -> Expr -> Expr
letIn = Let l . binds

-- | variable definitions in e.g. a let-expression
binds :: HashMap String Expr -> Binds L
binds = BDecls l . fmap (uncurry patBind) . toList

-- | variable definition in e.g. a let-expression
-- patBind :: Pat L -> Rhs L -> Maybe (Binds L) -> Decl L
patBind :: String -> Expr -> Decl L
patBind name expr = PatBind l (pvar name) (rhs expr) Nothing

-- | right-hand side of an assignment
rhs :: Expr -> Rhs L
rhs = UnGuardedRhs l

-- | variable name as used on the left-hand side of an assignment
pvar :: String -> Pat L
pvar = PVar l . ident

-- | tuple pattern as used on the left-hand side of an assignment
ptuple :: [Pat L] -> Pat L
ptuple = PTuple l Boxed

-- | symbol for use in infix expressions
symbol :: String -> QOp L
symbol = QVarOp l . UnQual l . Symbol l

-- | parenthesized expression
paren :: Expr -> Expr
paren = Paren l

-- | used in name nodes
ident :: String -> Name L
ident = Ident l

-- | function application
app :: Expr -> Expr -> Expr
app = App l

-- | function application: function
appFn :: Expr -> Expr
appFn = \case
    App _l a _b -> a
    _ -> error "App expected!"

-- | function application: argument
appArg :: Expr -> Expr
appArg = \case
    App _l _a b -> b
    _ -> error "App expected!"

-- | tuple of type constraints
cxTuple :: [Asst L] -> Context L
cxTuple = CxTuple l

cxSingle :: Asst L -> Context L
cxSingle = CxSingle l

cxEmpty :: Context L
cxEmpty = CxEmpty l

-- -- | implicit parameter constraint
-- -- | deprecated, not in use
-- iParam :: String -> Tp -> Asst L
-- iParam str = IParam l (IPLin l str)

-- type assertion
typeA :: QName L -> Tp -> Asst L
typeA qname tp = ClassA l qname [tp]

-- -- | get the string from an IPName
-- -- | deprecated, not in use
-- unIPName :: IPName L -> String
-- unIPName = \case
--     IPDup _l str -> str -- non-linear implicit parameter
--     IPLin _l str -> str -- linear implicit parameter

-- | get the string from a QName
unQName :: QName L -> String
unQName = \case
    Qual _l _moduleName name -> unName name -- name qualified with a module name
    UnQual _l name -> unName name -- unqualified local name
    Special _l _specialCon -> error "SpecialCon is not string-based"  -- built-in constructor with special syntax

-- | get the string from a Name
unName :: Name L -> String
unName = \case
    Ident _l str -> str   -- /varid/ or /conid/.
    Symbol _l str -> str  -- /varsym/ or /consym/

-- | infix function application
infixApp :: Expr -> QOp L -> Expr -> Expr
infixApp = InfixApp l

-- | a list of expressions
list :: [Expr] -> Expr
list = List l

-- | a tuple of expressions
tuple :: [Expr] -> Expr
tuple = Tuple l Boxed

-- | a literal expression
lit :: Literal L -> Expr
lit = Lit l

-- | Int expression
int :: Integer -> Expr
int i = lit $ Int l i $ show i

-- | String expression
string :: String -> Expr
string s = lit $ String l s s

-- | data constructor
con :: String -> Expr
con = Con l . qName

-- | lambda function
lambda :: [Pat L] -> Expr -> Expr
lambda = Lambda l

-- | list type
tyList :: Tp -> Tp
tyList = TyList l

-- | unpack a list expression
unList :: Expr -> [Expr]
unList = \case
  List _l exps -> exps
  _ -> error "expected list"

-- | unpack a tuple expression
unTuple :: Expr -> [Expr]
unTuple = \case
  Tuple _l _boxed exps -> exps
  _ -> error "expected tuple"

-- | unpack a tuple2 expression
unTuple2 :: Expr -> (Expr, Expr)
unTuple2 = unTuple `pipe` \case
  [a,b] -> (a,b)
  _ -> error "expected tuple2"

-- | unpack an either wrapping function results
unEitherError :: Expr -> Either String Expr
unEitherError = \case
  App _l a b -> case a of
    Con _l qname -> case qname of
      UnQual _l name -> case name of
        Ident _l str -> case str of
          "Right" -> Right b
          "Left" -> Left $ pp b
          _ -> error s
        _ -> error s
      _ -> error s
    _ -> error s
  _ -> error s
  where s = "expected Either SomeException _ !"

-- unpack a ParseResult into an Either
unParseResult :: ParseResult a -> Either String a
unParseResult = \case
  ParseOk a -> Right a
  ParseFailed _srcLoc str -> Left str

-- | any compiler extensions to use while parsing
parseMode :: ParseMode
parseMode =
  defaultParseMode
    { extensions =
        [ EnableExtension ScopedTypeVariables,
          -- EnableExtension FlexibleContexts,
          EnableExtension ConstraintKinds
        ]
    }

-- -- | this function takes an explicitly typed hole, returning its type
-- -- | deprecated, not in use
-- -- TODO: Maybe
-- holeType :: Expr -> Tp
-- holeType = \case
--   ExpTypeSig _l _exp tp -> tp
--   _ -> error "expected ExpTypeSig!"

-- | parse an expression from a string
parseExpr :: String -> Expr
parseExpr s = case unParseResult (parseWithMode parseMode s :: ParseResult Expr) of
  Right t -> t
  Left e -> error $ "failed to parse expr " ++ s ++ ": " ++ e

-- | parse a type from a string
parseType :: String -> Tp
parseType s = case unParseResult (parseWithMode parseMode s :: ParseResult Tp) of
  Right t -> t
  Left e -> error $ "failed to parse type " ++ s ++ ": " ++ e

-- | check if a type is a function type
isFn :: Tp -> Bool
isFn = \case
  TyFun _l _a _b -> True
  TyForall _l _maybeTyVarBinds _maybeContext tp -> isFn tp
  TyParen _l a -> isFn a
  _ -> False

-- | check if a type contains a function type
hasFn :: Tp -> Bool
hasFn typ =
  let f = hasFn
   in case typ of
        TyFun _l _a _b -> True
        TyForall _l _maybeTyVarBinds _maybeContext tp -> f tp
        TyTuple _l _boxed tps -> or $ f <$> tps
        TyUnboxedSum _l tps -> or $ f <$> tps
        TyList _l a -> f a
        TyParArray _l a -> f a
        TyApp _l a b -> f a || f b
        TyParen _l a -> f a
        TyKind _l a kind -> f a || f kind
        TyPromoted _l promoted -> case promoted of
          PromotedList _l _bl tps -> or $ f <$> tps
          PromotedTuple _l tps -> or $ f <$> tps
          _ -> False
        TyEquals _l a b -> f a || f b
        TyBang _l _bangType _unpackedness a -> f a
        _ -> False

-- | extract the input and output types from a function type as one list
fnIOTypes :: Tp -> [Tp]
fnIOTypes = (\tpl -> fst tpl ++ [snd tpl]) . fnTypeIO

-- | extract the input and output types from a function type
-- TODO: Maybe
fnTypeIO :: Tp -> ([Tp], Tp)
fnTypeIO = \case
  TyForall _l maybeTyVarBinds maybeContext tp -> case tp of
    TyFun _l a b -> first (f a :) $ fnTypeIO $ f b
    typ -> ([], typ)
    where
      f = TyForall _l maybeTyVarBinds maybeContext
  TyFun _l a b -> first (a :) $ fnTypeIO b
  TyParen _l a -> fnTypeIO a
  tp -> ([], tp)

-- | extract the input types from a function type
fnInputTypes :: Tp -> [Tp]
fnInputTypes = \case
  TyForall _l maybeTyVarBinds maybeContext typ -> case typ of
    TyFun _l a b -> f a : fnInputTypes (f b)
    _ -> []
    where
      f = TyForall _l maybeTyVarBinds maybeContext
  TyFun _l a b -> a : fnInputTypes b
  _ -> []

-- | check if a type is sane -- basically we wanna throw out crap like list of function.
typeSane :: Tp -> Bool
typeSane tp = constraintsSane tp && (not (hasFn tp) || (isFn tp && (and (typeSane <$> fnIOTypes tp))))
  where constraintsSane = \case
          TyForall _l _maybeTyVarBinds maybeContext _typ -> contextOk
            where
              contextOk :: Bool = fromContext $ fromMaybe (CxEmpty l) maybeContext
              fromContext :: Context L -> Bool = \case
                CxTuple _l assts -> all unAsst assts
                CxSingle _l asst -> unAsst asst
                CxEmpty _l -> True
              unAsst :: Asst L -> Bool = \case
                ClassA _l _qname tps -> flip all tps $ \case
                  TyVar _l _name -> True
                  _ -> False
                IParam _l _iPName a -> typeSane a
                ParenA _l asst -> unAsst asst
                _ -> error "unsupported Assist!"
          _ -> True

-- -- | check the effective arity of a function type
-- -- | deprecated, not in use
-- fnTpArity :: Tp -> Int
-- fnTpArity = \case
--   TyForall _l _maybeTyVarBinds _maybeContext tp -> f tp
--   TyParen _l a -> f a
--   TyFun _l _a b -> 1 + f b
--   _ -> 0
--   where f = fnTpArity

-- | filter out duplicate types. note this dedupe will fail for type variable variations...
nubPp :: Pretty a => [a] -> [a]
nubPp = nubBy (equating pp)

-- -- | turn any value into an expression
-- -- | deprecated, not in use, except in another deprecated function
-- mkExpr :: Show a => a -> Expr
-- mkExpr = parseExpr . show

-- -- | turn any value pair into an expression pair
-- -- | deprecated, not in use
-- mkExprPair :: (Show a, Show b) => (a, Either c b) -> (Expr, Either c Expr)
-- mkExprPair = first mkExpr . second (second mkExpr)

-- -- | turn any value pair into an expression pair
-- -- | deprecated, not in use
-- showPair :: (Show a, Show b) => (a, Either c b) -> (String, Either c String)
-- showPair = first show . second (second show)
