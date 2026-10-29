module Libri.TUI.Views.AddBook
  ( renderAddBook
  , renderEditBook
  , AddBookState (..)
  , initAddBookState
  , initEditBookState
  , updateCurrentField
  , parseList
  , joinList
  , parsePublishedField
  , applyLookup
  , filterRating
  , valueToText
  ) where

import Brick
import Brick.Widgets.Border (hBorder)
import Brick.Widgets.Center
import Control.Applicative ((<|>))
import Data.Aeson (Value(..))
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (Day, defaultTimeLocale, fromGregorian, parseTimeM)
import Lens.Micro ((^.), (&))
import Libri.TUI.Widgets.Common
import Libri.Types
import Text.Read (readMaybe)

-- | State for the add/edit book form
data AddBookState = AddBookState
  { absIsbn :: Text
  , absTitle :: Text
  , absAuthors :: Text        -- Semicolon-separated
  , absPublisher :: Text
  , absPublished :: Text      -- Year or full date
  , absLocation :: Text
  , absTags :: Text           -- Semicolon-separated
  , absRating :: Text         -- "1"-"5" or ""
  , absComments :: Text       -- Full text (display truncated)
  , absCustomFields :: [(Text, Text)]  -- List of (key, value)
  , absCustomFieldIdx :: Int  -- Selected custom field index
  , absEditingCustom :: Bool  -- Whether in custom field mode
  , absCurrentField :: Int    -- Which field is selected (0-9)
  , absIsEdit :: Bool
  , absOriginal :: Maybe Book -- Original book when editing, to preserve
                              -- fields the form does not expose
  }
  deriving (Show)

-- | Initialize add book state
initAddBookState :: AddBookState
initAddBookState = AddBookState
  { absIsbn = ""
  , absTitle = ""
  , absAuthors = ""
  , absPublisher = ""
  , absPublished = ""
  , absLocation = ""
  , absTags = ""
  , absRating = ""
  , absComments = ""
  , absCustomFields = []
  , absCustomFieldIdx = 0
  , absEditingCustom = False
  , absCurrentField = 0
  , absIsEdit = False
  , absOriginal = Nothing
  }

-- | Initialize edit state from existing book
initEditBookState :: Book -> AddBookState
initEditBookState book = AddBookState
  { absIsbn = maybe "" id (book ^. isbn)
  , absTitle = book ^. title
  , absAuthors = joinList (book ^. authors)
  , absPublisher = maybe "" id (book ^. publisher)
  , absPublished = maybe "" (T.pack . show) (book ^. published)
  , absLocation = maybe "" id (book ^. location)
  , absTags = joinList (book ^. tags)
  , absRating = maybe "" (T.pack . show) (book ^. rating)
  , absComments = maybe "" id (book ^. comments)
  , absCustomFields = Map.toList $ Map.map valueToText (book ^. custom)
  , absCustomFieldIdx = 0
  , absEditingCustom = False
  , absCurrentField = 0
  , absIsEdit = True
  , absOriginal = Just book
  }

-- | Convert Aeson Value to Text for display
valueToText :: Value -> Text
valueToText (String t) = t
valueToText (Number n) = T.pack (show n)
valueToText (Bool b) = if b then "true" else "false"
valueToText _ = ""

-- | Render the add book form
renderAddBook :: AddBookState -> Widget Name
renderAddBook st =
  if absEditingCustom st
    then renderCustomFieldsEditor st
    else centerLayer $
      titledBorder "Add New Book" $
        padAll 2 $
          vBox
            [ renderField 0 "ISBN" (absIsbn st) (absCurrentField st)
            , txt " "
            , renderField 1 "Title" (absTitle st) (absCurrentField st)
            , txt " "
            , renderField 2 "Authors" (absAuthors st) (absCurrentField st)
            , txt "(separated by ;)" & withAttr helpAttr
            , txt " "
            , renderField 3 "Publisher" (absPublisher st) (absCurrentField st)
            , txt " "
            , renderField 4 "Published" (absPublished st) (absCurrentField st)
            , txt "(year or YYYY-MM-DD)" & withAttr helpAttr
            , txt " "
            , renderField 5 "Location" (absLocation st) (absCurrentField st)
            , txt " "
            , renderField 6 "Tags" (absTags st) (absCurrentField st)
            , txt "(separated by ;)" & withAttr helpAttr
            , txt " "
            , renderRatingField 7 (absRating st) (absCurrentField st)
            , txt " "
            , renderCommentsField 8 (absComments st) (absCurrentField st)
            , txt " "
            , renderCustomFieldsPreview 9 (absCustomFields st) (absCurrentField st)
            , txt " "
            , withAttr helpAttr $ hBox
                [ txt "[Tab] Next  "
                , txt "[Enter] Save  "
                , txt "[Esc] Cancel  "
                , txt "[Ctrl+L] Lookup  "
                , txt "[Ctrl+E] Edit comments"
                ]
            ]

