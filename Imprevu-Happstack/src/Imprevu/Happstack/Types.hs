{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE RankNTypes   #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE FlexibleInstances   #-}

module Imprevu.Happstack.Types where

import Control.Concurrent.STM
import Control.Lens
import Happstack.Server            as HS (Input, ServerPartT, FromReqURI(..))
import Imprevu
import Imprevu.Evaluation
import Text.Blaze.Html5                  (Html)
import Text.Reform                       (CommonFormError, ErrorInputType, Form, FormError (..))
import Safe

data WebStateN n s = WebState {_webState     :: TVar s,
                               updateSession :: TVar s -> InputS -> InputData -> EventNumber -> IO (), -- update the session after an input is submitted
                               webEvalConf   :: EvalConfN n s}

type ImpForm a = Form (ServerPartT IO) [HS.Input] ImpFormError Html () a

data ImpFormError = ImpFormError (CommonFormError [HS.Input])

instance FormError ImpFormError where
    type ErrorInputType ImpFormError = [HS.Input]
    commonFormError = ImpFormError

instance FromReqURI InputS where
    fromReqURI = readMay

instance FromReqURI InputData where
    fromReqURI = readMay

makeLenses ''WebStateN
