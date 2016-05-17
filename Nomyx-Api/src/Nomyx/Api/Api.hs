{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}

module Nomyx.Api.Api
     where

import GHC.Generics
import Data.Proxy
import Servant.API
import Servant.Client
import Servant
import Network.URI (URI (..), URIAuth (..), parseURI)
import Data.Maybe (fromMaybe)
import Servant.Common.Text
import Data.List (intercalate)
import qualified Data.Text as T
import Nomyx.Api.Utils
import Test.QuickCheck
import Nomyx.Api.Model.Player
import Nomyx.Api.Model.Error
import Nomyx.Api.Model.NewPlayer
import Nomyx.Core.Session
import Nomyx.Core.Types
import Nomyx.Core.Profile
import           Control.Concurrent.STM
import           Control.Monad.State
import Control.Monad.Trans.Either
import Data.Swagger
import Data.Swagger.Schema
import Language.Nomyx.Expression
import Data.Swagger.Internal.Schema
import Data.Swagger.Internal
import Data.Swagger.Lens
import Data.Swagger.Declare
import Data.Swagger.SchemaOptions
import Control.Monad.Except
import Control.Lens


-- * API definition

type NomyxApi = PlayerApi :<|> RuleTemplateApi

type PlayerApi =  "players" :>                                   Get  '[JSON] [ProfileData] -- playersGet
             :<|> "players" :> ReqBody '[JSON] PlayerSettings :> Post '[JSON] ProfileData -- playersPost
             :<|> "players" :> Capture "id" Int               :> Get '[JSON] ProfileData
             :<|> "players" :> Capture "id" Int               :> Delete '[JSON] ()


type RuleTemplateApi =  "templates" :>                                   Get  '[JSON] [RuleTemplate]  --get all templates
                   :<|> "templates" :> ReqBody '[JSON] RuleTemplate   :> Post '[JSON] () -- post new template
                   :<|> "templates" :> ReqBody '[JSON] [RuleTemplate] :> Put  '[JSON] () -- replace all templates

nomyxApi :: Proxy NomyxApi
nomyxApi = Proxy

serverPath :: String
serverPath = "https://api.nomyx.net/v1"

parseHostPort :: String -> (String, Int)
parseHostPort path = (host,port)
    where
        authority = case parseURI path of
            Just x -> uriAuthority x
            _      -> Nothing
        (host, port) = case authority of
            Just y -> (uriRegName y, (getPort . uriPort) y)
            _      -> ("localhost", 8080)
        getPort p = case (length p) of
            0 -> 80
            _ -> (read . drop 1) p

(host, port) = parseHostPort serverPath

server :: TVar Session -> Server NomyxApi
server tv = ((playersGet tv)   :<|> (playersPost tv)   :<|> (playerGet tv) :<|> (playerDelete tv))
       :<|> ((templatesGet tv) :<|> (templatesPost tv) :<|> (templatesPut tv))

-- * Players API

playersGet :: TVar Session -> EitherT ServantErr IO [ProfileData]
playersGet tv = do
   s <- liftIO $ atomically $ readTVar tv
   pds <- liftIO $ getAllProfiles s
   return pds

playersPost :: TVar Session -> PlayerSettings -> EitherT ServantErr IO ProfileData
playersPost tv ps = do
   liftIO $ updateSession tv (newPlayer 2 ps)
   s <- liftIO $ atomically $ readTVar tv
   pds <- liftIO $ getAllProfiles s
   return $ head pds

playerGet :: TVar Session -> PlayerNumber -> EitherT ServantErr IO ProfileData
playerGet tv pn = do
   s <- liftIO $ atomically $ readTVar tv
   mpd <- liftIO $ getProfile s pn
   case mpd of
     Just pd -> return pd
     Nothing -> throwError $ err410 { errBody = "Player does not exist." }

playerDelete :: TVar Session -> PlayerNumber -> EitherT ServantErr IO ()
playerDelete tv pn = error "not supported"

-- * Templates API

templatesGet :: TVar Session -> EitherT ServantErr IO [RuleTemplate]
templatesGet tv = do
   s <- liftIO $ atomically $ readTVar tv
   return $ _mLibrary $ _multi s

templatesPost :: TVar Session -> RuleTemplate -> EitherT ServantErr IO ()
templatesPost tv rt = do
   liftIO $ updateSession tv (newRuleTemplate rt)
   return ()

templatesPut :: TVar Session -> [RuleTemplate] -> EitherT ServantErr IO ()
templatesPut tv rts = do
   liftIO $ updateSession tv (updateRuleTemplates rts)
   return ()

instance ToSchema ProfileData
instance ToSchema PlayerSettings
instance ToSchema RuleTemplate
instance ToSchema LastUpload
instance ToSchema Module
--instance ToSchema RuleInfo
--instance ToSchema RuleStatus
--instance ToSchema Rule where
--  declareNamedSchema _ = pure (Nothing, nullarySchema)