-- | Render the edit book form
renderEditBook :: AddBookState -> Widget Name
renderEditBook st =
  if absEditingCustom st
    then renderCustomFieldsEditor st
    else centerLayer $
      titledBorder "Edit Book" $
        padAll 2 $
          vBox
            [ renderField 0 "ISBN" (absIsbn st) (absCurrentField st)
            , txt " "
            , renderField 1 "Title" (absTitle st) (absCurrentField st)
            , txt " "
            , renderField 2 "Authors" (absAuthors st) (absCurrentField st)
            , txt "(separated by ;)" & withAttr helpAttr
            , txt " "
            , renderField 3 "Publisher" (absPublisher st) (absCurrentField st)
            , txt " "
            , renderField 4 "Published" (absPublished st) (absCurrentField st)
            , txt "(year or YYYY-MM-DD)" & withAttr helpAttr
            , txt " "
            , renderField 5 "Location" (absLocation st) (absCurrentField st)
            , txt " "
            , renderField 6 "Tags" (absTags st) (absCurrentField st)
            , txt "(separated by ;)" & withAttr helpAttr
            , txt " "
            , renderRatingField 7 (absRating st) (absCurrentField st)
            , txt " "
            , renderCommentsField 8 (absComments st) (absCurrentField st)
            , txt " "
            , renderCustomFieldsPreview 9 (absCustomFields st) (absCurrentField st)
            , txt " "
            , withAttr helpAttr $ hBox
                [ txt "[Tab] Next  "
                , txt "[Enter] Save  "
                , txt "[Esc] Cancel  "
                , txt "[Ctrl+E] Edit comments"
                ]
            ]

-- | Render a single form field
renderField :: Int -> Text -> Text -> Int -> Widget Name
renderField idx label value currentIdx =
  let isSelected = idx == currentIdx
      labelWidget = withAttr labelAttr $ txt $ label <> ": "
      cursor = if isSelected then "▋" else ""
      valueAttr' = if isSelected then selectedAttr else valueAttr
  in hBox
       [ padRight (Pad 1) $ hLimit 12 $ padLeft Max labelWidget
       , withAttr valueAttr' $ txtWrap $ value <> cursor
       ]

-- | Render rating field (1-5)
renderRatingField :: Int -> Text -> Int -> Widget Name
renderRatingField idx ratingVal currentIdx =
  let isSelected = idx == currentIdx
      labelWidget = withAttr labelAttr $ txt "Rating: "
      cursor = if isSelected then "▋" else ""
      valueAttr' = if isSelected then selectedAttr else valueAttr
      display = if T.null ratingVal then "" else ratingVal <> "/5"
  in hBox
       [ padRight (Pad 1) $ hLimit 12 $ padLeft Max labelWidget
       , withAttr valueAttr' $ txt $ display <> cursor
       , txt " "
       , withAttr helpAttr $ txt "(1-5)"
       ]

-- | Render comments field with truncated preview
renderCommentsField :: Int -> Text -> Int -> Widget Name
renderCommentsField idx commentsVal currentIdx =
  let isSelected = idx == currentIdx
      labelWidget = withAttr labelAttr $ txt "Comments: "
      valueAttr' = if isSelected then selectedAttr else valueAttr
      -- Truncate to ~40 chars for preview
      preview = if T.null commentsVal
                  then "(none)"
                  else let truncated = T.take 40 commentsVal
                       in if T.length commentsVal > 40
                            then truncated <> "..."
                            else truncated
      hint = if isSelected then " [Ctrl+E]" else ""
  in hBox
       [ padRight (Pad 1) $ hLimit 12 $ padLeft Max labelWidget
       , withAttr valueAttr' $ txt preview
       , withAttr helpAttr $ txt hint
       ]

-- | Render custom fields preview (for main form)
renderCustomFieldsPreview :: Int -> [(Text, Text)] -> Int -> Widget Name
renderCustomFieldsPreview idx customFields currentIdx =
  let isSelected = idx == currentIdx
      labelWidget = withAttr labelAttr $ txt "Custom: "
      valueAttr' = if isSelected then selectedAttr else valueAttr
      count = length customFields
      preview = if count == 0
                  then "(none)"
                  else T.pack (show count) <> " field(s)"
      hint = if isSelected then " [Enter to manage]" else ""
  in hBox
       [ padRight (Pad 1) $ hLimit 12 $ padLeft Max labelWidget
       , withAttr valueAttr' $ txt preview
       , withAttr helpAttr $ txt hint
       ]

