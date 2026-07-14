module DoctorSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Maybe (fromJust)
import Data.Text (Text)
import Data.Time (UTCTime, parseTimeM, defaultTimeLocale)
import Libri.CLI.Doctor (DoctorReport (..), analyseBooks, reportIsClean)
import Libri.Types
import Test.Hspec

makeBook :: Text -> Text -> Maybe Text -> [Text] -> Maybe Text -> Book
makeBook bid bookTitle bookIsbn bookTags bookLoc =
  let ts = fromJust $ parseTimeM True defaultTimeLocale "%Y-%m-%d" "2025-01-01" :: UTCTime
  in Book
       { _bookId = bid
       , _isbn = bookIsbn
       , _title = bookTitle
       , _authors = []
       , _series = Nothing
       , _seriesIndex = Nothing
       , _publisher = Nothing
       , _published = Nothing
       , _tags = bookTags
       , _rating = Nothing
       , _comments = Nothing
       , _location = bookLoc
       , _custom = Map.empty
       , _added = ts
       , _modified = ts
       }

withCanonicalPath :: Book -> (FilePath, Book)
withCanonicalPath b = ("books/" <> bookFilename b, b)

spec :: Spec
spec = describe "Doctor" $ do

  it "reports a clean collection as clean" $ do
    let bks = map withCanonicalPath
          [ makeBook "3fa2c1d0-0000-4000-8000-000000000001" "A" (Just "9780000000001") ["Arte"] Nothing ]
    reportIsClean (analyseBooks bks [] [] []) `shouldBe` True

  it "finds duplicate ISBNs regardless of dashes" $ do
    let b1 = makeBook "id-1" "A" (Just "978-0-13-468599-1") [] Nothing
        b2 = makeBook "id-2" "B" (Just "9780134685991") [] Nothing
        r = analyseBooks (map withCanonicalPath [b1, b2]) [] [] []
    map fst (drDuplicateIsbns r) `shouldBe` ["9780134685991"]

  it "finds duplicate IDs" $ do
    let b1 = makeBook "same" "A" Nothing [] Nothing
        b2 = makeBook "same" "B" Nothing [] Nothing
        r = analyseBooks (map withCanonicalPath [b1, b2]) [] [] []
    length (drDuplicateIds r) `shouldBe` 1

  it "flags stale filenames" $ do
    let b = makeBook "id-1" "A Title" Nothing [] Nothing
        r = analyseBooks [("books/1.yaml", b)] [] [] []
    map fst (drStaleFilenames r) `shouldBe` ["books/1.yaml"]

  it "groups tag spelling variants" $ do
    let b1 = makeBook "id-1" "A" Nothing ["Public Health"] Nothing
        b2 = makeBook "id-2" "B" Nothing ["Public health"] Nothing
        b3 = makeBook "id-3" "C" Nothing ["Arte"] Nothing
        r = analyseBooks (map withCanonicalPath [b1, b2, b3]) [] [] []
    drTagVariants r `shouldBe` [["Public Health", "Public health"]]

  it "flags empty tags" $ do
    let b = makeBook "id-1" "A" Nothing ["", "Arte"] Nothing
        r = analyseBooks [withCanonicalPath b] [] [] []
    map _bookId (drEmptyTags r) `shouldBe` ["id-1"]

  it "flags locations missing from locations.yaml" $ do
    let b = makeBook "id-1" "A" Nothing [] (Just "Attic")
        r = analyseBooks [withCanonicalPath b] [] [] ["Shelf A"]
    drUnknownLocations r `shouldBe` [("Attic", 1)]

  it "counts parse errors and tmp files as problems" $ do
    let r = analyseBooks [] [("books/bad.yaml", ParseError "books/bad.yaml" "boom")] ["books/x.yaml.tmp"] []
    reportIsClean r `shouldBe` False
