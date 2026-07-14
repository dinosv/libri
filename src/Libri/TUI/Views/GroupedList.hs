module Libri.TUI.Views.GroupedList
  ( ListItem (..)
  , buildGroupedList
  , renderGroupedList
  , nextSelectableIndex
  , prevSelectableIndex
  , firstSelectableIndex
  , lastSelectableIndex
  ) where

import Brick
import Data.List (sortBy)
import qualified Data.Map.Strict as Map
import Data.Ord (comparing)
import Data.Text (Text)
import qualified Data.Text as T
import Lens.Micro ((^.))
import Libri.TUI.Widgets.Common
import Libri.Types

data ListItem
  = SectionHeader Text Int
  | BookRow Book
  deriving (Show, Eq)

buildGroupedList :: GroupField -> SortField -> SortOrder -> [Book] -> [ListItem]
buildGroupedList field sortF sortO bks =
  let grouped = groupBooks field bks
      untaggedKey = if field == GroupByTag then "(Untagged)" else "(Unknown)"
      -- Only the active sentinel is special-cased; a real tag/author that
      -- happens to match the other mode's sentinel must not disappear
      sortedKeys = sortBy (comparing fst)
                   [(k, vs) | (k, vs) <- Map.toList grouped, k /= untaggedKey]
      untagged = Map.lookup untaggedKey grouped
      sections = map (buildSection sortF sortO) sortedKeys
      untaggedSection = case untagged of
        Nothing -> []
        Just us -> buildSection sortF sortO (untaggedKey, us)
  in concat sections ++ untaggedSection

groupBooks :: GroupField -> [Book] -> Map.Map Text [Book]
groupBooks GroupByTag bks = foldr addByTag Map.empty bks
  where
    addByTag book acc =
      case book ^. tags of
        [] -> Map.insertWith (++) "(Untagged)" [book] acc
        ts -> foldr (\t m -> Map.insertWith (++) t [book] m) acc ts
groupBooks GroupByAuthor bks = foldr addByAuthor Map.empty bks
  where
    addByAuthor book acc =
      case book ^. authors of
        [] -> Map.insertWith (++) "(Unknown)" [book] acc
        as -> foldr (\a m -> Map.insertWith (++) a [book] m) acc as

buildSection :: SortField -> SortOrder -> (Text, [Book]) -> [ListItem]
buildSection sortF sortO (name, sectionBooks) =
  let sorted = applySortOrder' sortF sortO sectionBooks
  in SectionHeader name (length sectionBooks) : map BookRow sorted

applySortOrder' :: SortField -> SortOrder -> [Book] -> [Book]
applySortOrder' field order bks =
  let cmp = case field of
        SortByTitle  -> comparing (T.toLower . (^. title))
        SortByAuthor -> comparing (T.toLower . head' . (^. authors))
        SortByDate   -> comparing (^. published)
      sorted = sortBy cmp bks
  in case order of
       Ascending  -> sorted
       Descending -> reverse sorted
  where
    head' [] = ""
    head' (x:_) = x

renderGroupedList :: [ListItem] -> Int -> Widget Name
renderGroupedList items selectedIdx =
  if null items
    then txt "No books to display"
    else withVScrollBars OnRight $
           viewport BookListViewport Vertical $
             vBox $ zipWith (renderItem selectedIdx) [0..] items

renderItem :: Int -> Int -> ListItem -> Widget Name
renderItem _ _ (SectionHeader name count) =
  withAttr sectionHeaderAttr $
    padRight Max $
      txt $ "── " <> name <> " (" <> T.pack (show count) <> ") " <>
            T.replicate 40 "─"
renderItem selectedIdx idx (BookRow book) =
  let isSelected = idx == selectedIdx
      attr = if isSelected then selectedAttr else mempty
      prefix = if isSelected then "> " else "  "
      titleText = truncateText' 35 (book ^. title)
      authorText = truncateText' 25 $ formatAuthors' (book ^. authors)
      row = withAttr attr $
              hBox
                [ txt prefix
                , padRight Max $ txt titleText
                , padRight (Pad 2) $ txt authorText
                ]
  in if isSelected then visible row else row

truncateText' :: Int -> Text -> Text
truncateText' maxLen t
  | T.length t <= maxLen = t
  | otherwise = T.take (maxLen - 1) t <> "…"

formatAuthors' :: [Text] -> Text
formatAuthors' [] = "Unknown"
formatAuthors' [a] = a
formatAuthors' (a:_) = a <> " et al."

nextSelectableIndex :: [ListItem] -> Int -> Int
nextSelectableIndex items current =
  let candidates = [i | (i, item) <- zip [0..] items, i > current, isBookRow item]
  in case candidates of
       (x:_) -> x
       []    -> current

prevSelectableIndex :: [ListItem] -> Int -> Int
prevSelectableIndex items current =
  let candidates = reverse [i | (i, item) <- zip [0..] items, i < current, isBookRow item]
  in case candidates of
       (x:_) -> x
       []    -> current

firstSelectableIndex :: [ListItem] -> Int
firstSelectableIndex items =
  case [i | (i, item) <- zip [0..] items, isBookRow item] of
    (x:_) -> x
    []    -> 0

lastSelectableIndex :: [ListItem] -> Int
lastSelectableIndex items =
  case reverse [i | (i, item) <- zip [0..] items, isBookRow item] of
    (x:_) -> x
    []    -> 0

isBookRow :: ListItem -> Bool
isBookRow (BookRow _) = True
isBookRow _ = False
