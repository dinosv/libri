module CommandsSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Time (UTCTime(..))
import Data.Time.Calendar (fromGregorian)
import Libri.CLI.Commands (AddOpts(..), applyAddOpts)
import Libri.Types (Book(..))
import Test.Hspec

blankBook :: Book
blankBook = Book
  { _bookId = "b1"
  , _isbn = Nothing
  , _title = ""
  , _authors = []
  , _series = Nothing
  , _seriesIndex = Nothing
  , _publisher = Nothing
  , _published = Nothing
  , _tags = []
  , _rating = Nothing
  , _comments = Nothing
  , _location = Nothing
  , _custom = Map.empty
  , _added = UTCTime (fromGregorian 2025 1 1) 0
  , _modified = UTCTime (fromGregorian 2025 1 1) 0
  }

spec :: Spec
spec = describe "Commands" $ do

  describe "applyAddOpts" $ do
    let opts = AddOpts
          { addISBN = Just "978-84-473-5307-1"
          , addTitle = Just "Obras. Tomo 40"
          , addAuthors = []
          , addLocation = Nothing
          , addTags = []
          }

    it "keeps the ISBN given on the command line when the lookup failed" $
      _isbn (applyAddOpts opts blankBook) `shouldBe` Just "9788447353071"

    it "keeps the ISBN the lookup returned" $
      _isbn (applyAddOpts opts blankBook { _isbn = Just "9788447353071" })
        `shouldBe` Just "9788447353071"

    it "applies the title override" $
      _title (applyAddOpts opts blankBook) `shouldBe` "Obras. Tomo 40"
