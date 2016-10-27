{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedStrings #-}

module Nomyx.Api.Server where

import           Nomyx.Api.Api
import           Servant
import qualified Network.Wai.Handler.Warp as Warp
import           Network.Wai.Middleware.Cors
import           Network.Wai
import           Control.Concurrent.STM
import           Nomyx.Core.Types
import           Data.Monoid

serveApi :: TVar Session -> IO ()
serveApi tv = do
   putStrLn "Starting Api on http://localhost:8001/"
   Warp.run 8001 $ myCors $ serve nomyxApi $ server tv

customPolicy :: CorsResourcePolicy
customPolicy = simpleCorsResourcePolicy { corsMethods = simpleMethods <> ["DELETE", "PUT"] }

myCors :: Middleware
myCors = cors (const $ Just customPolicy)

putSwaggerYaml :: IO ()
putSwaggerYaml = undefined --BL.putStrLn $ encode $ toSwagger nomyxApi
