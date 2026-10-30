module CalibreReconcileSpec (spec) where

import Data.Aeson (Value(..))
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
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
spec = do
  matchSpec
  conflictSpec

matchSpec :: Spec
matchSpec = describe "matchBook" $ do
  let owner = mk "b1" Nothing Nothing
  it "rule 1: mapped id present" $
    matchBook (Just []) (sync [("uuid:46", SyncMapped "b1" Map.empty)]) [owner] inc
      `shouldBe` MatchMapped owner Map.empty
  it "rule 1: mapped id missing" $
    matchBook (Just []) (sync [("uuid:46", SyncMapped "gone" Map.empty)]) [owner] inc
      `shouldBe` MatchDeletedInLibri
  it "rule 1: ignored and pending" $ do
    matchBook (Just []) (sync [("uuid:46", SyncIgnored)]) [] inc `shouldBe` MatchIgnored
    matchBook (Just []) (sync [("uuid:46", SyncPending)]) [] inc `shouldBe` MatchPending
  it "rule 1 beats every other rule" $
    matchBook (Just []) (sync [("uuid:46", SyncIgnored)])
      [mk "r" Nothing (Just "uuid:46")] inc `shouldBe` MatchIgnored
  it "rule 2: namespaced ref" $ do
    let r = mk "r" Nothing (Just "uuid:46")
    matchBook Nothing Nothing [r] inc `shouldBe` MatchByRef r
  it "rule 3: bare id when allowed" $ do
    let r = mk "r" Nothing (Just "46")
    matchBook (Just []) Nothing [r] inc `shouldBe` MatchBareRef r
  it "rule 3: bare id ignored when not allowed" $
    matchBook Nothing Nothing [mk "r" Nothing (Just "46")] inc `shouldBe` NoMatch
  it "rule 3: a former home library's namespaced ref, when allowed" $ do
    let r = mk "r" Nothing (Just "old:46")
    matchBook (Just ["old"]) Nothing [r] inc `shouldBe` MatchBareRef r
    matchBook (Just ["old"]) Nothing [mk "f" Nothing (Just "foreign:46")] inc
      `shouldBe` NoMatch
    matchBook Nothing Nothing [r] inc `shouldBe` NoMatch
    matchBook (Just ["old"]) Nothing [mk "x" Nothing (Just "old:461")] inc
      `shouldBe` NoMatch
  it "rule 4: ISBN, normalised and case-insensitive" $ do
    let r = mk "r" (Just "978-0-00-000000-1") Nothing
    matchBook (Just []) Nothing [r] inc `shouldBe` MatchIsbnGuess r
    let x = mk "x" (Just "080442957x") Nothing
        i = mk "n" (Just "080442957X") (Just "uuid:7")
    matchBook (Just []) Nothing [x] i `shouldBe` MatchIsbnGuess x
  it "rule 4 skips books carrying any identifier:calibre" $ do
    matchBook (Just []) Nothing [mk "r" (Just "9780000000001") (Just "99")] inc
      `shouldBe` NoMatch
    matchBook (Just []) Nothing [mk "r" (Just "9780000000001") (Just "other:5")] inc
      `shouldBe` NoMatch
  it "rule 5: no match" $ matchBook (Just []) Nothing [owner] inc `shouldBe` NoMatch
  it "ref beats ISBN regardless of order" $ do
    let byRef = mk "a" Nothing (Just "uuid:46")
        byIsbn = mk "b" (Just "9780000000001") Nothing
    matchBook (Just []) Nothing [byRef, byIsbn] inc `shouldBe` MatchByRef byRef
    matchBook (Just []) Nothing [byIsbn, byRef] inc `shouldBe` MatchByRef byRef
  it "a newly added book does not ISBN-capture a sibling Calibre id" $ do
    let added = inc { _bookId = "added" }
        second = mk "n2" (Just "9780000000001") (Just "uuid:47")
    matchBook (Just []) Nothing [added] second `shouldBe` NoMatch

