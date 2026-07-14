module Libri.Text.Normalize
  ( foldAccents
  , normalizeText
  , slugify
  ) where

import Data.Char (generalCategory, isAlphaNum, isAscii, GeneralCategory(NonSpacingMark))
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Normalize as TN

foldAccents :: Text -> Text
foldAccents = T.filter (not . isCombiningMark) . TN.normalize TN.NFD
  where
    isCombiningMark c = generalCategory c == NonSpacingMark

normalizeText :: Text -> Text
normalizeText = foldAccents . T.toLower

-- | Filesystem-friendly slug: accent-folded, lowercased, ASCII
-- alphanumerics kept, everything else collapsed to single hyphens,
-- capped at 40 characters. Empty input yields "book".
slugify :: Text -> Text
slugify t =
  let cleaned = T.dropAround (== '-')
              . squashHyphens
              . T.map (\c -> if isAscii c && isAlphaNum c then c else '-')
              . normalizeText
              $ t
      capped = T.dropAround (== '-') (T.take 40 cleaned)
  in if T.null capped then "book" else capped
  where
    squashHyphens = T.intercalate "-" . filter (not . T.null) . T.splitOn "-"
