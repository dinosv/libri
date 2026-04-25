module Libri.Storage.Index
  ( -- * Index Type
    BookIndex (..)
    -- * Building
  , buildIndex
  , emptyIndex
    -- * Querying
  , lookupById
  , lookupByISBN
  , filterByLocation
  , filterByTag
  , filterByAuthor
  , allBooks
    -- * Modification
  , addBook
  , updateBook
  , removeBook
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Lens.Micro ((^.))
import Libri.Types

-- | In-memory index for fast book lookups
data BookIndex = BookIndex
  { _byId :: Map BookId Book
  , _byISBN :: Map Text Book
  , _byLocation :: Map Location [Book]
  , _byTag :: Map Text [Book]
  , _byAuthor :: Map Text [Book]
  }
  deriving (Show)

-- | Empty index
emptyIndex :: BookIndex
emptyIndex =
  BookIndex
    { _byId = Map.empty
    , _byISBN = Map.empty
    , _byLocation = Map.empty
    , _byTag = Map.empty
    , _byAuthor = Map.empty
    }

-- | Build an index from a list of books
buildIndex :: [Book] -> BookIndex
buildIndex = foldr addBook emptyIndex

-- | Add a book to the index
addBook :: Book -> BookIndex -> BookIndex
addBook book idx =
  BookIndex
    { _byId = Map.insert (book ^. bookId) book (_byId idx)
    , _byISBN = case book ^. isbn of
        Nothing -> _byISBN idx
        Just i -> Map.insert i book (_byISBN idx)
    , _byLocation = case book ^. location of
        Nothing -> _byLocation idx
        Just loc ->
          Map.insertWith (++) loc [book] (_byLocation idx)
    , _byTag =
        foldr
          (\t m -> Map.insertWith (++) (T.toLower t) [book] m)
          (_byTag idx)
          (book ^. tags)
    , _byAuthor =
        foldr
          (\a m -> Map.insertWith (++) (T.toLower a) [book] m)
          (_byAuthor idx)
          (book ^. authors)
    }

-- | Update a book in the index (remove old, add new)
updateBook :: Book -> BookIndex -> BookIndex
updateBook book idx =
  case lookupById (book ^. bookId) idx of
    Nothing -> addBook book idx
    Just oldBook -> addBook book (removeBook oldBook idx)

-- | Remove a book from the index
removeBook :: Book -> BookIndex -> BookIndex
removeBook book idx =
  let bid = book ^. bookId
      removeFromList bs =
        case filter (\b -> b ^. bookId /= bid) bs of
          [] -> Nothing
          xs -> Just xs
  in BookIndex
    { _byId = Map.delete bid (_byId idx)
    , _byISBN = case book ^. isbn of
        Nothing -> _byISBN idx
        Just i -> Map.delete i (_byISBN idx)
    , _byLocation = case book ^. location of
        Nothing -> _byLocation idx
        Just loc -> Map.update removeFromList loc (_byLocation idx)
    , _byTag =
        foldr
          (\t m -> Map.update removeFromList (T.toLower t) m)
          (_byTag idx)
          (book ^. tags)
    , _byAuthor =
        foldr
          (\a m -> Map.update removeFromList (T.toLower a) m)
          (_byAuthor idx)
          (book ^. authors)
    }

-- | Lookup a book by its ID
lookupById :: BookId -> BookIndex -> Maybe Book
lookupById bid idx = Map.lookup bid (_byId idx)

-- | Lookup a book by ISBN
lookupByISBN :: Text -> BookIndex -> Maybe Book
lookupByISBN i idx = Map.lookup i (_byISBN idx)

-- | Filter books by location
filterByLocation :: Location -> BookIndex -> [Book]
filterByLocation loc idx =
  Map.findWithDefault [] loc (_byLocation idx)

-- | Filter books by tag (case-insensitive)
filterByTag :: Text -> BookIndex -> [Book]
filterByTag t idx =
  Map.findWithDefault [] (T.toLower t) (_byTag idx)

-- | Filter books by author (case-insensitive)
filterByAuthor :: Text -> BookIndex -> [Book]
filterByAuthor a idx =
  Map.findWithDefault [] (T.toLower a) (_byAuthor idx)

-- | Get all books in the index
allBooks :: BookIndex -> [Book]
allBooks idx = Map.elems (_byId idx)
