module Libri.TUI.Views.Search
  ( renderSearchBar
  , handleSearchEvent
  ) where

import Brick
import Data.Text (Text)
import qualified Data.Text as T
import Graphics.Vty.Input.Events
import Lens.Micro ((^.), (&), (.~))
import Libri.TUI.Widgets.Common
import Libri.Types

-- | Render the search bar
renderSearchBar :: Text -> Bool -> Widget Name
renderSearchBar query isActive =
  let prefix = if isActive then "/" else "Search: "
      attr = if isActive then searchAttr else helpAttr
      cursor = if isActive then "▋" else ""
  in withAttr attr $
       hBox
         [ txt prefix
         , txt query
         , txt cursor
         ]

-- | Handle events when search is active
handleSearchEvent :: BrickEvent Name e -> AppState -> EventM Name AppState ()
handleSearchEvent ev st = case ev of
  VtyEvent (EvKey KEsc []) ->
    -- Cancel search, return to list view
    put $ st & currentView .~ ViewList
               & searchQuery .~ ""

  VtyEvent (EvKey KEnter []) ->
    -- Confirm search, return to list view with filter active
    put $ st & currentView .~ ViewList

  VtyEvent (EvKey KBS []) ->
    -- Backspace: delete last character
    let query = st ^. searchQuery
    in put $ st & searchQuery .~ T.dropEnd 1 query

  VtyEvent (EvKey (KChar c) []) ->
    -- Add character to search query
    put $ st & searchQuery .~ (st ^. searchQuery <> T.singleton c)

  _ -> pure ()
