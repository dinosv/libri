module Libri.TUI.Views.Search
  ( renderSearchBar
  ) where

import Brick
import Data.Text (Text)
import Libri.TUI.Widgets.Common

-- | Render the search bar
renderSearchBar :: Text -> Bool -> Widget Name
renderSearchBar query isActive =
  let prefix = if isActive then "/" else "Search: "
      attr' = if isActive then searchAttr else helpAttr
      cursor = if isActive then "▋" else ""
  in withAttr attr' $
       hBox
         [ txt prefix
         , txt query
         , txt cursor
         ]
