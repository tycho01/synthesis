{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ImpredicativeTypes #-}

-- | find holes in an AST
module Synthesis.FindHoles
  ( gtrExpr,
    strExpr,
    findHolesExpr,
    findIdentExpr,
    findFnAppExpr,
    findHolesExpr',
    findIdentExpr',
    findFnAppExpr',
    findTopFnAppExpr',
  )
where

import Language.Haskell.Exts.Syntax
import Synthesis.Data (Expr)
import Synthesis.Utility

-- | get the first sub-expression
gtrExpr :: Exp l -> Exp l
gtrExpr x = case x of
  (Let _l _binds xp) -> xp
  (App _l xp _exp2) -> xp
  (Paren _l xp) -> xp
  (ExpTypeSig _l xp _tp) -> xp
  _ -> x

-- | set the first sub-expression
strExpr :: Exp l -> Exp l -> Exp l
strExpr x xp = case x of
  (Let l binds _exp) -> Let l binds xp
  (App l _exp1 xp2) -> App l xp xp2
  (Paren l _exp) -> Paren l xp
  (ExpTypeSig l _exp tp) -> ExpTypeSig l xp tp
  _ -> x

-- | look for holes in an expression. to simplify extracting type,
-- | we will only look for holes as part of an ExpTypeSig, e.g. `_ :: Bool`.
-- | I couldn't figure out how to get this to typecheck as a whole lens,
-- | so instead I'm taking them as getter/setter pairs...
findHolesExpr :: Exp l1 -> [(Exp l2 -> Exp l2, Exp l3 -> Exp l3 -> Exp l3)]
findHolesExpr expr =
  let f = findHolesExpr
      -- by the time we use the lens, we already know exactly how we're navigating.
      -- however, at compile-time this isn't known, so we have to pretend we're still checking here.
      mapLenses (a, b) = (a . gtrExpr, composeSetters strExpr gtrExpr b)
   in case expr of
        Let _l _binds xpr -> mapLenses <$> f xpr
        App _l exp1 exp2 -> (mapLenses <$> f exp1) ++ (mapLenses2 <$> f exp2)
          where
            gtr2 x = case x of (App _l _exp1 xp2) -> xp2; _ -> x
            str2 x xp2 = case x of (App l xp1 _exp2) -> App l xp1 xp2; _ -> x
            mapLenses2 (a, b) = (a . gtr2, composeSetters str2 gtr2 b)
        Paren _l xpr -> mapLenses <$> f xpr
        ExpTypeSig _l xpr _tp -> case xpr of
          Var _l qname -> case qname of
            -- Special _l specialCon -> case specialCon of
            --     ExprHole _l -> [(id, flip const)]
            --     _ -> mapLenses <$> f xpr
            UnQual _l name -> case name of
              Ident _l str -> case str of
                "undefined" -> [(id, flip const)]
                _ -> mapLenses <$> f xpr
              _ -> mapLenses <$> f xpr
            _ -> mapLenses <$> f xpr
          _ -> mapLenses <$> f xpr
        _ -> []

findHolesExpr' :: Expr -> [Expr]
findHolesExpr' expr =
  let f = findHolesExpr'
   in case expr of
        Let _l _binds xpr -> f xpr
        App _l exp1 exp2 -> f exp1 ++ f exp2
        Paren _l xpr -> f xpr
        ExpTypeSig _l xpr _tp -> case xpr of
          Var _l qname -> case qname of
            UnQual _l name -> case name of
              Ident _l str -> case str of
                "undefined" -> [xpr]
                _ -> f xpr
              _ -> f xpr
            _ -> f xpr
          _ -> f xpr
        _ -> []

-- | like findHolesExpr but for non-hole `Ident`
-- | deprecated, not in use
findIdentExpr :: Exp l1 -> [(Exp l2 -> Exp l2, Exp l3 -> Exp l3 -> Exp l3)]
findIdentExpr expr =
  let f = findIdentExpr
      mapLenses (a, b) = (a . gtrExpr, composeSetters strExpr gtrExpr b)
   in case expr of
        Let _l _binds xpr -> mapLenses <$> f xpr
        App _l exp1 exp2 -> (mapLenses <$> f exp1) ++ (mapLenses2 <$> f exp2)
          where
            gtr2 x = case x of (App _l _exp1 xp2) -> xp2; _ -> x
            str2 x xp2 = case x of (App l xp1 _exp2) -> App l xp1 xp2; _ -> x
            mapLenses2 (a, b) = (a . gtr2, composeSetters str2 gtr2 b)
        Paren _l xpr -> mapLenses <$> f xpr
        ExpTypeSig _l xpr _tp -> case xpr of
          Var _l qname -> case qname of
            -- Special _l specialCon -> case specialCon of
            --     ExprHole _l -> [(id, flip const)]
            --     _ -> mapLenses <$> f xpr
            UnQual _l name -> case name of
              Ident _l str -> case str of
                "undefined" -> mapLenses <$> f xpr
                _ -> [(id, flip const)]
              _ -> mapLenses <$> f xpr
            _ -> mapLenses <$> f xpr
          _ -> mapLenses <$> f xpr
        _ -> []

-- | like findHolesExpr but for non-hole `Ident`
findIdentExpr' :: Expr -> [Expr]
findIdentExpr' expr =
  let f = findIdentExpr'
   in case expr of
        Let _l _binds xpr -> f xpr
        App _l exp1 exp2 -> f exp1 ++ f exp2
        Paren _l xpr -> f xpr
        Var _l qname -> case qname of
          -- Special _l specialCon -> case specialCon of
          --     ExprHole _l -> xpr
          --     _ -> f xpr
          UnQual _l name -> case name of
            Ident _l str -> case str of
              "undefined" -> []
              _ -> [expr]
            _ -> []
          _ -> []
        ExpTypeSig _l xpr _tp -> f xpr
        _ -> []

-- | like findHolesExpr but for App
-- | deprecated, not in use
findFnAppExpr :: Exp l1 -> [(Exp l2 -> Exp l2, Exp l3 -> Exp l3 -> Exp l3)]
findFnAppExpr expr =
  let f = findFnAppExpr
      mapLenses (a, b) = (a . gtrExpr, composeSetters strExpr gtrExpr b)
   in case expr of
        Let _l _binds xpr -> mapLenses <$> f xpr
        App _l exp1 exp2 -> [(id, flip const)] ++ (mapLenses <$> f exp1) ++ (mapLenses2 <$> f exp2)
          where
            gtr2 x = case x of (App _l _exp1 xp2) -> xp2; _ -> x
            str2 x xp2 = case x of (App l xp1 _exp2) -> App l xp1 xp2; _ -> x
            mapLenses2 (a, b) = (a . gtr2, composeSetters str2 gtr2 b)
        Paren _l xpr -> mapLenses <$> f xpr
        ExpTypeSig _l xpr _tp -> mapLenses <$> f xpr
        _ -> []

-- | like findHolesExpr but for App
-- | deprecated, not in use
findFnAppExpr' :: Expr -> [Expr]
findFnAppExpr' expr =
  let f = findFnAppExpr'
   in case expr of
        Let _l _binds xpr -> f xpr
        App _l exp1 exp2 -> [expr] ++ f exp1 ++ f exp2
        Paren _l xpr -> f xpr
        ExpTypeSig _l xpr _tp -> f xpr
        _ -> []

-- | find top App occurrences, i.e. only count multi-arg chains once
-- | deprecated, not in use
findTopFnAppExpr' :: Bool -> Expr -> [Expr]
findTopFnAppExpr' chained expr =
  let f = findTopFnAppExpr'
   in case expr of
        Let _l _binds xpr -> f chained xpr
        App _l exp1 exp2 -> [expr | not chained] ++ f True exp1 ++ f False exp2
        Paren _l xpr -> f chained xpr
        ExpTypeSig _l xpr _tp -> f chained xpr
        _ -> []
