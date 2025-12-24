module Libri.TUI.Views.BookDetails
  ( renderBookDetails
  ) where

import Brick
import Brick.Widgets.Border
import Brick.Widgets.Center (center)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Aeson (Value (..))
import Data.Text (Text)
import qualified Data.Text as T
import Lens.Micro ((^.))
import Libri.TUI.Widgets.Common
import Libri.Types

-- | Render the book details panel
renderBookDetails :: Maybe Book -> Widget Name
renderBookDetails Nothing =
  center $ withAttr helpAttr $ txt "No book selected"
renderBookDetails (Just book) =
  padAll 1 $
    vBox
      [ renderTitle book
      , txt " "
      , renderAuthors book
      , renderSeries book
      , renderPublisher book
      , renderPublished book
      , txt " "
      , renderISBN book
      , renderLocation book
      , renderRating book
      , txt " "
      , renderTags book
      , txt " "
      , renderComments book
      , renderCustom book
      ]

-- | Render book title
renderTitle :: Book -> Widget n
renderTitle book =
  withAttr titleAttr $
    txtWrap (book ^. title)

-- | Render authors
renderAuthors :: Book -> Widget n
renderAuthors book =
  case book ^. authors of
    [] -> labeledField "Authors" "-"
    as -> labeledField "Authors" $ T.intercalate ", " as

-- | Render series info
renderSeries :: Book -> Widget n
renderSeries book =
  case book ^. series of
    Nothing -> emptyWidget  -- Series is optional, hide if not set
    Just s ->
      let indexText = case book ^. seriesIndex of
            Nothing -> ""
            Just idx -> " #" <> T.pack (show idx)
      in labeledField "Series" $ s <> indexText

-- | Render publisher
renderPublisher :: Book -> Widget n
renderPublisher book =
  case book ^. publisher of
    Nothing -> labeledField "Publisher" "-"
    Just p -> labeledField "Publisher" p

-- | Render publication date
renderPublished :: Book -> Widget n
renderPublished book =
  case book ^. published of
    Nothing -> labeledField "Published" "-"
    Just d -> labeledField "Published" $ T.pack $ show d

-- | Render ISBN
renderISBN :: Book -> Widget n
renderISBN book =
  case book ^. isbn of
    Nothing -> labeledField "ISBN" "-"
    Just i -> labeledField "ISBN" i

-- | Render location
renderLocation :: Book -> Widget n
renderLocation book =
  case book ^. location of
    Nothing -> labeledField "Location" "-"
    Just loc -> labeledField "Location" loc

-- | Render rating as stars
renderRating :: Book -> Widget n
renderRating book =
  case book ^. rating of
    Nothing -> labeledField "Rating" "-"
    Just r ->
      let stars = T.replicate r "★" <> T.replicate (5 - r) "☆"
      in hBox
           [ withAttr labelAttr $ txt "Rating: "
           , withAttr ratingAttr $ txt stars
           ]

-- | Render tags
renderTags :: Book -> Widget n
renderTags book =
  case book ^. tags of
    [] -> labeledField "Tags" "-"
    ts -> labeledField "Tags" $ T.intercalate ", " ts

-- | Render comments (truncated)
renderComments :: Book -> Widget n
renderComments book =
  case book ^. comments of
    Nothing -> emptyWidget
    Just c ->
      vBox
        [ withAttr labelAttr $ txt "Comments:"
        , padLeft (Pad 2) $ txtWrap $ truncateComments 300 c
        ]

-- | Render custom fields
renderCustom :: Book -> Widget n
renderCustom book =
  let customFields = book ^. custom
  in if Map.null customFields
       then emptyWidget
       else vBox
              [ txt " "
              , withAttr labelAttr $ txt "Custom fields:"
              , padLeft (Pad 2) $ vBox $ map renderCustomField $ Map.toList customFields
              ]

-- | Render a single custom field
renderCustomField :: (Text, Value) -> Widget n
renderCustomField (key, val) =
  hBox
    [ withAttr labelAttr $ txt $ key <> ": "
    , txt $ valueToText val
    ]

-- | Convert JSON Value to Text for display
valueToText :: Value -> Text
valueToText (String t) = t
valueToText (Number n) = T.pack $ show n
valueToText (Bool b) = if b then "Yes" else "No"
valueToText Null = "-"
valueToText (Array _) = "[array]"
valueToText (Object _) = "{object}"

-- | Helper for labeled fields
labeledField :: Text -> Text -> Widget n
labeledField label value =
  hBox
    [ withAttr labelAttr $ txt $ label <> ": "
    , withAttr valueAttr $ txt value
    ]

-- | Truncate comments with ellipsis
truncateComments :: Int -> Text -> Text
truncateComments maxLen t
  | T.length t <= maxLen = t
  | otherwise = T.take maxLen t <> "..."
