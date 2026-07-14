module Libri.CLI.Tags
  ( renameTag
  , deleteTag
  , runTagRename
  , runTagDelete
  ) where

import Control.Monad (forM, forM_)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Lens.Micro ((^.), (&), (.~))
import Libri.Storage.Yaml (loadBooksWithErrors, saveBook)
import Libri.Text.Normalize (normalizeText)
import Libri.Types
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

-- | Rename every tag normalised-equal to the old name, then
-- deduplicate (renaming onto an existing tag merges them).
-- Returns Nothing when the list is unchanged.
renameTag :: Text -> Text -> [Text] -> Maybe [Text]
renameTag old new tagList
  | not (any (`sameTag` old) tagList) = Nothing
  | otherwise =
      let renamed = map (\t -> if sameTag t old then new else t) tagList
          deduped = dedupeTags renamed
      in if deduped == tagList then Nothing else Just deduped

-- | Remove every tag normalised-equal to the given name.
-- Returns Nothing when the list is unchanged.
deleteTag :: Text -> [Text] -> Maybe [Text]
deleteTag tag tagList =
  let remaining = filter (not . (`sameTag` tag)) tagList
  in if remaining == tagList then Nothing else Just remaining

sameTag :: Text -> Text -> Bool
sameTag a b = normalizeText a == normalizeText b

-- | Keep the first spelling of each tag, dropping later duplicates
dedupeTags :: [Text] -> [Text]
dedupeTags = go []
  where
    go _ [] = []
    go seen (t : ts)
      | normalizeText t `elem` seen = go seen ts
      | otherwise = t : go (normalizeText t : seen) ts

-- | Apply a tag-list transformation to every affected book and save
applyTagChange :: Config -> (Book -> Maybe [Text]) -> IO Int
applyTagChange cfg change = do
  (loadErrs, bks) <- loadBooksWithErrors cfg
  forM_ loadErrs $ \(path, err) ->
    hPutStrLn stderr $ "Warning: skipping unreadable book file " <> path <> ": " <> show err
  results <- forM bks $ \book ->
    case change book of
      Nothing -> pure (Right False)
      Just newTags -> do
        result <- saveBook cfg (book & tags .~ newTags)
        case result of
          Left err -> do
            hPutStrLn stderr $ "Error saving '" <> T.unpack (book ^. title) <> "': " <> show err
            pure (Left ())
          Right () -> pure (Right True)
  case length [() | Left () <- results] of
    0 -> pure $ length [() | Right True <- results]
    _ -> exitFailure

runTagRename :: Config -> Text -> Text -> IO ()
runTagRename cfg old new = do
  changed <- applyTagChange cfg (renameTag old new . (^. tags))
  if changed == 0
    then TIO.putStrLn $ "No books carry the tag '" <> old <> "'."
    else TIO.putStrLn $ "Renamed '" <> old <> "' to '" <> new <> "' in "
      <> T.pack (show changed) <> " book(s)."

runTagDelete :: Config -> Text -> IO ()
runTagDelete cfg tag = do
  changed <- applyTagChange cfg (deleteTag tag . (^. tags))
  if changed == 0
    then TIO.putStrLn $ "No books carry the tag '" <> tag <> "'."
    else TIO.putStrLn $ "Removed '" <> tag <> "' from "
      <> T.pack (show changed) <> " book(s)."
