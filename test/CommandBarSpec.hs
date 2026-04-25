module CommandBarSpec (spec) where

import Libri.TUI.CommandBar
import Libri.Types (SortField (..), GroupField (..))
import Test.Hspec

spec :: Spec
spec = describe "CommandBar" $ do

  describe "parseCommand" $ do
    it "parses tag filter" $
      parseCommand "tag Philosophy" `shouldBe` CmdFilterTag "Philosophy"
    it "parses author filter" $
      parseCommand "author Eco" `shouldBe` CmdFilterAuthor "Eco"
    it "parses group by tag" $
      parseCommand "group tag" `shouldBe` CmdGroup GroupByTag
    it "parses group by author" $
      parseCommand "group author" `shouldBe` CmdGroup GroupByAuthor
    it "parses group none" $
      parseCommand "group none" `shouldBe` CmdGroupNone
    it "parses clear" $
      parseCommand "clear" `shouldBe` CmdClear
    it "parses sort title" $
      parseCommand "sort title" `shouldBe` CmdSort SortByTitle
    it "parses sort author" $
      parseCommand "sort author" `shouldBe` CmdSort SortByAuthor
    it "parses sort date" $
      parseCommand "sort date" `shouldBe` CmdSort SortByDate
    it "returns unknown for invalid command" $
      parseCommand "foobar" `shouldBe` CmdUnknown "foobar"
    it "trims whitespace from arguments" $
      parseCommand "tag  Philosophy  " `shouldBe` CmdFilterTag "Philosophy"
    it "handles empty input" $
      parseCommand "" `shouldBe` CmdUnknown ""
    it "returns needs-arg for group without argument" $ do
      let result = parseCommand "group"
      case result of
        CmdNeedsArg _ _ -> pure ()
        other -> expectationFailure $ "expected CmdNeedsArg, got " <> show other
    it "returns needs-arg for tag without argument" $ do
      let result = parseCommand "tag"
      case result of
        CmdNeedsArg _ _ -> pure ()
        other -> expectationFailure $ "expected CmdNeedsArg, got " <> show other
    it "returns needs-arg for sort without argument" $ do
      let result = parseCommand "sort"
      case result of
        CmdNeedsArg _ _ -> pure ()
        other -> expectationFailure $ "expected CmdNeedsArg, got " <> show other

  describe "tab completion" $ do
    let candidates = ["Art", "History", "Philosophy", "Poetry", "Politics"]
        cbs = initCommandBarState candidates []

    it "completes first match on Tab" $ do
      let cbs' = cbs { cbsInput = "tag Ph" }
          completed = completeNext cbs'
      cbsInput completed `shouldBe` "tag Philosophy"

    it "cycles through matches on repeated Tab" $ do
      let cbs' = cbs { cbsInput = "tag P" }
          c1 = completeNext cbs'
          c2 = completeNext c1
      cbsInput c1 `shouldNotBe` cbsInput c2

    it "shows all options when argument is empty" $ do
      let cbs' = cbs { cbsInput = "tag " }
          c1 = completeNext cbs'
      cbsInput c1 `shouldBe` "tag Art"

    it "wraps around after exhausting matches" $ do
      let cbs' = cbs { cbsInput = "tag Art" }
          c1 = completeNext cbs'
          c2 = completeNext c1
      cbsInput c1 `shouldBe` "tag Art"
      cbsInput c2 `shouldBe` "tag Art"

  describe "command-level completion" $ do
    let cbs = initCommandBarState ["Philosophy"] ["Eco"]

    it "cycles through commands from empty input" $ do
      let c1 = completeNext cbs
      cbsInput c1 `shouldBe` "tag "

    it "cycles to next command on repeated Tab" $ do
      let c1 = completeNext cbs
          c2 = completeNext c1
          c3 = completeNext c2
          c4 = completeNext c3
          c5 = completeNext c4
      cbsInput c1 `shouldBe` "tag "
      cbsInput c2 `shouldBe` "author "
      cbsInput c3 `shouldBe` "group "
      cbsInput c4 `shouldBe` "sort "
      cbsInput c5 `shouldBe` "clear "

    it "completes partial command keyword" $ do
      let cbs' = cbs { cbsInput = "gr" }
          c1 = completeNext cbs'
      cbsInput c1 `shouldBe` "group "

    it "completes group sub-options" $ do
      let cbs' = cbs { cbsInput = "group " }
          c1 = completeNext cbs'
      cbsInput c1 `shouldBe` "group tag"

    it "cycles through group sub-options" $ do
      let cbs' = cbs { cbsInput = "group " }
          c1 = completeNext cbs'
          c2 = completeNext c1
          c3 = completeNext c2
      cbsInput c1 `shouldBe` "group tag"
      cbsInput c2 `shouldBe` "group author"
      cbsInput c3 `shouldBe` "group none"

    it "completes sort sub-options" $ do
      let cbs' = cbs { cbsInput = "sort " }
          c1 = completeNext cbs'
      cbsInput c1 `shouldBe` "sort title"
