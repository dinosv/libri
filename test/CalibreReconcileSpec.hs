module CalibreReconcileSpec (spec) where

import Data.Aeson (Value(..))
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Data.Time (UTCTime(..))
import Data.Time.Calendar (fromGregorian)
import Libri.Storage.CalibreReconcile
import Libri.Storage.CalibreSync
import Libri.Types (Book(..))
import Test.Hspec

mk :: Text -> Maybe Text -> Maybe Text -> Book
mk bid isbn ref = Book
  { _bookId = bid
  , _isbn = isbn
  , _title = "T"
  , _authors = []
  , _series = Nothing
  , _seriesIndex = Nothing
  , _publisher = Nothing
  , _published = Nothing
  , _tags = []
  , _rating = Nothing
  , _comments = Nothing
  , _location = Nothing
  , _custom = maybe Map.empty (Map.singleton "identifier:calibre" . String) ref
  , _added = UTCTime (fromGregorian 2025 1 1) 0
  , _modified = UTCTime (fromGregorian 2025 1 1) 0
  }

inc :: Book
inc = mk "new" (Just "9780000000001") (Just "uuid:46")

sync :: [(Text, SyncEntry)] -> Maybe LibrarySync
sync es = Just (LibrarySync "p" HomeYes (Map.fromList es))

spec :: Spec
spec = describe "matchBook" $ do
  let owner = mk "b1" Nothing Nothing
  it "rule 1: mapped id present" $
    matchBook True (sync [("uuid:46", SyncMapped "b1" Map.empty)]) [owner] inc
      `shouldBe` MatchMapped owner Map.empty
  it "rule 1: mapped id missing" $
    matchBook True (sync [("uuid:46", SyncMapped "gone" Map.empty)]) [owner] inc
      `shouldBe` MatchDeletedInLibri
  it "rule 1: ignored and pending" $ do
    matchBook True (sync [("uuid:46", SyncIgnored)]) [] inc `shouldBe` MatchIgnored
    matchBook True (sync [("uuid:46", SyncPending)]) [] inc `shouldBe` MatchPending
  it "rule 1 beats every other rule" $
    matchBook True (sync [("uuid:46", SyncIgnored)])
      [mk "r" Nothing (Just "uuid:46")] inc `shouldBe` MatchIgnored
  it "rule 2: namespaced ref" $ do
    let r = mk "r" Nothing (Just "uuid:46")
    matchBook False Nothing [r] inc `shouldBe` MatchByRef r
  it "rule 3: bare id when allowed" $ do
    let r = mk "r" Nothing (Just "46")
    matchBook True Nothing [r] inc `shouldBe` MatchBareRef r
  it "rule 3: bare id ignored when not allowed" $
    matchBook False Nothing [mk "r" Nothing (Just "46")] inc `shouldBe` NoMatch
  it "rule 4: ISBN, normalised and case-insensitive" $ do
    let r = mk "r" (Just "978-0-00-000000-1") Nothing
    matchBook True Nothing [r] inc `shouldBe` MatchIsbnGuess r
    let x = mk "x" (Just "080442957x") Nothing
        i = mk "n" (Just "080442957X") (Just "uuid:7")
    matchBook True Nothing [x] i `shouldBe` MatchIsbnGuess x
  it "rule 4 skips books carrying any identifier:calibre" $ do
    matchBook True Nothing [mk "r" (Just "9780000000001") (Just "99")] inc
      `shouldBe` NoMatch
    matchBook True Nothing [mk "r" (Just "9780000000001") (Just "other:5")] inc
      `shouldBe` NoMatch
  it "rule 5: no match" $ matchBook True Nothing [owner] inc `shouldBe` NoMatch
  it "ref beats ISBN regardless of order" $ do
    let byRef = mk "a" Nothing (Just "uuid:46")
        byIsbn = mk "b" (Just "9780000000001") Nothing
    matchBook True Nothing [byRef, byIsbn] inc `shouldBe` MatchByRef byRef
    matchBook True Nothing [byIsbn, byRef] inc `shouldBe` MatchByRef byRef
  it "a newly added book does not ISBN-capture a sibling Calibre id" $ do
    let added = inc { _bookId = "added" }
        second = mk "n2" (Just "9780000000001") (Just "uuid:47")
    matchBook True Nothing [added] second `shouldBe` NoMatch
