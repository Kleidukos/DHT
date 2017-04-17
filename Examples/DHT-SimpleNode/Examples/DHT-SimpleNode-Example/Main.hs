{-# LANGUAGE OverloadedStrings #-}
module Main where

import DHT.SimpleNode
import DHT.SimpleNode.Logging

import DHT
import DHT.Bucket
import DHT.ID
import DHT.Contact


import Control.Concurrent
import Control.Monad
import Data.Monoid
import Data.ByteString.Lazy
import Data.String.Conv
import qualified Data.ByteString.Lazy.Char8 as Lazy

-- delay a thread for n seconds
delay :: Int -> IO ()
delay = threadDelay . (* 1000000)

forkVoid :: IO a -> IO ThreadId
forkVoid m = forkIO $ void m

forkVoid_ :: IO a -> IO ()
forkVoid_ m = void (forkVoid m)

bootstrapAddr :: Addr
bootstrapAddr = Addr "127.0.0.1" 6471

idle :: DHT IO a
idle = liftDHT $ forever $ threadDelay 5000000

-- Add a prefix to a logged string
lgPrefix :: String -> String -> DHT IO ()
lgPrefix p str = lg (p <> str)

-- Prefix a log string with a name and our id
lgAt :: String -> String -> DHT IO ()
lgAt name str = do
  id <- askOurID
  lgPrefix (showBits id <> " " <> name <> " :\t") str

-- Store two values in the DHT, then show their IDs then try and retrieve the
-- values, expecting them to be the same.
testStore :: DHT IO ()
testStore = do
  let key0 = "Hello"
      val0 = "World!"

      key1 = "foo"
      val1 = "barbaz"

  lgHere . toS $ "Storing two values: " <> key0<>":"<>val0<>" and " <> key1<>":"<>val1
  keyID0  <- store key0 val0
  keyID1  <- store key1 val1
  lgHere $ "The IDs of the two keys are: " ++ showBits keyID0 ++ " and " ++ showBits keyID1

  lgHere "Looking up the two ID's to check they exist/ have the right value."
  mVal0 <- findValue keyID0
  mVal1 <- findValue keyID1
  responseValueIs mVal0 val0
  responseValueIs mVal1 val1

  return ()
  where
    lgHere = lgAt "testStore"

    -- Require that a response from 'findValue' is the same as a given value.
    -- Output related information.
    responseValueIs :: ([Contact],Maybe ByteString) -> ByteString -> DHT IO ()
    responseValueIs (cts,mVal) expectedVal =
      lgHere $ "Told about contacts: " ++ showContacts cts ++ (case mVal of
        Nothing
          -> " But did NOT get any value back. FAILURE."

        Just v
          | v == expectedVal
          -> " and got expected value back. SUCCESS."
          | otherwise
          -> " But got a different value back. FAILURE.")

-- Lookup two ID's communicated out of band in the DHT.
-- We hope to retrieve their values.
testLookup :: DHT IO ()
testLookup = do
  lgHere "Assuming values might have been stored by somebody else for \"Hello\" and \"foo\", lookup the values."
  mVal0 <- findValue (mkID ("Hello"::Lazy.ByteString) 8)
  mVal1 <- findValue (mkID ("foo"::Lazy.ByteString) 8)
  lgFindResponse mVal0
  lgFindResponse mVal1
  return ()
  where
    lgHere = lgAt "testLookup"

    lgFindResponse :: ([Contact],Maybe ByteString) -> DHT IO ()
    lgFindResponse (ctcs,mVal) =
      lgHere $ "Told about contacts: " ++ showContacts ctcs ++ (
        case mVal of
          Nothing
            -> mconcat [" But we did NOT get a value back."
                       ," This is only a FAILURE IF 'testStore' has stored these values before us."
                       ," Otherwise we're simply looking up IDs which don't exist."
                       ]

          Just v
            -> mconcat [" and we got the value: " ++ toS v
                       ," back."
                       ]
      )

-- Attempt to find our own closest neighbours by performing a 'findContact' on
-- our own ID.
testNeighbours :: DHT IO ()
testNeighbours = do
  id <- askOurID
  lgHere $ "Our ID is" ++ showBits id

  lgHere "Attempt to find the neighbours of our ID"
  (ns,mn) <- findContact id
  lgHere $ (case mn of
    Nothing
      -> "We're not already known about"

    Just i
      | _ID i == id
      -> "We found ourself"
      | otherwise
      -> "We found a collision with ourself!!"
      ) ++ " and found neighbours: " ++ showContacts ns
  where
    lgHere = lgAt "testNeighbours"

main :: IO ()
main = do
  -- Create a logger to share across our example nodes
  mLogging <- newSimpleLogging

  -- Create the first node others will use as a bootstrap.
  forkVoid_ $ newSimpleNode
                bootstrapAddr
                Nothing
                mLogging
                $ do lg "Creating bootstrap node."
                     idle

  -- Test storing and retrieving a value
  forkVoid_ $ newSimpleNode
                (Addr "127.0.0.1" 6472)
                (Just bootstrapAddr)
                mLogging
                $ do liftDHT $ delay 1
                     lg "Creating testStore node."
                     testStore
                     idle

  -- Test looking up a value WE didnt store
  forkVoid_ $ newSimpleNode
                (Addr "127.0.0.1" 6473)
                (Just bootstrapAddr)
                mLogging
                $ do lg "Creating testLookup node."
                     liftDHT $ delay 5
                     testLookup
                     idle

  -- Test neighbour lookup
  forkVoid_ $ newSimpleNode
                (Addr "127.0.0.1" 6474)
                (Just bootstrapAddr)
                mLogging
                $ do lg "Creating testNeighbours node."
                     liftDHT $ delay 8
                     testNeighbours
                     idle

  delay 10
  return ()

