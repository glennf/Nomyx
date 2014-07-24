{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE GADTs #-}
    
-- | Voting system
module Language.Nomyx.Vote where

import Prelude hiding (foldr)
import Language.Nomyx.Expression
import Language.Nomyx.Events
import Language.Nomyx.Inputs
import Language.Nomyx.Outputs
import Language.Nomyx.Players
import Language.Nomyx.Rules
import Control.Monad.State hiding (forM_)
import Data.Maybe
import Data.Typeable
import Data.Time hiding (getCurrentTime)
import Control.Arrow
import Control.Applicative
import Data.List
import qualified Data.Map as M

-- | a vote assessing function (such as unanimity, majority...)
type AssessFunction = VoteStats -> Maybe Bool

-- | the vote statistics, including the number of votes per choice (Nothing means abstention),
-- the number of persons called to vote, and if the vote if finished (timeout or everybody voted)
data VoteStats = VoteStats { voteCounts     :: M.Map (Maybe Bool) Int,
                             nbParticipants :: Int,
                             voteFinished   :: Bool}
                             deriving (Show)

-- | vote at unanimity every incoming rule
unanimityVote :: Nomex ()
unanimityVote = onRuleProposed $ callVoteRule unanimity oneDay

-- | call a vote on a rule for every players, with an assessing function and a delay
callVoteRule :: AssessFunction -> NominalDiffTime -> RuleInfo -> Nomex ()
callVoteRule assess delay ri = do
   endTime <- addUTCTime delay <$> liftEffect getCurrentTime
   callVoteRule' assess endTime ri

callVoteRule' :: AssessFunction -> UTCTime -> RuleInfo -> Nomex ()
callVoteRule' assess endTime ri = do
   let title = "Vote for rule: \"" ++ (_rName ri) ++ "\" (#" ++ (show $ _rNumber ri) ++ "):"
   callVote assess endTime title (activateOrRejectRule ri)

-- | call a vote for every players, with an assessing function, a delay and a function to run on the result
callVote :: AssessFunction -> UTCTime -> String -> (Bool -> Nomex ()) -> Nomex ()
callVote assess endTime title payload = do
   pns <- liftEffect getAllPlayerNumbers
   en <- onEventOnce (voteWith endTime pns assess title) payload
   displayVote en

-- vote with a function able to assess the ongoing votes.
-- the vote can be concluded as soon as the result is known.
voteWith :: UTCTime -> [PlayerNumber] -> AssessFunction -> String -> Event Bool
voteWith timeLimit pns assess title = shortcutEvents (voteEvents timeLimit title pns) (assess . getVoteStats (length pns))

-- list of vote events
voteEvents :: UTCTime -> String -> [PlayerNumber] -> [Event (Maybe Bool)]
voteEvents time title pns = map (singleVote time title) pns

-- trigger the display of a radio button choice on the player screen, yelding either Just True or Just False.
-- after the time limit, the value sent back is Nothing.
singleVote :: UTCTime -> String -> PlayerNumber -> Event (Maybe Bool)
singleVote timeLimit title pn = (Just <$> inputRadio pn title [(True, "For"), (False, "Against")]) <|> (Nothing <$ timeEvent timeLimit)

-- | assess the vote results according to a unanimity
unanimity :: AssessFunction
unanimity voteStats = voteQuota (nbVoters voteStats) voteStats

-- | assess the vote results according to an absolute majority (half voters plus one)
majority :: AssessFunction
majority voteStats = voteQuota ((nbVoters voteStats) `div` 2 + 1) voteStats
                       
-- | assess the vote results according to a majority of x (in %)
majorityWith :: Int -> AssessFunction
majorityWith x voteStats = voteQuota ((nbVoters voteStats) * x `div` 100 + 1) voteStats

-- | assess the vote results according to a fixed number of positive votes
numberVotes :: Int -> AssessFunction
numberVotes x voteStats = voteQuota x voteStats

-- | adds a quorum to an assessing function
withQuorum :: AssessFunction -> Int -> AssessFunction
withQuorum f minNbVotes = \voteStats -> if (voted voteStats) >= minNbVotes
                                        then f voteStats
                                        else if voteFinished voteStats then Just False else Nothing

getVoteStats :: Int -> [Maybe Bool] -> VoteStats
getVoteStats npPlayers votes = VoteStats
   {voteCounts   = M.fromList $ counts votes,
    nbParticipants = npPlayers,
    voteFinished = length votes == npPlayers}

counts :: (Eq a, Ord a) => [a] -> [(a, Int)]
counts as = map (head &&& length) (group $ sort as)

-- | Compute a result based on a quota of positive votes.
-- the result can be positive if the quota if reached, negative if the quota cannot be reached anymore at that point, or still pending.
voteQuota :: Int -> VoteStats -> Maybe Bool
voteQuota q voteStats
   | M.findWithDefault 0 (Just True)  vs >= q                       = Just True
   | M.findWithDefault 0 (Just False) vs > (nbVoters voteStats) - q = Just False
   | otherwise = Nothing
   where vs = voteCounts voteStats


-- | number of people that voted if the voting is finished,
-- total number of people that should vote otherwise
nbVoters :: VoteStats -> Int
nbVoters vs
   | voteFinished vs = (nbParticipants vs) - (notVoted vs)
   | otherwise = nbParticipants vs

totalVoters, voted, notVoted :: VoteStats -> Int
totalVoters vs = M.foldr (+) 0 (voteCounts vs)
notVoted    vs = fromMaybe 0 $ M.lookup Nothing (voteCounts vs)
voted       vs = (totalVoters vs) - (notVoted vs)

displayVote :: EventNumber -> Nomex ()
displayVote en = void $ outputAll $ do
   mds <- getIntermediateResults en
   let mbs = map getBooleanResult <$> mds
   pns <- getAllPlayerNumbers
   case mbs of
      Just bs -> showOnGoingVote $ getVotes pns bs
      Nothing -> return ""

getVotes :: [PlayerNumber] -> [(PlayerNumber, Bool)] -> [(PlayerNumber, Maybe Bool)]
getVotes pns rs = map (findVote rs) pns where
   findVote :: [(PlayerNumber, Bool)] -> PlayerNumber -> (PlayerNumber, Maybe Bool)
   findVote rs pn = case (find (\(pn1, b) -> pn == pn1) rs) of
      Just (pn, b) -> (pn, Just b)
      Nothing -> (pn, Nothing)

getBooleanResult :: (PlayerNumber, SomeData) -> (PlayerNumber, Bool)
getBooleanResult (pn, SomeData sd) = case (cast sd) of
   Just a  -> (pn, a)
   Nothing -> error "incorrect vote field"

showChoice :: Maybe Bool -> String
showChoice (Just a) = show a
showChoice Nothing  = "Not Voted"

showOnGoingVote :: [(PlayerNumber, Maybe Bool)] -> NomexNE String
showOnGoingVote [] = return "Nobody voted yet"
showOnGoingVote listVotes = do
   list <- mapM showVote listVotes
   return $ "Votes:" ++ "\n" ++ concatMap (\(name, vote) -> name ++ "\t" ++ vote ++ "\n") list

showFinishedVote :: [(PlayerNumber, Maybe Bool)] -> NomexNE String
showFinishedVote l = do
   let voted = filter (\(_, r) -> isJust r) l
   votes <- mapM showVote voted
   return $ intercalate ", " $ map (\(name, vote) -> name ++ ": " ++ vote) votes

showVote :: (PlayerNumber, Maybe Bool) -> NomexNE (String, String)
showVote (pn, v) = do
   name <- showPlayer pn
   return (name, showChoice v)
                                              
--displayVoteResult :: (Votable a) => String -> VoteData a -> Nomex OutputNumber
--displayVoteResult toVoteName (VoteData msgEnd voteVar _ _ _) = onMessage msgEnd $ \result -> do
--   vs <- getMsgVarData_ voteVar
--   votes <- liftEffect $ showFinishedVote vs
--   void $ outputAll_ $ "Vote result for " ++ toVoteName ++ ": " ++ showChoices result ++ " (" ++ votes ++ ")"


