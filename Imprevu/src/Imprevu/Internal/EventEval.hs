{-# LANGUAGE GADTs               #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TemplateHaskell           #-}


-- | Evaluation of the events
module Imprevu.Internal.EventEval where

import           Control.Applicative
import           Control.Category            hiding (id)
import           Control.Lens
import           Control.Monad
import           Control.Monad.Error.Class   (MonadError (..))
import           Control.Monad.Error
import           Control.Monad.Reader
import           Control.Monad.State
import           Data.Either
import qualified Data.Foldable               as F hiding (find)
import           Data.Function               (on)
import           Data.List
import           Data.Maybe
import           Data.Todo
import           Data.Typeable
import           Imprevu.Internal.Event
import           Imprevu.Internal.EvalUtils
import           Imprevu.Internal.Utils
import           Prelude                     hiding (log, (.))
import           Safe
import           Debug.Trace.Helpers    (traceM)


class HasEvents n s where
   getEvents :: s -> [EventInfo n]
   setEvents :: [EventInfo n] -> s -> s

-- | Environment necessary for the evaluation of any nomyx expressions or events
--TODO: should the first field be a "Maybe RuleNumber"?
--Indeed an evaluation is not always performed by a rule but also by the system (in which case we currently use rule number 0)
data EvalEnv n s = EvalEnv { _evalEnv      :: s,
                             evalFunc     :: forall a. (Show a) => n a -> Evaluate n s (),       -- evaluation function
                             errorHandler :: EventNumber -> String -> Evaluate n s ()}    -- error function

events :: (HasEvents n s) => Lens' (EvalEnv n s) [EventInfo n]
events f (EvalEnv s g h) = fmap (\s' -> (EvalEnv (setEvents s' s) g h)) (f (getEvents s))

-- | Environment necessary for the evaluation of Nome
type Evaluate n s a = ErrorT String (State (EvalEnv n s)) a

makeLenses ''EvalEnv

-- * Event triggers

-- trigger an event with an event result
triggerEvent :: (Signal e, HasEvents n s) => e -> (SignalDataType e) -> Evaluate n s ()
triggerEvent e dat = do
   (EvalEnv s _ _) <- get
   triggerEvent' (SignalData e dat) Nothing (getEvents s)

-- trigger some specific signal
triggerEvent' :: (HasEvents n s) => SignalData -> Maybe SignalAddress -> [EventInfo n] -> Evaluate n s ()
triggerEvent' sd msa evs = do
   let evs' = evs -- sortBy (compare `on` _ruleNumber) evs
   eids <- mapM (getUpdatedEventInfo sd msa) evs'           -- get all the EventInfos updated with the field
   traceM $ "triggerEvent' eids=" ++ (show eids) ++ " sd=" ++ (show sd) ++ " msa=" ++ (show msa) ++ " evs=" ++ (show evs)
   events %= union (map fst eids)                           -- store them
   void $ mapM triggerIfComplete eids                           -- trigger the handlers for completed events

-- if the event is complete, trigger its handler
triggerIfComplete :: (EventInfo n, Maybe SomeData) -> Evaluate n s ()
triggerIfComplete (EventInfo en _ h SActive _, Just (SomeData val)) = case cast val of
   Just a -> do
      traceM $ "triggerIfComplete" ++ (show a)
      eval <- gets evalFunc
      err <- gets errorHandler
      (void $ (eval $ h (en, a))) `catchError` (err en)
   Nothing -> error "Bad trigger data type"
triggerIfComplete _ = return ()


