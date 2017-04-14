{-# LANGUAGE OverloadedStrings #-}
module Main where

import DHT
import DHT.Bucket
import DHT.ID
import DHT.Contact

import DHT.Node
import DHT.Node.Logging

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
  let val0 = "Hello World"
      val1 = "foobarbaz"
  lgHere . toS $ "Storing two values: " <> val0 <>" and " <> val1
  vID0  <- store val0
  vID1  <- store val1
  lgHere $ "The IDs of the two values are: " ++ showBits vID0 ++ " and " ++ showBits vID1

  lgHere "Looking up the two ID's to check they exist/ have the right value."
  mVal0 <- findValue vID0
  mVal1 <- findValue vID1
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
  lgHere "We've been given the ID's for \"Hello World\" and \"foobarbaz\" out of band so we're going to lookup the values."
  mVal0 <- findValue (mkID ("Hello World"::Lazy.ByteString) 8)
  mVal1 <- findValue (mkID ("foobarbaz"::Lazy.ByteString) 8)
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
  mLogging <- newLogging

  -- Create the first node others will use as a bootstrap.
  forkVoid_ $ newNode bootstrapAddr
                      Nothing
                      mLogging
                      $ lg "Creating bootstrap node." >> idle
  delay 1

  -- Test storing and retrieving a value
  forkVoid_ $ newNode (Addr "127.0.0.1" 6472)
                      (Just bootstrapAddr)
                      mLogging
                      $ lg "Creating testStore node." >> testStore
  delay 1

  -- Test looking up a value WE didnt store
  forkVoid_ $ newNode (Addr "127.0.0.1" 6473)
                      (Just bootstrapAddr)
                      mLogging
                      $ lg "Creating testLookup node." >> testLookup
  delay 2

  -- Test neighbour lookup
  forkVoid_ $ newNode (Addr "127.0.0.1" 6474)
                      (Just bootstrapAddr)
                      mLogging
                      $ lg "Creating testNeighbours node." >> testNeighbours

  delay 10
  return ()

