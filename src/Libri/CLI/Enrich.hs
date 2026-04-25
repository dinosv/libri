module Libri.CLI.Enrich
  ( EnrichResult (..)
  , needsEnrichment
  , mergeTags
  , enrichBook
  , runEnrich
  ) where

import Control.Concurrent (threadDelay)
import Control.Monad (forM, when)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Lens.Micro ((^.), (&), (.~))
import Libri.ISBN.OpenLibrary (fetchByISBNWith, newISBNManager)
import Libri.Storage.Yaml (loadBooks, saveBook)
import Libri.Text.Normalize (normalizeText)
import Libri.Types
import Network.HTTP.Client (Manager)
import System.IO (hFlush, stdout, hPutStrLn, stderr)
import System.Exit (exitFailure)

data EnrichResult
  = Enriched Int Bool
  | NotFound
  | AlreadyComplete
  | NoISBN
  deriving (Show, Eq)

needsEnrichment :: Book -> Bool
needsEnrichment book =
  case book ^. isbn of
    Nothing -> False
    Just _  -> null (book ^. tags) || book ^. comments == Nothing

mergeTags :: [Text] -> [Text] -> [Text]
mergeTags existing new =
  let existingNorm = map normalizeText existing
      isNew t = normalizeText t `notElem` existingNorm
      newOnly = take 10 $ filter isNew new
  in existing ++ newOnly

enrichBook :: Manager -> Book -> IO (Book, EnrichResult)
enrichBook mgr book =
  case book ^. isbn of
    Nothing -> pure (book, NoISBN)
    Just isbnVal -> do
      result <- fetchByISBNWith mgr isbnVal
      case result of
        Left (ISBNNotFound _) -> pure (book, NotFound)
        Left _ -> pure (book, NotFound)
        Right fetched ->
          let newTags = mergeTags (book ^. tags) (fetched ^. tags)
              tagsAdded = length newTags - length (book ^. tags)
              addedDesc = book ^. comments == Nothing && fetched ^. comments /= Nothing
              newComments = case book ^. comments of
                Just c  -> Just c
                Nothing -> fetched ^. comments
              enriched = book & tags .~ newTags
                              & comments .~ newComments
          in pure (enriched, Enriched tagsAdded addedDesc)

runEnrich :: Config -> IO ()
runEnrich cfg = do
  booksResult <- loadBooks cfg
  case booksResult of
    Left err -> do
      hPutStrLn stderr $ "Error loading books: " <> show err
      exitFailure
    Right bks -> do
      let toEnrich = filter needsEnrichment bks
          total = length toEnrich
      if total == 0
        then TIO.putStrLn "All books already have tags and descriptions."
        else do
          TIO.putStrLn $ "Enriching " <> tshow total <> " books with missing data...\n"
          mgr <- newISBNManager
          results <- forM (zip [1 :: Int ..] toEnrich) $ \(n, book) -> do
            TIO.putStr $ "  " <> tshow n <> "/" <> tshow total
                      <> ": " <> (book ^. title)
                      <> case book ^. isbn of
                           Just i  -> " (" <> i <> ")"
                           Nothing -> ""
                      <> "... "
            hFlush stdout
            (enriched, res) <- enrichBook mgr book
            printResult res
            case res of
              Enriched _ _ -> do
                saveResult <- saveBook cfg enriched
                case saveResult of
                  Left err -> TIO.putStrLn $ "    save error: " <> T.pack (show err)
                  Right () -> pure ()
              _ -> pure ()
            threadDelay 1000000
            pure res

          let updated = length [() | Enriched _ _ <- results]
              notFound = length [() | NotFound <- results]
          TIO.putStrLn ""
          TIO.putStrLn "Enrichment complete!"
          TIO.putStrLn $ "  " <> tshow updated <> " books updated"
          when (notFound > 0) $
            TIO.putStrLn $ "  " <> tshow notFound <> " books not found on OpenLibrary"
  where
    tshow :: Show a => a -> Text
    tshow = T.pack . show

printResult :: EnrichResult -> IO ()
printResult (Enriched tagCount hasDesc) = do
  let parts = (if tagCount > 0 then ["+" <> T.pack (show tagCount) <> " tags"] else [])
           ++ (if hasDesc then ["+description"] else [])
  case parts of
    [] -> TIO.putStrLn "no new data"
    _  -> TIO.putStrLn $ T.intercalate ", " parts
printResult NotFound = TIO.putStrLn "not found"
printResult AlreadyComplete = TIO.putStrLn "already complete"
printResult NoISBN = TIO.putStrLn "no ISBN"
