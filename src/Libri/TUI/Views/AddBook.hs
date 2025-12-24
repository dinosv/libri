module Libri.TUI.Views.AddBook
  ( renderAddBook
  , renderEditBook
  , AddBookState (..)
  , initAddBookState
  , initEditBookState
  , updateCurrentField
  , parseCommaSeparated
  , filterRating
  ) where

import Brick
import Brick.Widgets.Border
import Brick.Widgets.Center
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Value(..))
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (getCurrentTime)
import Graphics.Vty.Input.Events
import Lens.Micro ((^.), (&), (.~))
import Libri.TUI.Widgets.Common
import Libri.Types

-- | State for the add/edit book form
data AddBookState = AddBookState
  { absIsbn :: Text
  , absTitle :: Text
  , absAuthors :: Text        -- Comma-separated
  , absPublisher :: Text
  , absPublished :: Text      -- Year (e.g., "2024")
  , absLocation :: Text
  , absTags :: Text           -- Comma-separated
  , absRating :: Text         -- "1"-"5" or ""
  , absComments :: Text       -- Full text (display truncated)
  , absCustomFields :: [(Text, Text)]  -- List of (key, value)
  , absCustomFieldIdx :: Int  -- Selected custom field index
  , absEditingCustom :: Bool  -- Whether in custom field mode
  , absCurrentField :: Int    -- Which field is selected (0-9)
  , absIsEdit :: Bool         -- True if editing existing book
  , absOriginalId :: Maybe BookId
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
  , absOriginalId = Nothing
  }

-- | Initialize edit state from existing book
initEditBookState :: Book -> AddBookState
initEditBookState book = AddBookState
  { absIsbn = maybe "" id (book ^. isbn)
  , absTitle = book ^. title
  , absAuthors = T.intercalate ", " (book ^. authors)
  , absPublisher = maybe "" id (book ^. publisher)
  , absPublished = maybe "" (T.pack . show) (book ^. published)
  , absLocation = maybe "" id (book ^. location)
  , absTags = T.intercalate ", " (book ^. tags)
  , absRating = maybe "" (T.pack . show) (book ^. rating)
  , absComments = maybe "" id (book ^. comments)
  , absCustomFields = Map.toList $ Map.map valueToText (book ^. custom)
  , absCustomFieldIdx = 0
  , absEditingCustom = False
  , absCurrentField = 0
  , absIsEdit = True
  , absOriginalId = Just (book ^. bookId)
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
            , txt "(comma-separated)" & withAttr helpAttr
            , txt " "
            , renderField 3 "Publisher" (absPublisher st) (absCurrentField st)
            , txt " "
            , renderField 4 "Published" (absPublished st) (absCurrentField st)
            , txt "(year, e.g. 2024)" & withAttr helpAttr
            , txt " "
            , renderField 5 "Location" (absLocation st) (absCurrentField st)
            , txt " "
            , renderField 6 "Tags" (absTags st) (absCurrentField st)
            , txt "(comma-separated)" & withAttr helpAttr
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
            , txt "(comma-separated)" & withAttr helpAttr
            , txt " "
            , renderField 3 "Publisher" (absPublisher st) (absCurrentField st)
            , txt " "
            , renderField 4 "Published" (absPublished st) (absCurrentField st)
            , txt "(year, e.g. 2024)" & withAttr helpAttr
            , txt " "
            , renderField 5 "Location" (absLocation st) (absCurrentField st)
            , txt " "
            , renderField 6 "Tags" (absTags st) (absCurrentField st)
            , txt "(comma-separated)" & withAttr helpAttr
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

-- | Handle events in add/edit book form
handleAddBookEvent
  :: BrickEvent Name e
  -> AddBookState
  -> EventM Name (Either AddBookState Book) ()
handleAddBookEvent ev st = case ev of
  VtyEvent (EvKey KEsc []) ->
    -- Cancel, return to list
    halt

  VtyEvent (EvKey KEnter []) ->
    -- Save the book
    if T.null (absTitle st)
      then pure ()  -- Don't save without title
      else do
        now <- liftIO getCurrentTime
        let book = Book
              { _bookId = maybe (absIsbn st) id (absOriginalId st)
              , _isbn = if T.null (absIsbn st) then Nothing else Just (absIsbn st)
              , _title = absTitle st
              , _authors = parseCommaSeparated (absAuthors st)
              , _series = Nothing
              , _seriesIndex = Nothing
              , _publisher = Nothing
              , _published = Nothing
              , _tags = parseCommaSeparated (absTags st)
              , _rating = Nothing
              , _comments = Nothing
              , _location = if T.null (absLocation st) then Nothing else Just (absLocation st)
              , _custom = mempty
              , _added = now
              , _modified = now
              }
        put (Right book)
        halt

  VtyEvent (EvKey (KChar '\t') []) ->
    -- Move to next field
    put $ Left $ st { absCurrentField = (absCurrentField st + 1) `mod` 10 }

  VtyEvent (EvKey KBackTab []) ->
    -- Move to previous field
    put $ Left $ st { absCurrentField = (absCurrentField st - 1 + 10) `mod` 10 }

  VtyEvent (EvKey KBS []) ->
    -- Backspace in current field
    put $ Left $ updateCurrentField (T.dropEnd 1) st

  VtyEvent (EvKey (KChar c) []) ->
    -- Add character to current field
    put $ Left $ updateCurrentField (<> T.singleton c) st

  _ -> pure ()

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

-- | Parse comma-separated values
parseCommaSeparated :: Text -> [Text]
parseCommaSeparated =
  filter (not . T.null) . map T.strip . T.splitOn ","
