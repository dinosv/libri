module Libri.TUI.Views.BookList
  ( renderBookList
  ) where

import Brick
import Brick.Widgets.Center
import Data.Text (Text)
import qualified Data.Text as T
import Lens.Micro ((^.))
import Libri.TUI.Widgets.Common
import Libri.Types

-- | Render the book list view
renderBookList :: [Book] -> Int -> Widget Name
renderBookList bks selectedIdx =
  if null bks
    then renderEmptyList
    else renderBooks bks selectedIdx

-- | Render when no books exist
renderEmptyList :: Widget Name
renderEmptyList =
  center $
    vBox
      [ withAttr headerAttr $ txt "No books in collection"
      , txt " "
      , txt "Press 'a' to add your first book"
      , txt "or use --import-calibre to import from Calibre"
      ]

-- | Render the list of books with viewport and scroll bar
renderBooks :: [Book] -> Int -> Widget Name
renderBooks bks selectedIdx =
  withVScrollBars OnRight $
    viewport BookListViewport Vertical $
      vBox $ zipWith (renderBookRow selectedIdx) [0..] bks

-- | Render a single book row
-- Uses 'visible' on selected row to enable auto-scroll in viewport
renderBookRow :: Int -> Int -> Book -> Widget Name
renderBookRow selectedIdx idx book =
  let isSelected = idx == selectedIdx
      attr = if isSelected then selectedAttr else mempty
      prefix = if isSelected then "> " else "  "
      titleText = truncateText 35 (book ^. title)
      authorText = truncateText 25 $ formatAuthors (book ^. authors)
      locationText = truncateText 15 $ maybe "-" id (book ^. location)
      row = withAttr attr $
              hBox
                [ txt prefix
                , padRight Max $ txt titleText
                , padRight (Pad 2) $ txt authorText
                , txt locationText
                ]
  in if isSelected
     then visible row
     else row

-- | Format authors list
formatAuthors :: [Text] -> Text
formatAuthors [] = "Unknown"
formatAuthors [a] = a
formatAuthors (a:_) = a <> " et al."

-- | Truncate text with ellipsis
truncateText :: Int -> Text -> Text
truncateText maxLen t
  | T.length t <= maxLen = t
  | otherwise = T.take (maxLen - 1) t <> "…"

