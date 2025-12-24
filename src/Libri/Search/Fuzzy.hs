module Libri.Search.Fuzzy
  ( searchBooks
  , SearchResult (..)
  , searchBooksWithScore
  , searchBooksExact
  , fuzzyMatch
  , tokenize
  ) where

import Data.Char (isAlphaNum)
import Data.List (sortBy)
import Data.Ord (Down (..), comparing)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Metrics as TM
import Lens.Micro ((^.))
import Libri.Types

-- | Search result with relevance score
data SearchResult = SearchResult
  { srBook :: Book
  , srScore :: Double
  }
  deriving (Show)

-- | Minimum query length for fuzzy matching
-- Shorter queries use exact substring matching instead
minQueryLength :: Int
minQueryLength = 3

-- | Search books by query, returning matches sorted by relevance
-- Uses fuzzy matching for queries >= 3 chars, exact substring for shorter
searchBooks :: Double -> Text -> [Book] -> [Book]
searchBooks threshold query books
  | T.null (T.strip query) = books
  | T.length (T.strip query) < minQueryLength = searchBooksExact query books
  | otherwise = map srBook $ searchBooksWithScore threshold query books

-- | Exact substring search for short queries (case-insensitive)
searchBooksExact :: Text -> [Book] -> [Book]
searchBooksExact query books =
  let q = T.toLower (T.strip query)
  in filter (bookContainsExact q) books

-- | Check if book contains exact substring in title, authors, or tags
bookContainsExact :: Text -> Book -> Bool
bookContainsExact q book =
  q `T.isInfixOf` T.toLower (book ^. title)
  || any (T.isInfixOf q . T.toLower) (book ^. authors)
  || any (T.isInfixOf q . T.toLower) (book ^. tags)

-- | Search books with scores, filtering by threshold and majority-word matching
searchBooksWithScore :: Double -> Text -> [Book] -> [SearchResult]
searchBooksWithScore threshold query books
  | T.null (T.strip query) = map (\b -> SearchResult b 1.0) books
  | otherwise =
      let queryTokens = tokenize query
          -- First filter by majority-word matching (>50% of query words must match)
          booksWithMajority = filter (hasMajorityMatches queryTokens) books
          -- Then score and filter by threshold
          results = map (scoreBook queryTokens) booksWithMajority
          filtered = filter (\sr -> srScore sr >= threshold) results
      in sortBy (comparing (Down . srScore)) filtered

-- | Check if majority (>50%) of query tokens have a match in the book
hasMajorityMatches :: [Text] -> Book -> Bool
hasMajorityMatches queryTokens book
  | null queryTokens = True
  | otherwise =
      let matchCount = countMatchingTokens queryTokens book
          required = (length queryTokens + 1) `div` 2  -- ceiling of half
      in matchCount >= required

-- | Count how many query tokens have a match in the book
countMatchingTokens :: [Text] -> Book -> Int
countMatchingTokens queryTokens book =
  let titleTokens = tokenize (book ^. title)
      authorTokens = concatMap tokenize (book ^. authors)
      tagTokens = concatMap tokenize (book ^. tags)
      allFieldTokens = titleTokens ++ authorTokens ++ tagTokens
      hasMatch qt = any (\ft -> fuzzyMatch qt ft >= minTokenMatchThreshold) allFieldTokens
  in length $ filter hasMatch queryTokens

-- | Score a book against query tokens
-- Only searches title, authors, and tags as per user configuration
-- Uses maximum score across authors/tags (not sum) to prevent accumulation bias
scoreBook :: [Text] -> Book -> SearchResult
scoreBook queryTokens book =
  let titleScore = scoreField 3.0 queryTokens (book ^. title)
      -- Use maximum instead of sum to avoid bias towards books with many authors/tags
      authorScores = map (scoreField 2.0 queryTokens) (book ^. authors)
      authorScore = if null authorScores then 0 else maximum authorScores
      tagScores = map (scoreField 1.5 queryTokens) (book ^. tags)
      tagScore = if null tagScores then 0 else maximum tagScores

      totalScore = titleScore + authorScore + tagScore
  in SearchResult book totalScore

-- | Score a text field against query tokens
scoreField :: Double -> [Text] -> Text -> Double
scoreField weight queryTokens fieldText =
  let fieldTokens = tokenize fieldText
      matches = sum $ map (bestMatch fieldTokens) queryTokens
  in weight * matches

-- | Minimum similarity threshold for a token match to count
-- Below this, the match is treated as 0 (no match)
-- This filters out noise from unrelated partial matches
minTokenMatchThreshold :: Double
minTokenMatchThreshold = 0.5

-- | Find the best fuzzy match score for a query token against field tokens
-- Only returns scores above the minimum threshold
bestMatch :: [Text] -> Text -> Double
bestMatch fieldTokens queryToken =
  if null fieldTokens
    then 0
    else let scores = map (fuzzyMatch queryToken) fieldTokens
             validScores = filter (>= minTokenMatchThreshold) scores
         in if null validScores then 0 else maximum validScores

-- | Minimum token length for substring matching to count
-- Prevents short words like "o", "a", "in" from matching as substrings
minSubstringLength :: Int
minSubstringLength = 4

-- | Calculate fuzzy match score between two tokens (0.0 to 1.0)
fuzzyMatch :: Text -> Text -> Double
fuzzyMatch query target
  | T.null query || T.null target = 0
  | query == target = 1.0
  -- Only count substring matches if the substring is long enough
  | T.length query >= minSubstringLength && query `T.isInfixOf` target = 0.9
  | T.length target >= minSubstringLength && target `T.isInfixOf` query = 0.8
  | otherwise = levenshteinSimilarity query target

-- | Calculate similarity based on Levenshtein distance using text-metrics
levenshteinSimilarity :: Text -> Text -> Double
levenshteinSimilarity s1 s2 =
  let dist = TM.levenshtein s1 s2
      maxLen = max (T.length s1) (T.length s2)
  in if maxLen == 0
       then 1.0
       else max 0 (1.0 - fromIntegral dist / fromIntegral maxLen)

-- | Tokenize text into lowercase words
tokenize :: Text -> [Text]
tokenize =
  filter (not . T.null)
  . map T.toLower
  . T.split (not . isAlphaNum)
