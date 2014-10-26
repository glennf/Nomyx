{-# LANGUAGE GADTs #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE StandaloneDeriving #-}

-- | additional tools for evaluation
module Nomyx.Core.Engine.EvalUtils where

import Prelude hiding ((.), log)
import Control.Monad
import Control.Monad.State
import Control.Monad.Reader
import Control.Category
import Data.Typeable
import Data.Lens
import Data.Maybe
import Data.List
import Control.Applicative
import Control.Monad.Error
import Language.Nomyx.Expression
import Nomyx.Core.Engine.Types
import Nomyx.Core.Engine.Utils
import Safe

-- find a signal occurence in an environment
lookupSignal :: Typeable a => Signal a -> SignalAddress -> [SignalOccurence] -> Maybe a
lookupSignal fi fa frs = headMay $ mapMaybe (getSignalData fi fa) frs

--get the signal data from the signal occurence
getSignalData :: Typeable a => Signal a -> SignalAddress -> SignalOccurence -> Maybe a
getSignalData fi fa (SignalOccurence fi' res fa') = do
   ((fi'', res') :: (Signal a, a)) <- cast (fi', res)
   if (fi'' == fi) && maybe True (== fa) fa' then (Just res') else Nothing

errorHandler :: EventNumber -> String -> Evaluate ()
errorHandler en s = do
   rn <- access eRuleNumber
   logAll $ "Error in rule " ++ show rn ++ " (triggered by event " ++ show en ++ "): " ++ s

logPlayer :: PlayerNumber -> String -> Evaluate ()
logPlayer pn = log (Just pn)

logAll :: String -> Evaluate ()
logAll = log Nothing

log :: Maybe PlayerNumber -> String -> Evaluate ()
log mpn s = focusGame $ do
   time <- access currentTime
   void $ logs %= (Log mpn time s : )

liftEval :: EvaluateNE a -> Evaluate a
liftEval r = runReader r <$> get

--extract the game state from an Evaluate
--knowing the rule number performing the evaluation (0 if by the system)
--and the player number to whom display errors (set to Nothing for all players)
--TODO: clean
runEvalError :: RuleNumber -> (Maybe PlayerNumber) -> Evaluate a -> State Game ()
runEvalError rn mpn egs = modify (\g -> _eGame $ execState (runEvalError' mpn egs) (EvalEnv rn g))

runEvalError' :: (Maybe PlayerNumber) -> Evaluate a -> State EvalEnv ()
runEvalError' mpn egs = do
   e <- runErrorT egs
   case e of
      Right _ -> return ()
      Left e' -> do
         tracePN (fromMaybe 0 mpn) $ "Error: " ++ e'
         void $ runErrorT $ log mpn "Error: "


runEvaluateNE :: Game -> RuleNumber -> EvaluateNE a -> a
runEvaluateNE g rn ev = runReader ev (EvalEnv rn g)

runSystemEval :: PlayerNumber -> Evaluate a -> State Game ()
runSystemEval pn e = runEvalError 0 (Just pn) e

runSystemEval' :: Evaluate a -> State Game ()
runSystemEval' e = runEvalError 0 Nothing e

focusGame :: State Game a -> Evaluate a
focusGame = lift . (focus eGame)

accessGame :: Lens Game a -> Evaluate (a, RuleNumber)
accessGame l = do
   a <- access (eGame >>> l)
   rn <- access eRuleNumber
   return (a, rn)

putGame :: Lens Game a -> a -> Evaluate ()
putGame l a = do
   ruleActive <- evalRuleActive
   when ruleActive $ void $ (eGame >>> l) ~= a

modifyGame :: Lens Game a -> (a -> a) -> Evaluate ()
modifyGame l f = do
   ruleActive <- evalRuleActive
   when ruleActive $ void $ (eGame >>> l) %= f

evalRuleActive :: Evaluate Bool
evalRuleActive = do
   rn <- access eRuleNumber
   rs <- access (eGame >>> rules)
   return $ if rn == 0
      then True
      else case find (\r -> _rNumber r == rn) rs of
         Just r -> _rStatus r == Active
         Nothing -> True --TODO why should there be an evaluating rule not in the list?


--replace temporarily the rule number used for evaluation
withRN :: RuleNumber -> Evaluate a -> Evaluate a
withRN rn eval = do
   oldRn <- gets _eRuleNumber
   eRuleNumber ~= rn
   a <- eval
   eRuleNumber ~= oldRn
   return a

instance Eq SomeSignal where
  (SomeSignal e1) == (SomeSignal e2) = e1 === e2

instance Show EventInfo where
   show (EventInfo en rn _ _ s env) =
      "event num: " ++ (show en) ++
      ", rule num: " ++ (show rn) ++
      ", envs: " ++ (show env) ++
      ", status: " ++ (show s)
