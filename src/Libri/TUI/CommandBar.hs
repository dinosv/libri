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
  | CmdUnknown Text
  deriving (Show, Eq)

data CommandBarState = CommandBarState
  { cbsInput :: Text
  , cbsTagCandidates :: [Text]
  , cbsAuthorCandidates :: [Text]
  , cbsCompletionIndex :: Maybe Int
  , cbsLastPrefix :: Text
  }
  deriving (Show)

initCommandBarState :: [Text] -> [Text] -> CommandBarState
initCommandBarState tagCandidates authorCandidates = CommandBarState
  { cbsInput = ""
  , cbsTagCandidates = tagCandidates
  , cbsAuthorCandidates = authorCandidates
  , cbsCompletionIndex = Nothing
  , cbsLastPrefix = ""
  }

parseCommand :: Text -> Command
parseCommand input =
  let stripped = T.strip input
      (cmd, rest) = T.breakOn " " stripped
      arg = T.strip (T.drop 1 rest)
  in case T.toLower cmd of
    "tag"    | not (T.null arg) -> CmdFilterTag arg
    "author" | not (T.null arg) -> CmdFilterAuthor arg
    "group"  -> case T.toLower arg of
      "tag"    -> CmdGroup GroupByTag
      "author" -> CmdGroup GroupByAuthor
      "none"   -> CmdGroupNone
      _        -> CmdUnknown stripped
    "sort"   -> case T.toLower arg of
      "title"  -> CmdSort SortByTitle
      "author" -> CmdSort SortByAuthor
      "date"   -> CmdSort SortByDate
      _        -> CmdUnknown stripped
    "clear"  -> CmdClear
    _        -> CmdUnknown stripped

completeNext :: CommandBarState -> CommandBarState
completeNext cbs =
  let input = cbsInput cbs
      (cmd, rest) = T.breakOn " " input
      hasSpace = T.length rest > 0
  in if not hasSpace
       then cbs
       else
         let prefix = if cbsCompletionIndex cbs == Nothing
                        then T.strip (T.drop 1 rest)
                        else cbsLastPrefix cbs
             candidates = case T.toLower cmd of
               "tag"    -> cbsTagCandidates cbs
               "author" -> cbsAuthorCandidates cbs
               _        -> []
             normPrefix = normalizeText prefix
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
                  { cbsInput = cmd <> " " <> chosen
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
