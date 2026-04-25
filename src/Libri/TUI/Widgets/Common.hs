module Libri.TUI.Widgets.Common
  ( -- * Resource Names
    Name (..)
    -- * Attributes
  , theMap
  , titleAttr
  , selectedAttr
  , headerAttr
  , labelAttr
  , valueAttr
  , ratingAttr
  , helpAttr
  , errorAttr
  , searchAttr
  , commandBarAttr
  , sectionHeaderAttr
    -- * Common Widgets
  , bordered
  , titledBorder
  , padded
  , centeredText
  , keyHelp
  ) where

import Brick
import Brick.Widgets.Border
import Brick.Widgets.Border.Style
import Brick.Widgets.Center
import Data.Text (Text)
import Graphics.Vty.Attributes

-- | Resource names for widgets
data Name
  = BookList
  | BookListViewport
  | BookDetails
  | SearchField
  | CommandBarField
  | AddForm
  | EditForm
  | LocationList
  | HelpView
  deriving (Eq, Ord, Show)

-- | Attribute map for the application
theMap :: AttrMap
theMap = attrMap defAttr
  [ (titleAttr, fg brightWhite `withStyle` bold)
  , (selectedAttr, black `on` cyan)
  , (headerAttr, fg brightCyan `withStyle` bold)
  , (labelAttr, fg yellow)
  , (valueAttr, fg white)
  , (ratingAttr, fg yellow)
  , (helpAttr, fg brightBlack)
  , (errorAttr, fg red `withStyle` bold)
  , (searchAttr, fg brightGreen)
  , (commandBarAttr, fg brightYellow)
  , (sectionHeaderAttr, fg brightCyan `withStyle` bold)
  , (borderAttr, fg brightBlack)
  ]

-- | Attribute names
titleAttr :: AttrName
titleAttr = attrName "title"

selectedAttr :: AttrName
selectedAttr = attrName "selected"

headerAttr :: AttrName
headerAttr = attrName "header"

labelAttr :: AttrName
labelAttr = attrName "label"

valueAttr :: AttrName
valueAttr = attrName "value"

ratingAttr :: AttrName
ratingAttr = attrName "rating"

helpAttr :: AttrName
helpAttr = attrName "help"

errorAttr :: AttrName
errorAttr = attrName "error"

searchAttr :: AttrName
searchAttr = attrName "search"

commandBarAttr :: AttrName
commandBarAttr = attrName "commandBar"

sectionHeaderAttr :: AttrName
sectionHeaderAttr = attrName "sectionHeader"

-- | Add a unicode border around a widget
bordered :: Widget n -> Widget n
bordered = withBorderStyle unicode . border

-- | Add a titled border
titledBorder :: Text -> Widget n -> Widget n
titledBorder title w =
  withBorderStyle unicode $
    borderWithLabel (withAttr titleAttr $ txt $ " " <> title <> " ") w

-- | Add padding around a widget
padded :: Widget n -> Widget n
padded = padAll 1

-- | Center text horizontally
centeredText :: Text -> Widget n
centeredText = hCenter . txt

-- | Display key help at the bottom
keyHelp :: [(Text, Text)] -> Widget n
keyHelp keys =
  withAttr helpAttr $
    hBox $
      map renderKey keys
  where
    renderKey (key, desc) =
      padRight (Pad 2) $
        hBox
          [ withAttr labelAttr $ txt $ "[" <> key <> "]"
          , txt " "
          , txt desc
          ]
