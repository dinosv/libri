module Libri.Text.Normalize
  ( foldAccents
  , normalizeText
  ) where

import Data.Char (generalCategory, GeneralCategory(NonSpacingMark))
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Normalize as TN

foldAccents :: Text -> Text
foldAccents = T.filter (not . isCombiningMark) . TN.normalize TN.NFD
  where
    isCombiningMark c = generalCategory c == NonSpacingMark

normalizeText :: Text -> Text
normalizeText = foldAccents . T.toLower