conflictSpec :: Spec
conflictSpec = describe "conflicts" $ do
  let libri = (mk "b1" (Just "9780000000001") (Just "uuid:1"))
        { _title = "Mine", _tags = ["a", "B"], _comments = Just "old"
        , _location = Just "/x/y"
        , _custom = Map.fromList
            [ ("identifier:calibre", String "uuid:1")
            , ("identifier:amazon", String "A1")
            , ("identifier:openlibrary", String "OL1")
            , ("mine", String "keep") ] }
      cal = libri
        { _bookId = "other", _title = "Theirs", _tags = ["b", "c"]
        , _comments = Just "new", _location = Nothing
        , _added = UTCTime (fromGregorian 2000 1 1) 0
        , _custom = Map.fromList
            [ ("identifier:calibre", String "uuid:99")
            , ("identifier:amazon", String "A2") ] }
  it "changedFields lists only differing or missing prints" $ do
    let stored = fieldPrints libri
        incoming = fieldPrints libri { _comments = Just "new" }
    changedFields stored incoming `shouldBe` [FComments]
    changedFields (Map.delete FRating stored) stored `shouldBe` [FRating]
  it "differingFields drops fields already equal" $
    differingFields [FComments, FTags] libri libri { _comments = Just "new" }
      `shouldBe` [FComments]
  it "TakeCalibre on FTitle copies only the title" $
    applyChoices [(FTitle, TakeCalibre)] cal libri
      `shouldBe` libri { _title = "Theirs" }
  it "UnionTags keeps libri order then Calibre-only tags, deduplicated" $
    _tags (applyChoices [(FTags, UnionTags)] cal libri)
      `shouldBe` ["a", "B", "c"]
  it "TakeCalibre on FIdentifiers merges and keeps libri-only keys" $ do
    let r = _custom (applyChoices [(FIdentifiers, TakeCalibre)] cal libri)
    Map.lookup "identifier:amazon" r `shouldBe` Just (String "A2")
    Map.lookup "identifier:openlibrary" r `shouldBe` Just (String "OL1")
    Map.lookup "identifier:calibre" r `shouldBe` Just (String "uuid:1")
    Map.lookup "mine" r `shouldBe` Just (String "keep")
  it "KeepLibri for every field changes nothing" $
    applyChoices [(f, KeepLibri) | f <- [minBound .. maxBound]] cal libri
      `shouldBe` libri
  it "fieldDisplay truncates long comments to 60 characters" $ do
    let d = fieldDisplay FComments cal { _comments = Just (T.replicate 80 "x") }
    d `shouldBe` T.replicate 60 "x" <> "\8230"
    fieldDisplay FAuthors cal { _authors = ["A", "B"] } `shouldBe` "A, B"
  it "fieldDisplays keeps the plain displays when they already differ" $ do
    let a = libri { _comments = Just (T.replicate 80 "x") }
        b = libri { _comments = Just (T.replicate 80 "y") }
    fieldDisplays FComments a b `shouldBe` (fieldDisplay FComments a, fieldDisplay FComments b)
  it "fieldDisplays shows a difference after the truncation point" $ do
    let base = T.pack (take 200 (cycle "abcdefghij"))
        edited = T.take 150 base <> "Z" <> T.drop 151 base
        (dl, dc) = fieldDisplays FComments libri { _comments = Just base }
                                            libri { _comments = Just edited }
    T.length base `shouldBe` 200
    dl `shouldNotBe` dc
    dc `shouldSatisfy` ("Z" `T.isInfixOf`)
    dl `shouldSatisfy` ("\8230" `T.isPrefixOf`)
    T.length dl `shouldSatisfy` (<= 62)
  it "fieldDisplays makes a whitespace-only difference visible" $ do
    let short = fieldDisplays FComments libri { _comments = Just "uno dos" }
                                         libri { _comments = Just "uno  dos" }
    fst short `shouldNotBe` snd short
    let base = T.replicate 200 "w"
        nl = T.take 150 base <> "\n" <> T.drop 150 base
        sp = T.take 150 base <> " " <> T.drop 150 base
        long = fieldDisplays FComments libri { _comments = Just nl }
                                       libri { _comments = Just sp }
    fst long `shouldNotBe` snd long
    fst long `shouldNotSatisfy` ("\n" `T.isInfixOf`)
