module Libri.TUI.Views.TagSidebar
  ( TagEntry (..)
  , buildTagEntries
  , entryToFilter
  , entryLabel
  , renderTagSidebar
  ) where

import Brick
import Data.List (nub, sortBy)
import qualified Data.Map.Strict as Map
import Data.Ord (comparing)
import Data.Text (Text)
import qualified Data.Text as T
import Lens.Micro ((^.))
import Libri.Text.Normalize (normalizeText)
import Libri.TUI.Widgets.Common
import Libri.Types

-- | One selectable row in the tag sidebar
data TagEntry
  = AllBooks Int      -- ^ Whole collection; selecting clears the filter
  | TagEntry Text Int -- ^ A tag and its book count
  | Untagged Int      -- ^ Books with no tags
  deriving (Show, Eq)

-- | Build the sidebar entries from the full collection: All first,
-- tags alphabetically (accents folded), Untagged last when non-empty
buildTagEntries :: [Book] -> [TagEntry]
buildTagEntries bks =
  let counts = Map.fromListWith (+)
        [(t, 1 :: Int) | b <- bks, t <- nub (b ^. tags)]
      sorted = sortBy (comparing (normalizeText . fst)) (Map.toList counts)
      untaggedCount = length (filter (null . (^. tags)) bks)
      untagged = [Untagged untaggedCount | untaggedCount > 0]
  in AllBooks (length bks) : map (uncurry TagEntry) sorted ++ untagged

-- | The filter a sidebar entry stands for; All clears the filter
entryToFilter :: TagEntry -> Maybe Filter
entryToFilter (AllBooks _) = Nothing
entryToFilter (TagEntry t _) = Just (FilterTagExact t)
entryToFilter (Untagged _) = Just FilterUntagged

-- | Display label of an entry (without the count)
entryLabel :: TagEntry -> Text
entryLabel (AllBooks _) = "All"
entryLabel (TagEntry t _) = t
entryLabel (Untagged _) = "(Untagged)"

-- | Render the sidebar. The selection marker is shown only when the
-- sidebar has focus; the entry matching the active filter stays
-- highlighted either way.
renderTagSidebar :: [TagEntry] -> Int -> Bool -> Maybe Filter -> Widget Name
renderTagSidebar entries selectedIdx focused activeF =
  withVScrollBars OnRight $
    viewport TagSidebarViewport Vertical $
      vBox $ zipWith renderEntry [0..] entries
  where
    renderEntry idx entry =
      let isSelected = focused && idx == selectedIdx
          isActive = entryToFilter entry == activeF && activeF /= Nothing
          attr
            | isSelected = selectedAttr
            | isActive = labelAttr
            | otherwise = mempty
          prefix = if isSelected then "> " else "  "
          count = case entry of
            AllBooks n -> n
            TagEntry _ n -> n
            Untagged n -> n
          row = withAttr attr $
            hBox
              [ txt prefix
              , padRight Max $ txt $ truncateLabel 14 (entryLabel entry)
              , txt $ T.pack (show count)
              ]
      in if isSelected then visible row else row

    truncateLabel maxLen t
      | T.length t <= maxLen = t
      | otherwise = T.take (maxLen - 1) t <> "…"
