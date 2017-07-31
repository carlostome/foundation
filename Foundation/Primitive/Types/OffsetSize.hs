-- |
-- Module      : Foundation.Primitive.Types.OffsetSize
-- License     : BSD-style
-- Maintainer  : Vincent Hanquez <vincent@snarc.org>
-- Stability   : experimental
-- Portability : portable
--
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MagicHash                  #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE CPP                        #-}
module Foundation.Primitive.Types.OffsetSize
    ( FileSize(..)
    , Offset(..)
    , Offset8
    , offsetOfE
    , offsetPlusE
    , offsetMinusE
    , offsetRecast
    , offsetCast
    , offsetSub
    , offsetShiftL
    , offsetShiftR
    , sizeCast
    , sizeLastOffset
    , sizeAsOffset
    , sizeSub
    , countOfRoundUp
    , offsetAsSize
    , (+.)
    , (.==#)
    , CountOf(..)
    , Size8
    , sizeOfE
    , csizeOfOffset
    , csizeOfSize
    , sizeOfCSSize
    , sizeOfCSize
    ) where

#include "MachDeps.h"

import GHC.Types
import GHC.Word
import GHC.Int
import GHC.Prim
import Foreign.C.Types
import System.Posix.Types (CSsize (..))
import Data.Bits
import Foundation.Internal.Base
import Foundation.Internal.Proxy
import Foundation.Numerical.Number
import Foundation.Numerical.Additive
import Foundation.Numerical.Subtractive
import Foundation.Numerical.Multiplicative
import Foundation.Primitive.IntegralConv
import Data.List (foldl')
import qualified Prelude

#if WORD_SIZE_IN_BITS < 64
import GHC.IntWord64
#endif

-- $setup
-- >>> import Foundation.Array.Unboxed

-- | File size in bytes
newtype FileSize = FileSize Word64
    deriving (Show,Eq,Ord)

-- | Offset in bytes used for memory addressing (e.g. in a vector, string, ..)
type Offset8 = Offset Word8

-- | Offset in a data structure consisting of elements of type 'ty'.
--
-- Int is a terrible backing type which is hard to get away from,
-- considering that GHC/Haskell are mostly using this for offset.
-- Trying to bring some sanity by a lightweight wrapping.
newtype Offset ty = Offset Int
    deriving (Show,Eq,Ord,Enum,Additive,Typeable,Integral,Prelude.Num)

instance IsIntegral (Offset ty) where
    toInteger (Offset i) = toInteger i
instance IsNatural (Offset ty) where
    toNatural (Offset i) = toNatural (integralCast i :: Word)
instance Subtractive (Offset ty) where
    type Difference (Offset ty) = CountOf ty
    (Offset a) - (Offset b) = CountOf (a-b)
instance IntegralCast Int (Offset ty) where
    integralCast i = Offset i
instance IntegralCast Word (Offset ty) where
    integralCast (W# w) = Offset (I# (word2Int# w))


(+.) :: Offset ty -> Int -> Offset ty
(+.) (Offset a) b = Offset (a + b)
{-# INLINE (+.) #-}

-- . is offset (as a pointer from a beginning), and # is the size (amount of data)
(.==#) :: Offset ty -> CountOf ty -> Bool
(.==#) (Offset ofs) (CountOf sz) = ofs == sz
{-# INLINE (.==#) #-}

offsetOfE :: Size8 -> Offset ty -> Offset8
offsetOfE (CountOf sz) (Offset ty) = Offset (ty * sz)

offsetPlusE :: Offset ty -> CountOf ty -> Offset ty
offsetPlusE (Offset ofs) (CountOf sz) = Offset (ofs + sz)

offsetMinusE :: Offset ty -> CountOf ty -> Offset ty
offsetMinusE (Offset ofs) (CountOf sz) = Offset (ofs - sz)

-- | subtract 2 CountOf values of the same type.
--
-- m need to be greater than n, otherwise negative count error ensue
-- use the safer (-) version if unsure.
offsetSub :: Offset a -> Offset a -> Offset a
offsetSub (Offset m) (Offset n) = Offset (m - n)

offsetRecast :: Size8 -> Size8 -> Offset ty -> Offset ty2
offsetRecast szTy (CountOf szTy2) ofs =
    let (Offset bytes) = offsetOfE szTy ofs
     in Offset (bytes `div` szTy2)

offsetShiftR :: Int -> Offset ty -> Offset ty2
offsetShiftR n (Offset o) = Offset (o `unsafeShiftR` n)

offsetShiftL :: Int -> Offset ty -> Offset ty2
offsetShiftL n (Offset o) = Offset (o `unsafeShiftL` n)

offsetCast :: Proxy (a -> b) -> Offset a -> Offset b
offsetCast _ (Offset o) = Offset o
{-# INLINE offsetCast #-}

sizeCast :: Proxy (a -> b) -> CountOf a -> CountOf b
sizeCast _ (CountOf sz) = CountOf sz
{-# INLINE sizeCast #-}

-- | subtract 2 CountOf values of the same type.
--
-- m need to be greater than n, otherwise negative count error ensue
-- use the safer (-) version if unsure.
sizeSub :: CountOf a -> CountOf a -> CountOf a
sizeSub (CountOf m) (CountOf n)
    | diff >= 0 = CountOf diff
    | otherwise = error "sizeSub negative size"
  where
    diff = m - n

-- TODO add a callstack, or a construction to prevent size == 0 error
sizeLastOffset :: CountOf a -> Offset a
sizeLastOffset (CountOf s)
    | s > 0     = Offset (pred s)
    | otherwise = error "last offset on size 0"

sizeAsOffset :: CountOf a -> Offset a
sizeAsOffset (CountOf a) = Offset a
{-# INLINE sizeAsOffset #-}

offsetAsSize :: Offset a -> CountOf a
offsetAsSize (Offset a) = CountOf a
{-# INLINE offsetAsSize #-}


-- | CountOf of a data structure in bytes.
type Size8 = CountOf Word8

-- | CountOf of a data structure.
--
-- More specifically, it represents the number of elements of type `ty` that fit
-- into the data structure.
--
-- >>> length (fromList ['a', 'b', 'c', '🌟']) :: CountOf Char
-- CountOf 4
--
-- Same caveats as 'Offset' apply here.
newtype CountOf ty = CountOf Int
    deriving (Show,Eq,Ord,Enum,Typeable,Integral)

instance Prelude.Num (CountOf ty) where
    fromInteger a = CountOf (fromInteger a)
    (+) (CountOf a) (CountOf b) = CountOf (a+b)
    (-) (CountOf a) (CountOf b)
        | b > a     = CountOf 0
        | otherwise = CountOf (a - b)
    (*) (CountOf a) (CountOf b) = CountOf (a*b)
    abs a = a
    negate _ = error "cannot negate CountOf: use Foundation Numerical hierarchy for this function to not be exposed to CountOf"
    signum (CountOf a) = CountOf (Prelude.signum a)

instance IsIntegral (CountOf ty) where
    toInteger (CountOf i) = toInteger i
instance IsNatural (CountOf ty) where
    toNatural (CountOf i) = toNatural (integralCast i :: Word)

instance Additive (CountOf ty) where
    azero = CountOf 0
    (+) (CountOf a) (CountOf b) = CountOf (a+b)

instance Subtractive (CountOf ty) where
    type Difference (CountOf ty) = Maybe (CountOf ty)
    (CountOf a) - (CountOf b) | a >= b    = Just . CountOf $ a - b
                              | otherwise = Nothing

instance Monoid (CountOf ty) where
    mempty = azero
    mappend = (+)
    mconcat = foldl' (+) 0

instance IntegralCast Int (CountOf ty) where
    integralCast i = CountOf i
instance IntegralCast Word (CountOf ty) where
    integralCast (W# w) = CountOf (I# (word2Int# w))

sizeOfE :: Size8 -> CountOf ty -> Size8
sizeOfE (CountOf sz) (CountOf ty) = CountOf (ty * sz)

-- | alignment need to be a power of 2
countOfRoundUp :: Int -> CountOf ty -> CountOf ty
countOfRoundUp alignment (CountOf n) = CountOf ((n + (alignment-1)) .&. complement (alignment-1))

-- when #if WORD_SIZE_IN_BITS < 64 the 2 following are wrong
-- instead of using FromIntegral and being silently wrong
-- explicit pattern match to sort it out.

csizeOfSize :: Size8 -> CSize
#if WORD_SIZE_IN_BITS < 64
csizeOfSize (CountOf (I# sz)) = CSize (W32# (int2Word# sz))
#else
csizeOfSize (CountOf (I# sz)) = CSize (W64# (int2Word# sz))
#endif

csizeOfOffset :: Offset8 -> CSize
#if WORD_SIZE_IN_BITS < 64
csizeOfOffset (Offset (I# sz)) = CSize (W32# (int2Word# sz))
#else
csizeOfOffset (Offset (I# sz)) = CSize (W64# (int2Word# sz))
#endif

sizeOfCSSize :: CSsize -> Size8
sizeOfCSSize (CSsize (-1))      = error "invalid size: CSSize is -1"
#if WORD_SIZE_IN_BITS < 64
sizeOfCSSize (CSsize (I32# sz)) = CountOf (I# sz)
#else
sizeOfCSSize (CSsize (I64# sz)) = CountOf (I# sz)
#endif

sizeOfCSize :: CSize -> Size8
#if WORD_SIZE_IN_BITS < 64
sizeOfCSize (CSize (W32# sz)) = CountOf (I# (word2Int# sz))
#else
sizeOfCSize (CSize (W64# sz)) = CountOf (I# (word2Int# sz))
#endif
