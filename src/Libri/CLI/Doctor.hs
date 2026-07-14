module Libri.CLI.Doctor
  ( DoctorReport (..)
  , analyseBooks
  , reportIsClean
  , runDoctor
  ) where

import Control.Exception (IOException, catch)
import Control.Monad (forM, forM_, unless)
import Data.List (isSuffixOf, sort)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Libri.Storage.Yaml (getDataDir, loadBook, loadLocations)
import Libri.Text.Normalize (normalizeText)
import Libri.Types
import System.Directory (listDirectory)
import System.Exit (exitFailure)
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr)

-- | Everything doctor has to say about the collection
data DoctorReport = DoctorReport
  { drParseErrors :: [(FilePath, LibriError)]
  , drTmpFiles :: [FilePath]
  , drDuplicateIsbns :: [(Text, [Book])]   -- normalised ISBN, books sharing it
  , drDuplicateIds :: [(Text, [Book])]
  , drStaleFilenames :: [(FilePath, Book)] -- actual file /= canonical name
  , drEmptyTags :: [Book]                  -- books with blank/whitespace tags
  , drTagVariants :: [[Text]]              -- spellings that normalise equal
  , drUnknownLocations :: [(Text, Int)]    -- location, book count
  }
  deriving (Show)

reportIsClean :: DoctorReport -> Bool
reportIsClean r =
  null (drParseErrors r) && null (drTmpFiles r)
    && null (drDuplicateIsbns r) && null (drDuplicateIds r)
    && null (drStaleFilenames r) && null (drEmptyTags r)
    && null (drTagVariants r) && null (drUnknownLocations r)

-- | Pure analysis over the loaded collection
analyseBooks
  :: [(FilePath, Book)]        -- successfully loaded books with their files
  -> [(FilePath, LibriError)]  -- files that failed to load
  -> [FilePath]                -- stray .tmp files
  -> [Location]                -- known locations
  -> DoctorReport
analyseBooks loaded parseErrors tmpFiles knownLocs =
  let books' = map snd loaded
      normalizeIsbn = T.filter (\c -> c /= '-' && c /= ' ')

      groupBy' key vals = Map.toAscList $ Map.fromListWith (++)
        [(key v, [v]) | v <- vals]
      dupes key vals = [(k, reverse vs) | (k, vs) <- groupBy' key vals, length vs > 1]

      dupIsbns = dupes (maybe "" normalizeIsbn . _isbn)
                       (filter ((/= Nothing) . _isbn) books')
      dupIds = dupes _bookId books'

      stale = [ (path, b)
              | (path, b) <- loaded
              , not (bookFilename b `isSuffixOf` path)
              ]

      emptyTagged = filter (any (T.null . T.strip) . _tags) books'

      variantGroups =
        [ sort spellings
        | (_, spellings) <- Map.toAscList $ Map.fromListWith (++)
            [ (normalizeText t, [t])
            | t <- Map.keys $ Map.fromList
                [(t, ()) | b <- books', t <- _tags b, not (T.null (T.strip t))]
            ]
        , length spellings > 1
        ]

      usedLocs = Map.toAscList $ Map.fromListWith (+)
        [(loc, 1 :: Int) | b <- books', Just loc <- [_location b]]
      unknownLocs = [(loc, n) | (loc, n) <- usedLocs, loc `notElem` knownLocs]

  in DoctorReport
       { drParseErrors = parseErrors
       , drTmpFiles = tmpFiles
       , drDuplicateIsbns = dupIsbns
       , drDuplicateIds = dupIds
       , drStaleFilenames = stale
       , drEmptyTags = emptyTagged
       , drTagVariants = variantGroups
       , drUnknownLocations = unknownLocs
       }

-- | Run all integrity checks and print a report. Never writes.
-- Exits non-zero when any issue is found.
runDoctor :: Config -> IO ()
runDoctor cfg = do
  dir <- getDataDir cfg
  let booksDir = dir </> "books"
  files <- listDirectory booksDir
    `catch` \(_ :: IOException) -> pure []
  let yamlFiles = [f | f <- files, ".yaml" `isSuffixOf` f]
      tmpFiles = [booksDir </> f | f <- files, ".tmp" `isSuffixOf` f]
  results <- forM yamlFiles $ \f -> do
    let path = booksDir </> f
    result <- loadBook path
    pure $ either (Left . (path,)) (Right . (path,)) result
  knownLocs <- either (const []) id <$> loadLocations cfg

  let loaded = [x | Right x <- results]
      parseErrors = [x | Left x <- results]
      report = analyseBooks loaded parseErrors tmpFiles knownLocs

  TIO.putStrLn $ "Checked " <> tshow (length yamlFiles) <> " book files.\n"

  section "Unreadable files" (drParseErrors report) $ \(path, err) ->
    putStrLn $ "  " <> path <> ": " <> show err

  section "Stray .tmp files (interrupted writes)" (drTmpFiles report) $ \path ->
    putStrLn $ "  " <> path

  section "Duplicate ISBNs" (drDuplicateIsbns report) $ \(isbnVal, bks) -> do
    TIO.putStrLn $ "  " <> isbnVal <> ":"
    forM_ bks $ \b ->
      TIO.putStrLn $ "    " <> _title b <> " (ID: " <> _bookId b <> ")"

  section "Duplicate IDs" (drDuplicateIds report) $ \(bid, bks) -> do
    TIO.putStrLn $ "  " <> bid <> ": " <> T.intercalate ", " (map _title bks)

  section "Stale filenames (run --migrate-ids)" (drStaleFilenames report) $ \(path, b) ->
    putStrLn $ "  " <> path <> " (canonical: " <> bookFilename b <> ")"

  section "Books with empty tags" (drEmptyTags report) $ \b ->
    TIO.putStrLn $ "  " <> _title b <> " (ID: " <> _bookId b <> ")"

  section "Tag spelling variants (use --tag-rename)" (drTagVariants report) $ \spellings ->
    TIO.putStrLn $ "  " <> T.intercalate "  /  " spellings

  section "Locations not in locations.yaml" (drUnknownLocations report) $ \(loc, n) ->
    TIO.putStrLn $ "  " <> loc <> " (" <> tshow n <> " books)"

  if reportIsClean report
    then TIO.putStrLn "No problems found."
    else do
      hPutStrLn stderr "Problems found."
      exitFailure
  where
    tshow :: Show a => a -> Text
    tshow = T.pack . show

    section :: Text -> [a] -> (a -> IO ()) -> IO ()
    section name items printItem =
      unless (null items) $ do
        TIO.putStrLn $ name <> " (" <> T.pack (show (length items)) <> "):"
        mapM_ printItem items
        TIO.putStrLn ""
