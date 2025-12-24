module Libri.TUI.Views.MoveBook
  ( renderMoveBook
  , MoveBookState (..)
  , initMoveBookState
  ) where

import Brick hiding (Location)
import Brick.Widgets.Border
import Brick.Widgets.Center
import Data.Text (Text)
import qualified Data.Text as T
import Lens.Micro ((^.))
import Libri.TUI.Widgets.Common
import Libri.Types (Book, BookId, Location, bookId, title, location)

-- | State for the move book dialog
data MoveBookState = MoveBookState
  { mbsBookId :: BookId
  , mbsBookTitle :: Text
  , mbsCurrentLocation :: Maybe Text
  , mbsLocations :: [Location]
  , mbsSelectedIndex :: Int
  }
  deriving (Show)

-- | Initialize move state from a book and available locations
initMoveBookState :: Book -> [Location] -> MoveBookState
initMoveBookState book locs = MoveBookState
  { mbsBookId = book ^. bookId
  , mbsBookTitle = book ^. title
  , mbsCurrentLocation = book ^. location
  , mbsLocations = locs
  , mbsSelectedIndex = findCurrentIdx
  }
  where
    findCurrentIdx = case book ^. location of
      Nothing -> 0
      Just loc -> max 0 $ maybe 0 id $ findIndex (== loc) locs
    findIndex _ [] = Nothing
    findIndex p (x:xs)
      | p x = Just 0
      | otherwise = (+ 1) <$> findIndex p xs

-- | Render the move book dialog
renderMoveBook :: MoveBookState -> Widget Name
renderMoveBook st =
  centerLayer $
    titledBorder "Move Book" $
      padAll 2 $
        vBox
          [ withAttr labelAttr $ txt "Book: "
          , padLeft (Pad 2) $ txt (mbsBookTitle st)
          , txt " "
          , withAttr labelAttr $ txt "Current location: "
          , padLeft (Pad 2) $ txt $ maybe "(none)" id (mbsCurrentLocation st)
          , txt " "
          , hBorder
          , txt " "
          , withAttr labelAttr $ txt "Select new location:"
          , txt " "
          , vBox $ zipWith (renderLocationItem (mbsSelectedIndex st)) [0..] (mbsLocations st)
          , txt " "
          , hBorder
          , txt " "
          , withAttr helpAttr $ hBox
              [ txt "[j/k/↑/↓] Select  "
              , txt "[Enter] Confirm  "
              , txt "[Esc] Cancel"
              ]
          ]

-- | Render a single location item
renderLocationItem :: Int -> Int -> Location -> Widget Name
renderLocationItem selectedIdx idx loc =
  let isSelected = idx == selectedIdx
      prefix = if isSelected then "> " else "  "
      attr = if isSelected then selectedAttr else valueAttr
  in withAttr attr $ txt $ prefix <> loc
