{-# LANGUAGE OverloadedStrings #-}

module System.IO.Streams.Tests.ByteString (tests) where

------------------------------------------------------------------------------
import           Control.Concurrent
import           Control.Monad
import           Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as S
import qualified Data.ByteString.Lazy.Char8 as L
import           Data.List
import           Data.Monoid
import           Prelude hiding (read)
import qualified Prelude
import           System.IO.Streams
import           Test.Framework
import           Test.Framework.Providers.HUnit
import           Test.Framework.Providers.QuickCheck2
import           Test.QuickCheck hiding (output)
import           Test.QuickCheck.Monadic
import           Test.HUnit hiding (Test)
import           System.IO.Streams.Tests.Common
------------------------------------------------------------------------------

tests :: [Test]
tests = [ testBoyerMoore
        , testCountInput
        , testCountOutput
        , testThrowIfTooSlow
        , testReadExactly
        , testTakeBytes
        , testTakeBytes2
        , testTakeBytes3
        , testThrowIfProducesMoreThan
        , testThrowIfProducesMoreThan2
        , testThrowIfConsumesMoreThan
        , testThrowIfConsumesMoreThan2
        , testTrivials
        , testWriteLazyByteString
        , testGiveBytes
        ]


------------------------------------------------------------------------------
testCountInput :: Test
testCountInput = testProperty "bytestring/countInput" $
                 monadicIO $
                 forAllM arbitrary prop
  where
    prop :: [ByteString] -> PropertyM IO ()
    prop l = liftQ $ do
        is          <- fromList l
        (is', grab) <- countInput is

        x <- toList is'
        n <- grab

        assertEqual "countInput1" (L.length $ L.fromChunks l) n
        assertEqual "countInput2" (L.length $ L.fromChunks x) n


------------------------------------------------------------------------------
testCountOutput :: Test
testCountOutput = testProperty "bytestring/countOutput" $
                  monadicIO $
                  forAllM arbitrary prop
  where
    prop :: [ByteString] -> PropertyM IO ()
    prop l = liftQ $ do
        is            <- fromList l
        (os0, grab)   <- listOutputStream
        (os, grabLen) <- countOutput os0

        connect is os

        xs <- grab
        n  <- grabLen

        assertEqual "countOutput1" l xs
        assertEqual "countOutput2" (L.length $ L.fromChunks l) n


------------------------------------------------------------------------------
testTakeBytes :: Test
testTakeBytes = testProperty "bytestring/takeBytes" $
                monadicIO $
                forAllM arbitrary prop
  where
    prop :: L.ByteString -> PropertyM IO ()
    prop l = pre (L.length l > 5) >> liftQ (do
        let (a,b) = L.splitAt 4 l

        is  <- fromList (L.toChunks l)
        is' <- takeBytes 4 is

        x   <- liftM L.fromChunks $ toList is'
        y   <- liftM L.fromChunks $ toList is

        assertEqual "take1" a x
        assertEqual "take2" b y
        )


------------------------------------------------------------------------------
testTakeBytes2 :: Test
testTakeBytes2 = testProperty "bytestring/takeBytes2" $
                 monadicIO $
                 forAllM arbitrary prop
  where
    prop :: L.ByteString -> PropertyM IO ()
    prop l = liftQ $ do
        is  <- fromList (L.toChunks l)
        is2 <- takeBytes 0 is

        x   <- toList is2
        y   <- liftM L.fromChunks $ toList is

        assertEqual "takeBytes3" [] x
        assertEqual "takeBytes4" l y

        -- Test that pushback makes it back to the source inputstream
        is3 <- takeBytes 20 is
        void $ toList is3
        unRead "ok2" is3
        unRead "ok1" is3

        z   <- toList is
        assertEqual "takeBytes5" ["ok1", "ok2"] z


------------------------------------------------------------------------------
testTakeBytes3 :: Test
testTakeBytes3 = testCase "bytestring/takeBytes3" $ do
    is <- fromList ["The", "quick", "brown", "fox"::ByteString] >>=
          takeBytes 100
    _  <- toList is
    m  <- read is

    assertEqual "takeBytes3" Nothing m


------------------------------------------------------------------------------
testThrowIfProducesMoreThan :: Test
testThrowIfProducesMoreThan =
    testProperty "bytestring/throwIfProducesMoreThan" $
    monadicIO $ forAllM arbitrary prop

  where
    prop :: L.ByteString -> PropertyM IO ()
    prop l = do
        pre (L.length l > 5)

        liftQ $ do
            is  <- fromList $ L.toChunks l
            is' <- throwIfProducesMoreThan 4 is
            expectExceptionH $ toList is'


------------------------------------------------------------------------------
testThrowIfProducesMoreThan2 :: Test
testThrowIfProducesMoreThan2 =
    testProperty "bytestring/throwIfProducesMoreThan2" $
    monadicIO $ forAllM arbitrary prop

  where
    prop :: L.ByteString -> PropertyM IO ()
    prop l = do
        let n = L.length l

        liftQ $ do
            is  <- fromList $ L.toChunks l
            is' <- throwIfProducesMoreThan (n + 1) is
            l'  <- liftM L.fromChunks $ toList is'
            assertEqual "throwIfProducesMoreThan2" l l'

            m   <- read is'
            assertEqual "throwIfProducesMoreThan2-2" Nothing m

            unRead "ok2" is'
            unRead "ok1" is'
            z   <- toList is
            assertEqual "throwIfProducesMoreThan2-3" ["ok1", "ok2"] z


------------------------------------------------------------------------------
testThrowIfConsumesMoreThan :: Test
testThrowIfConsumesMoreThan =
    testProperty "bytestring/throwIfConsumesMoreThan" $
    monadicIO $
    forAllM arbitrary prop
  where
    prop :: L.ByteString -> PropertyM IO ()
    prop l = do
        let n = L.length l
        pre (n > 0)
        liftQ $ do
             is      <- fromList (L.toChunks l)
             (os, _) <- listOutputStream
             os'     <- throwIfConsumesMoreThan (n-1) os

             expectExceptionH $ connect is os'


------------------------------------------------------------------------------
testThrowIfConsumesMoreThan2 :: Test
testThrowIfConsumesMoreThan2 =
    testProperty "bytestring/throwIfConsumesMoreThan2" $
    monadicIO $
    forAllM arbitrary prop
  where
    prop :: L.ByteString -> PropertyM IO ()
    prop l = do
        let n = L.length l

        liftQ $ do
             is         <- fromList (L.toChunks l)
             (os, grab) <- listOutputStream
             os'        <- throwIfConsumesMoreThan n os

             connect is os'

             l' <- liftM L.fromChunks grab
             assertEqual "throwIfConsumesMoreThan" l l'


------------------------------------------------------------------------------
testGiveBytes :: Test
testGiveBytes = testProperty "bytestring/giveBytes" $
                monadicIO $
                forAllM arbitrary prop
  where
    prop :: L.ByteString -> PropertyM IO ()
    prop l = do
        pre (L.length l > 5)
        let a = L.take 4 l

        liftQ $ do
            is         <- fromList (L.toChunks l)
            (os, grab) <- listOutputStream
            os'        <- giveBytes 4 os

            connect is os'
            write Nothing os'

            x <- liftM L.fromChunks grab

            assertEqual "giveBytes1" a x

        liftQ $ do
            is <- fromList $ L.toChunks a
            (os, grab) <- listOutputStream
            os'        <- giveBytes 10 os

            connect is os'
            write Nothing os'
            x <- liftM L.fromChunks grab
            assertEqual "giveBytes2" a x


------------------------------------------------------------------------------
testThrowIfTooSlow :: Test
testThrowIfTooSlow = testCase "bytestring/throwIfTooSlow" $ do
    is <- mkList
    expectExceptionH $ trickleFrom is

    is' <- mkList
    void $ toList is'
    x <- read is'

    assertEqual "throwIfTooSlow" Nothing x

    src  <- mkSrc
    src' <- throwIfTooSlow (return ()) 10 2 src

    void $ toList src'
    unRead "ok2" src'
    unRead "ok1" src'
    l <- toList src

    assertEqual "throwIfTooSlow/pushback" ["ok1", "ok2"] l


  where
    mkSrc = fromList $ Prelude.take 100 $ cycle $
            intersperse " " ["the", "quick", "brown", "fox"]

    mkList = mkSrc >>= throwIfTooSlow (return ()) 10 2

    trickleFrom is = go
      where
        go = read is >>= maybe (return ())
                               (\x -> x `seq` (threadDelay 2000000 >> go))


------------------------------------------------------------------------------
testBoyerMoore :: Test
testBoyerMoore = testProperty "bytestring/boyerMoore" $
                 monadicIO $ forAllM arbitrary prop
  where
    prop :: (ByteString, [ByteString]) -> PropertyM IO ()
    prop (needle, haystack') = do
        let lneedle   = L.fromChunks [needle]
        let lhaystack = L.fromChunks haystack'

        pre ((not $ S.null needle) &&
             (not $ L.null lhaystack) &&
             (not $ S.isInfixOf needle $ S.concat haystack'))


        (lhay, toklist0) <- insertNeedle lneedle lhaystack
        let stream  = L.toChunks $ L.concat [lneedle, lhay]
        let toklist = (Match needle) : toklist0

        -- there should be exactly three matches
        out <- liftQ (fromList stream >>= search needle >>= toList)

        let nMatches = length $ filter isMatch out

        let out' = concatAdj Nothing id out

        when (nMatches /= 3 || out' /= toklist) $ liftQ $ do
            putStrLn "got wrong output!!"
            putStrLn "needle:\n"
            putStrLn $ show lneedle
            putStrLn "\nhaystack:\n"
            mapM_ (putStrLn . show) stream
            putStrLn "\noutput stream:"
            mapM_ (putStrLn . show) out
            putStrLn "\noutput stream (minified):"
            mapM_ (putStrLn . show) out'
            putStrLn "\nexpected output:"
            mapM_ (putStrLn . show) toklist
            putStrLn ""

        liftQ $ do
            assertEqual "boyer-moore matches" 3 nMatches
            assertEqual "boyer-moore output" toklist out'


    isMatch (Match _) = True
    isMatch _         = False

    concatAdj :: Maybe MatchInfo
              -> ([MatchInfo] -> [MatchInfo])
              -> [MatchInfo]
              -> [MatchInfo]
    concatAdj prefix dl []     = dl $ maybe [] (:[]) prefix
    concatAdj prefix dl (x:xs) =
        maybe (concatAdj (Just x) dl xs)
              (\p -> maybe (concatAdj (Just x) (dl . (p:)) xs)
                           (\x' -> concatAdj (Just x') dl xs)
                           (merge p x))
              prefix

      where
        merge (NoMatch z) y
            | S.null z  = Just y
            | otherwise = case y of
                            NoMatch x' -> Just $ NoMatch $ z `mappend` x'
                            _          -> Nothing

        merge (Match _) _ = Nothing

    insertNeedle lneedle lhaystack = do
        idxL  <- pick $ choose (0, lenL-1)
        idxN  <- pick $ choose (0, lenN-1)
        idxN2 <- pick $ choose (0, lenN-1)
        let (l1, l2) = L.splitAt (toEnum idxL) lhaystack
        let (n1, n2) = L.splitAt (toEnum idxN) lneedle
        let (n3, n4) = L.splitAt (toEnum idxN2) lneedle

        let out1 = L.concat [ l1, n1, n2, l2, n3, n4 ]

        let res = concatAdj Nothing id
                      [ NoMatch $ strict l1
                      , Match   $ strict lneedle
                      , NoMatch $ strict l2
                      , Match   $ strict lneedle
                      ]

        return (out1, res)

      where
        strict = S.concat . L.toChunks

        lenN = fromEnum $ L.length lneedle
        lenL = fromEnum $ L.length lhaystack


------------------------------------------------------------------------------
testWriteLazyByteString :: Test
testWriteLazyByteString = testProperty "bytestring/writeLazy" $
                          monadicIO $
                          forAllM arbitrary prop
  where
    prop :: [ByteString] -> PropertyM IO ()
    prop l0 = liftQ $ do
        let l = filter (not . S.null) l0
        let s = L.fromChunks l
        (os, grab) <- listOutputStream
        writeLazyByteString s os

        l' <- grab
        assertEqual "writeLazy" l l'


------------------------------------------------------------------------------
testReadExactly :: Test
testReadExactly = testProperty "bytestring/readExactly" $
                  monadicIO $
                  forAllM arbitrary prop
  where
    prop l0 = liftQ $ do
        let l = filter (not . S.null) l0
        is <- fromList l

        let s = L.fromChunks l
        let n = fromEnum $ L.length s

        t <- readExactly n is
        assertEqual "eq" s $ L.fromChunks [t]

        unRead t is
        expectExceptionH $ readExactly (n+1) is

        when (n > 0) $ do
            is' <- fromList l
            u   <- readExactly (n-1) is'
            assertEqual "eq2" (L.take (toEnum $ n-1) s) (L.fromChunks [u])
            v   <- readExactly 1 is'
            assertEqual "eq3" (L.drop (toEnum $ n-1) s) (L.fromChunks [v])


------------------------------------------------------------------------------
testTrivials :: Test
testTrivials = testCase "bytestring/testTrivials" $ do
    coverTypeableInstance (undefined :: TooManyBytesReadException)
    coverShowInstance     (undefined :: TooManyBytesReadException)
    coverTypeableInstance (undefined :: RateTooSlowException)
    coverShowInstance     (undefined :: RateTooSlowException)
    coverTypeableInstance (undefined :: ReadTooShortException)

    coverEqInstance $ Match ""

    coverShowInstance $ Match ""
    coverShowInstance $ NoMatch ""