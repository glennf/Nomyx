-----------------------------------------------------------------------------
--
-- Module      :  Help
-- Copyright   :
-- License     :  OtherLicense
--
-- Maintainer  :  corentin.dupont@gmail.com
-- Stability   :
-- Portability :
--
-- |
--
-----------------------------------------------------------------------------

module Web.Help where
upload = "In the following form you can upload your file containing custom rules. The file must be a haskell .hs file containing a module, \n" ++
         "like the following example (file is named SimpleModule.hs). Once correctly loaded, the content of the file will be \"in scope\" and you will be able to propose the functions \n" ++
         "in the file as new rules on the main page (in this example, you will be able to propose myRule).\n" ++
         "Additionally, your file will appear as a link on the left hand side on the main page\n" ++
         "Warning, files uploaded here cannot be overwritten. If your uploaded file contains a mistake,\n" ++
         "re-upload it with a different name (a version number suffixed for example) or ask the administrator to delete it.\n"

uploadExample = "module SimpleModule where\n" ++
                "import Prelude\n" ++
                "import Language.Nomyx\n" ++
                "myRule :: RuleFunc\n" ++
                "myRule = voidRule $ outputAll helperFunction\n" ++
                "helperFunction :: String\n" ++
                "helperFunction = \"Hello\"\n"

code = "This is where you type in your new rule. Its type must be \"RuleFunc\". As a first rule, you can try to type \"nothing\", which is a rule that does nothing. Other examples can be found in the file Examples.hs accessible on the left tab."
actives = "Those rules are active and control the game. Usually, initial rules define how to propose and activate new rules (for example, a democratic vote) and how to win. Of course, this can be changed!"
pendings = "Rules are pending after being proposed by a player. Only another, active rule can activate those rules with instruction \"activateRule\"."
inputs = "Rules can trigger an input to gather data from the player, for example with the instruction \"onInputRadio\"."
events = "Rules can register on events, in order to be triggered when the event happens, for example with the instruction \"onEvent\"."
variables = "Rules can create variables to store data. For example, a rule creating a bank account with instruction \"newVar\" will make a new variable appear here."
outputs = "Rules can display text on players screen, with instruction \"output\"."
view = "Only view a game. You will not be able to propose new rules."
join = "Be part of the game. You will be able to propose new rules, vote etc. Please register in the game's agora (see the link on game page) to follow the game."

getSaveFile = "With the following link, you can download the save file of the game. This allows you to load it in a local instance of the game.\n" ++
              "This way, you will be able to compose and test the effects of your new rules locally, without affecting the online game. \n" ++
              "The procedure is: \n" ++
              "$> cabal install Nomyx \n" ++
              "$> Nomyx -r <save file name>\n"