-- get update the EventInfo updated with the signal data.
-- get the event result if all signals are completed
getUpdatedEventInfo :: SignalData -> Maybe SignalAddress -> EventInfo n -> Evaluate n s (EventInfo n, Maybe SomeData)
getUpdatedEventInfo sd@(SignalData sig _) addr ei@(EventInfo _ ev _ _ envi) = do
   trs <- getEventResult ev envi
   traceM $ "getUpdatedEventInfo"
   case trs of
      Todo rs -> case find (\(sa, (SomeSignal ss)) -> (ss === sig) && maybe True (==sa) addr) rs of -- check if our signal match one of the remaining signals
         Just (sa, _) -> do
            traceM $ "getUpdatedEventInfo sa=" ++ (show sa)
            let envi' = SignalOccurence sd sa : envi
            er <- getEventResult ev envi'                                                           -- add our event to the environment and get the result
            case er of
               Todo _ -> do
                 traceM $ "getUpdatedEventInfo"
                 return (env .~ envi' $ ei, Nothing)                                              -- some other signals are left to complete: add ours in the environment
               Done a -> do
                 traceM $ "getUpdatedEventInfo a=" ++ (show a)
                 return (env .~  [] $ ei, Just $ SomeData a)                                       -- event complete: return the final data result
         Nothing -> do
           traceM "getUpdatedEventInfo Nothing"
           return (ei, Nothing)                                                            -- our signal does not belong to this event.
      Done a -> return (env .~  [] $ ei, Just $ SomeData a)

--get the signals left to be completed in an event
getRemainingSignals' :: EventInfo n -> Evaluate n s [(SignalAddress, SomeSignal)]
getRemainingSignals' (EventInfo _ e _ _ envi) = do
   tr <- getEventResult e envi
   return $ case tr of
      Done _ -> []
      Todo a -> a


-- compute the result of an event given an environment.
-- in the case the event cannot be computed because some signals results are pending, return that list instead.
getEventResult :: Event a -> [SignalOccurence] -> Evaluate n s (Todo (SignalAddress, SomeSignal) a)
getEventResult e frs = getEventResult' e frs []

-- compute the result of an event given an environment. The third argument is used to know where we are in the event tree.
getEventResult' :: Event e -> [SignalOccurence] -> SignalAddress -> Evaluate n s (Todo (SignalAddress, SomeSignal) e)
getEventResult' (PureEvent a)   _   _  = return $ Done a
getEventResult'  EmptyEvent     _   _  = return $ Todo []
getEventResult' (SumEvent a b)  ers fa = liftM2 (<|>) (getEventResult' a ers (fa ++ [SumL])) (getEventResult' b ers (fa ++ [SumR]))
getEventResult' (AppEvent f b)  ers fa = liftM2 (<*>) (getEventResult' f ers (fa ++ [AppL])) (getEventResult' b ers (fa ++ [AppR]))
--getEventResult' (LiftEvent a)   _   _  = do
--   evalNomexNE <- asks evalNomexNEFunc
--   r <- evalNomexNE a
--   return $ Done r
getEventResult' (BindEvent a f) ers fa = do
   er <- getEventResult' a ers (fa ++ [BindL])
   case er of
      Done a' -> getEventResult' (f a') ers (fa ++ [BindR])
      Todo bs -> return $ Todo bs

getEventResult' (SignalEvent a) ers fa = return $ case lookupSignal a fa ers of
   Just r  -> Done r
   Nothing -> Todo [(fa, SomeSignal a)]

getEventResult' (ShortcutEvents es f) ers fa = do
  (ers' :: [Todo (SignalAddress, SomeSignal) a]) <- mapM (\e -> getEventResult' e ers (fa ++ [Shortcut])) es -- get the result for each event in the list
  return $ if f (toMaybe <$> ers')                                                                     -- apply f to the event results that we already have
     then Done $ toMaybe <$> ers'                                                                        -- if the result is true, we are done. Return the list of maybe results
     else Todo $ join $ lefts $ toEither <$> ers'                                                        -- otherwise, return the list of remaining fields to complete from each event


getRemainingSignals :: EventInfo n -> EvalEnv n s -> [(SignalAddress, SomeSignal)]
getRemainingSignals (EventInfo _ e _ _ occ) env = case evalState (runEvalError' (getEventResult e occ)) env of
   Just (Todo a) -> a
   Just (Done _) -> []
   Nothing -> []

runEvalError' :: Evaluate n s a -> State (EvalEnv n s) (Maybe a)
runEvalError' egs = do
   e <- runErrorT egs
   case e of
      Right a -> return $ Just a
      Left e' -> error $ "error " ++ e'
         --tracePN (fromMaybe 0 mpn) $ "Error: " ++ e'
         --void $ runErrorT $ log mpn "Error: "