-- | Render the custom fields editor (full screen mode)
renderCustomFieldsEditor :: AddBookState -> Widget Name
renderCustomFieldsEditor st =
  centerLayer $
    titledBorder "Custom Fields" $
      padAll 2 $
        vBox
          [ if null (absCustomFields st)
              then withAttr helpAttr $ txt "(no custom fields)"
              else vBox $ zipWith (renderCustomFieldItem (absCustomFieldIdx st)) [0..] (absCustomFields st)
          , txt " "
          , hBorder
          , txt " "
          , withAttr helpAttr $ vBox
              [ txt "[j/k] Navigate  [a] Add  [d] Delete"
              , txt "[r] Rename key  [Enter] Edit value  [Esc] Back"
              ]
          ]

-- | Render a single custom field item
renderCustomFieldItem :: Int -> Int -> (Text, Text) -> Widget Name
renderCustomFieldItem selectedIdx itemIdx (key, value) =
  let isSelected = selectedIdx == itemIdx
      prefix = if isSelected then "> " else "  "
      attr = if isSelected then selectedAttr else valueAttr
  in withAttr attr $ txt $ prefix <> key <> ": " <> value

-- | Filter rating input to only allow 1-5
filterRating :: Text -> Text
filterRating t =
  case T.unpack (T.filter (`elem` ("12345" :: String)) t) of
    [] -> ""
    (c:_) -> T.singleton c  -- Only keep first valid digit

-- | Update the currently selected field
updateCurrentField :: (Text -> Text) -> AddBookState -> AddBookState
updateCurrentField f st = case absCurrentField st of
  0 -> st { absIsbn = f (absIsbn st) }
  1 -> st { absTitle = f (absTitle st) }
  2 -> st { absAuthors = f (absAuthors st) }
  3 -> st { absPublisher = f (absPublisher st) }
  4 -> st { absPublished = f (absPublished st) }
  5 -> st { absLocation = f (absLocation st) }
  6 -> st { absTags = f (absTags st) }
  7 -> st { absRating = filterRating (f (absRating st)) }
  8 -> st  -- Comments edited via external editor, no direct input
  9 -> st  -- Custom fields have special handling
  _ -> st

-- | Separator for list fields (authors, tags) in the form. Not a
-- comma: Calibre tags and authors often contain commas themselves
-- ("Goya, Francisco, 1746-1828")
listSeparator :: Text
listSeparator = ";"

-- | Render a list field for editing
joinList :: [Text] -> Text
joinList = T.intercalate (listSeparator <> " ")

-- | Parse a list field back into its items
parseList :: Text -> [Text]
parseList =
  filter (not . T.null) . map T.strip . T.splitOn listSeparator

-- | Parse the published field: empty means no date; otherwise a full
-- date ("2020-01-31", the format the edit form displays) or a bare
-- year. Anything else is an error rather than a silently lost date.
parsePublishedField :: Text -> Either Text (Maybe Day)
parsePublishedField t
  | T.null s = Right Nothing
  | otherwise =
      maybe (Left $ "Published: expected a year or YYYY-MM-DD, got '" <> s <> "'")
            (Right . Just)
            (parseTimeM True defaultTimeLocale "%Y-%m-%d" (T.unpack s) <|> parseYear)
  where
    s = T.strip t
    parseYear = case readMaybe (T.unpack s) of
      Just year | year >= 1000 && year <= 9999 -> Just (fromGregorian year 1 1)
      _ -> Nothing

-- | Fill the form from an ISBN lookup. Only empty fields are filled,
-- so a lookup never overwrites what the user has already entered.
applyLookup :: Book -> AddBookState -> AddBookState
applyLookup book st = st
  { absTitle = fillEmpty (absTitle st) (book ^. title)
  , absAuthors = fillEmpty (absAuthors st) (joinList (book ^. authors))
  , absPublisher = fillEmpty (absPublisher st) (maybe "" id (book ^. publisher))
  , absPublished = fillEmpty (absPublished st) (maybe "" (T.pack . show) (book ^. published))
  , absLocation = fillEmpty (absLocation st) (maybe "" id (book ^. location))
  , absTags = fillEmpty (absTags st) (joinList (book ^. tags))
  }
  where
    fillEmpty current fetched
      | T.null (T.strip current) = fetched
      | otherwise = current
