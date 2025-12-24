{-# LANGUAGE OverloadedStrings #-}

module Libri.CLI.BatchImport
  ( parseIsbnFile
  , FetchResult(..)
  , BatchResults(..)
  , categorizeResults
  , normalizeISBN
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Libri.Types (Book)

-- | Result of fetching a single ISBN
data FetchResult
  = FetchSuccess Book
  | FetchNotFound Text           -- ^ ISBN not in OpenLibrary
  | FetchError Text String       -- ^ ISBN + error message
  | FetchDuplicate Book Book     -- ^ fetched book + existing book
  deriving (Show, Eq)

-- | Categorized batch results
data BatchResults = BatchResults
  { brNew        :: [Book]              -- ^ New books ready to import
  , brDuplicates :: [(Book, Book)]      -- ^ (fetched, existing)
  , brNotFound   :: [Text]              -- ^ ISBNs not found
  , brErrors     :: [(Text, String)]    -- ^ ISBNs with errors
  } deriving (Show, Eq)

-- | Parse a text file containing ISBNs (one per line).
-- Skips empty lines and lines starting with '#' (comments).
-- Trims whitespace from each ISBN.
parseIsbnFile :: Text -> [Text]
parseIsbnFile content =
  filter (not . T.null)
  . filter (not . T.isPrefixOf "#")
  . map T.strip
  . T.lines
  . T.replace "\r" ""  -- Handle Windows CRLF
  $ content

-- | Categorize fetch results into new, duplicates, not found, and errors
categorizeResults :: [FetchResult] -> BatchResults
categorizeResults results = BatchResults
  { brNew        = [b | FetchSuccess b <- results]
  , brDuplicates = [(f, e) | FetchDuplicate f e <- results]
  , brNotFound   = [isbn | FetchNotFound isbn <- results]
  , brErrors     = [(isbn, err) | FetchError isbn err <- results]
  }

-- | Normalize ISBN by removing dashes and spaces
normalizeISBN :: Text -> Text
normalizeISBN = T.filter (\c -> c /= '-' && c /= ' ')
