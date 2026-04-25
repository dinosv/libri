module Libri.TUI.CommandBar
  ( Command (..)
  , CommandBarState (..)
  , parseCommand
  , initCommandBarState
  , completeNext
  , renderCommandBar
  ) where

import Brick
import Data.Text (Text)
import qualified Data.Text as T
import Libri.Text.Normalize (normalizeText)
import Libri.TUI.Widgets.Common (Name, commandBarAttr)
import Libri.Types (SortField (..), GroupField (..))

data Command
  = CmdFilterTag Text
  | CmdFilterAuthor Text
  | CmdGroup GroupField
  | CmdGroupNone
  | CmdSort SortField
  | CmdClear
  | CmdNeedsArg Text Text
  | CmdUnknown Text
  deriving (Show, Eq)

data CommandBarState = CommandBarState
  { cbsInput :: Text
  , cbsTagCandidates :: [Text]
  , cbsAuthorCandidates :: [Text]
  , cbsCompletionIndex :: Maybe Int
  , cbsLastPrefix :: Text
  , cbsCompletingCommand :: Bool
  }
  deriving (Show)

initCommandBarState :: [Text] -> [Text] -> CommandBarState
initCommandBarState tagCandidates authorCandidates = CommandBarState
  { cbsInput = ""
  , cbsTagCandidates = tagCandidates
  , cbsAuthorCandidates = authorCandidates
  , cbsCompletionIndex = Nothing
  , cbsLastPrefix = ""
  , cbsCompletingCommand = False
  }

parseCommand :: Text -> Command
parseCommand input =
  let stripped = T.strip input
      (cmd, rest) = T.breakOn " " stripped
      arg = T.strip (T.drop 1 rest)
  in case T.toLower cmd of
    "tag"    | not (T.null arg) -> CmdFilterTag arg
             | otherwise        -> CmdNeedsArg "tag" "tag <name> -- e.g. tag Philosophy"
    "author" | not (T.null arg) -> CmdFilterAuthor arg
             | otherwise        -> CmdNeedsArg "author" "author <name> -- e.g. author Eco"
    "group"  -> case T.toLower arg of
      "tag"    -> CmdGroup GroupByTag
      "author" -> CmdGroup GroupByAuthor
      "none"   -> CmdGroupNone
      ""       -> CmdNeedsArg "group" "group <tag|author|none>"
      _        -> CmdUnknown stripped
    "sort"   -> case T.toLower arg of
      "title"  -> CmdSort SortByTitle
      "author" -> CmdSort SortByAuthor
      "date"   -> CmdSort SortByDate
      ""       -> CmdNeedsArg "sort" "sort <title|author|date>"
      _        -> CmdUnknown stripped
    "clear"  -> CmdClear
    _        -> CmdUnknown stripped

commandKeywords :: [Text]
commandKeywords = ["tag", "author", "group", "sort", "clear"]

groupSubOptions :: [Text]
groupSubOptions = ["tag", "author", "none"]

sortSubOptions :: [Text]
sortSubOptions = ["title", "author", "date"]

completeNext :: CommandBarState -> CommandBarState
completeNext cbs
  | cbsCompletingCommand cbs = completeCommandLevel cbs
  | not hasSpace              = completeCommandLevel cbs
  | otherwise                 = completeArgLevel cbs
  where
    (_, rest) = T.breakOn " " (cbsInput cbs)
    hasSpace = not (T.null rest)

completeCommandLevel :: CommandBarState -> CommandBarState
completeCommandLevel cbs =
  let prefix = if cbsCompletionIndex cbs == Nothing
                 then T.stripEnd (cbsInput cbs)
                 else cbsLastPrefix cbs
      result = completeFrom commandKeywords prefix cbs (\chosen -> chosen <> " ")
  in result { cbsCompletingCommand = True }

completeArgLevel :: CommandBarState -> CommandBarState
completeArgLevel cbs =
  let (cmd, rest) = T.breakOn " " (cbsInput cbs)
      prefix = if cbsCompletionIndex cbs == Nothing
                 then T.strip (T.drop 1 rest)
                 else cbsLastPrefix cbs
      candidates = case T.toLower cmd of
        "tag"    -> cbsTagCandidates cbs
        "author" -> cbsAuthorCandidates cbs
        "group"  -> groupSubOptions
        "sort"   -> sortSubOptions
        _        -> []
  in completeFrom candidates prefix cbs (\chosen -> cmd <> " " <> chosen)

completeFrom :: [Text] -> Text -> CommandBarState -> (Text -> Text) -> CommandBarState
completeFrom candidates prefix cbs buildInput =
  let normPrefix = normalizeText prefix
      matches = if T.null normPrefix
                  then candidates
                  else filter (\c -> normPrefix `T.isPrefixOf` normalizeText c) candidates
  in if null matches
       then cbs
       else
         let idx = case cbsCompletionIndex cbs of
               Nothing -> 0
               Just i  -> (i + 1) `mod` length matches
             chosen = matches !! idx
         in cbs
           { cbsInput = buildInput chosen
           , cbsCompletionIndex = Just idx
           , cbsLastPrefix = prefix
           }

renderCommandBar :: CommandBarState -> Widget Name
renderCommandBar cbs =
  withAttr commandBarAttr $
    hBox
      [ txt ":"
      , txt (cbsInput cbs)
      , txt "▋"
      ]
