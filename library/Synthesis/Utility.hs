{-# LANGUAGE LambdaCase #-}

-- | utility functions
module Synthesis.Utility (Item(..), NestedTuple(..), flatten, pick, mapKeys, groupByVal, fromKeys, fromVals, flattenTuple, mapTuple, mapTuple3, tuplify3, untuple3, while, pp, pp_, pickKeys, composeSetters, randomSplit, flipOrder, equating, fromKeysM, fromValsM, ppMap, filterHmM, pickKeysSafe) where

import Data.Hashable (Hashable)
import System.Random (randomRIO)
import Data.HashMap.Lazy (HashMap, fromList, toList, (!), lookup)
import qualified Data.HashMap.Lazy as HM
import Language.Haskell.Exts.Pretty (Pretty(..), prettyPrint)
import qualified Data.Text.Prettyprint.Doc as PP -- (Pretty, pretty)
import GHC.Exts (groupWith)
import Data.Bifunctor (first)
import Data.Bifoldable (biList)
import Control.Monad (join, filterM)
import Control.Arrow ((***))
import Data.List.Split (splitPlaces)
import Data.Maybe (isJust, fromJust)

-- | map over both elements of a tuple
mapTuple :: (a -> b) -> (a, a) -> (b, b)
mapTuple = join (***)

-- | map over of a 3-element tuple
mapTuple3 :: (a -> b) -> (a, a, a) -> (b, b, b)
mapTuple3 f (a1, a2, a3) = (f a1, f a2, f a3)

-- | convert a list of 3(+) items to a tuple of 3
tuplify3 :: [a] -> (a,a,a)
tuplify3 [x,y,z] = (x,y,z)

-- | unpack a tuple into a list
untuple3 :: (a, a, a) -> [a]
untuple3 (x,y,z) = [x,y,z]

-- | a homogeneous nested list
data Item a = One [a] | Many [Item a]

-- | flatten a nested list
flatten :: Item a -> [a]
flatten (One x) = x
flatten (Many x) = concatMap flatten x

-- | a homogeneous nested tuple
data NestedTuple a = SingleTuple (a, a) | DeepTuple (a, NestedTuple a)

-- | flatten a nested tuple
flattenTuple :: NestedTuple a -> [a]
flattenTuple = \case
    SingleTuple tpl -> biList tpl
    DeepTuple (x, xs) -> x : flattenTuple xs

-- | randomly pick an item from a list
pick :: [a] -> IO a
pick xs = (xs !!) <$> randomRIO (0, length xs - 1)

-- | map over the keys of a hashmap
mapKeys :: (Hashable k, Eq k, Hashable k_, Eq k_) => (k -> k_) -> HashMap k v -> HashMap k_ v
mapKeys fn = fromList . fmap (first fn) . toList

-- | group a list of k/v pairs by values, essentially inverting the original HashMap
groupByVal :: (Hashable v, Ord v) => [(k, v)] -> HashMap v [k]
groupByVal = fromList . fmap (\pairs -> (snd $ head pairs, fst <$> pairs)) . groupWith snd

-- | create a HashMap by mapping over a list of keys
fromKeys :: (Hashable k, Eq k) => (k -> v) -> [k] -> HashMap k v
fromKeys fn ks = fromList . zip ks $ fn <$> ks

-- | create a monadic HashMap by mapping over a list of keys
fromKeysM :: (Monad m, Hashable k, Eq k) => (k -> m v) -> [k] -> m (HashMap k v)
fromKeysM fn ks = sequence . fromList . zip ks $ fn <$> ks

-- | create a HashMap by mapping over a list of values
fromVals :: (Hashable k, Eq k) => (v -> k) -> [v] -> HashMap k v
fromVals fn vs = fromList $ zip (fn <$> vs) vs

-- | create a monadic HashMap by mapping over a list of values
fromValsM :: (Monad m, Hashable k, Eq k) => (v -> m k) -> [v] -> m (HashMap k v)
fromValsM fn vs = do
    ks <- sequence $ fn <$> vs
    return $ fromList $ zip ks vs

-- filter a HashMap by a monadic predicate
filterHmM :: (Monad m, Hashable k, Eq k) => ((k,v) -> m Bool) -> HashMap k v -> m (HashMap k v)
filterHmM p = fmap fromList . filterM p . toList

-- -- ‘hashWithSalt’ is not a (visible) method of class ‘Hashable’
-- -- https://github.com/haskell-infra/hackage-trustees/issues/139
-- instance (Type l) => Hashable (Type l) where
--     -- hash = 1
--     hashWithSalt n = hash
--     -- hashWithSalt salt tp = case (unpack $ pp tp) of
--     --         -- https://github.com/tibbe/hashable/blob/cc4ede9bf7821f952eb700a131cf1852d3fd3bcd/Data/Hashable/Class.hs#L641
--     --         T.Text arr off len -> hashByteArrayWithSalt (TA.aBA arr) (off `shiftL` 1) (len `shiftL` 1) salt
--     -- --  :: Int -> a -> Int
--     -- -- hashWithSalt salt tp = pp tp
--     -- -- hashWithSalt = defaultHashWithSalt

while :: Monad m => (a -> Bool) -> (a -> m a) -> a -> m a
while praed funktion x
    | praed x = do
        y <- funktion x
        while praed funktion y
    | otherwise = return x

-- | shorthand for pretty-printing AST nodes, used for comparisons
pp :: Pretty a => a -> String
pp = prettyPrint

-- | shorthand for pretty-printing AST nodes, used in my top-level module
pp_ :: PP.Pretty a => a -> String
pp_ = show . PP.pretty

-- | `show` drop-in for HashMap with Pretty keys.
ppMap :: (Pretty k, Show v) => HashMap k v -> String
ppMap = show . fmap (first pp) . toList

-- | pick some keys from a hashmap
pickKeys :: (Hashable k, Eq k) => [k] -> HashMap k v -> HashMap k v
pickKeys ks hashmap = fromKeys (hashmap !) ks

-- | pick some keys from a hashmap
pickKeysSafe :: (Hashable k, Eq k) => [k] -> HashMap k v -> HashMap k v
pickKeysSafe ks hashmap = fmap fromJust . HM.filter isJust $ fromKeys (`HM.lookup` hashmap) ks

-- | compose two setter functions, as I didn't figure out lenses and their monad instantiations
composeSetters :: (s -> s -> s_) -> (s -> t) -> (t -> b -> s) -> s -> b -> s_
composeSetters newStr newGtr oldStr v part = newStr v $ oldStr (newGtr v) part

-- | randomly split a dataset into subsets based on the indicated split ratio
randomSplit :: (Double, Double, Double) -> [a] -> ([a], [a], [a])
randomSplit split xs = let
        n :: Int = length xs
        ns :: (Int, Int, Int) = mapTuple3 (round . (fromIntegral n *)) split
    in
        tuplify3 $ splitPlaces (untuple3 ns) xs

-- | flip an Ordering
flipOrder :: Ordering -> Ordering
flipOrder GT = LT
flipOrder LT = GT
flipOrder EQ = EQ

-- | mapped equality check
equating :: Eq a => (b -> a) -> b -> b -> Bool
equating p x y = p x == p y