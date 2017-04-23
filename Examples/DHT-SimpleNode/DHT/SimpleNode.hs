{-|
Stability : experimental

Run a DHT computation using "DHT.SimpleNode.Logger", "DHT.SimpleNode.Messaging", "DHT.SimpleNode.RoutingTable"
and "DHT.SimpleNode.ValueStore" for stdout logging, simple UDP messaging a wrapped "DHT.Routing" routing table
and an in-memory hashmap value store.
-}
module DHT.SimpleNode
  ( mkSimpleNodeConfig
  , newSimpleNode
  )
  where

import           Control.Applicative
import           Control.Concurrent
import           Data.Time.Clock.POSIX
import           Network.Socket                       (Socket,socket,Family(AF_INET),SocketType(Datagram),inet_addr,SockAddr(SockAddrInet),inet_ntoa,bind)
import           System.Random
import qualified Data.ByteString.Char8      as Strict
import qualified Data.ByteString.Lazy.Char8 as Lazy
import qualified Network.Socket.ByteString  as Strict

import DHT
import DHT.Contact
import DHT.ID
import DHT.Message
import DHT.Types

import DHT.SimpleNode.Logging
import DHT.SimpleNode.Messaging
import DHT.SimpleNode.RoutingTable
import DHT.SimpleNode.ValueStore

import Control.Monad

mkSimpleNodeConfig :: Addr
                   -> Int
                   -> LoggingOp IO
                   -> IO (DHTConfig DHT IO)
mkSimpleNodeConfig ourAddr hashSize logging = do
  now          <- timeF
  routingTable <- newSimpleRoutingTable hashSize ourID now
  valueStore   <- newSimpleValueStore
  messaging    <- newSimpleMessaging hashSize (maxPortLength,ourPort)

  let ops = DHTOp {_dhtOpTimeOp         = timeF
                  ,_dhtOpRandomIntOp    = randF
                  ,_dhtOpMessagingOp    = messaging
                  ,_dhtOpRoutingTableOp = routingTable
                  ,_dhtOpValueStoreOp   = valueStore
                  ,_dhtOpLoggingOp      = logging
                  }
  return $ DHTConfig ops ourAddr hashSize
  where
    timeF :: IO Time
    timeF = round <$> getPOSIXTime

    randF :: IO Int
    randF = randomRIO (0,maxBound)

    Addr ourIP ourPort = ourAddr
    ourID = mkID ourAddr hashSize

    maxPortLength = 5

-- | Start a new node with some configuration.
-- - Will handle incoming messages for the duration of the given program.
-- Continuing communication after we reach the end of our own DHT computation must be programmed explicitly.
newSimpleNode :: DHTConfig DHT IO
              -> Maybe Addr
              -> DHT IO a
              -> IO (Either DHTError a)
newSimpleNode dhtConfig mBootstrapAddr dht = do
  let run :: Maybe Addr -> DHT IO a -> IO (Either DHTError a)
      run = runDHT dhtConfig

  forkIO $ void $ run Nothing recvAndHandleMessages

  run mBootstrapAddr dht

