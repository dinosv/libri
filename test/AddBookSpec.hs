{-# LANGUAGE OverloadedStrings #-}

module AddBookSpec (spec) where

import Data.Either (isLeft)
import qualified Data.Map.Strict as Map
import Data.Time (UTCTime(..))
import Data.Time.Calendar (fromGregorian)
import Libri.TUI.Views.AddBook
import Libri.Types (Book(..))
import Test.Hspec

sampleBook :: Book
sampleBook = Book
  { _bookId = "b1"
  , _isbn = Just "9780000000001"
  , _title = "Tarascon Pocket Urologica"
  , _authors = ["Eco, Umberto"]
  , _series = Nothing
  , _seriesIndex = Nothing
  , _publisher = Just "Jones"
  , _published = Just (fromGregorian 2010 1 1)
  , _tags = ["Urology -- Handbooks, manuals, etc", "Medicine"]
  , _rating = Just 4
  , _comments = Nothing
  , _location = Nothing
  , _custom = Map.empty
  , _added = UTCTime (fromGregorian 2025 1 1) 0
  , _modified = UTCTime (fromGregorian 2025 1 1) 0
  }

spec :: Spec
spec = describe "AddBook form" $ do

  describe "list fields" $ do
    it "round-trips tags that contain commas" $ do
      let st = initEditBookState sampleBook
      parseList (absTags st) `shouldBe` _tags sampleBook

    it "round-trips authors that contain commas" $ do
      let st = initEditBookState sampleBook
      parseList (absAuthors st) `shouldBe` _authors sampleBook

    it "splits on semicolons, trimming and dropping empties" $
      parseList " Arte ;Historia;; " `shouldBe` ["Arte", "Historia"]

  describe "parsePublishedField" $ do
    it "accepts an empty field as no date" $
      parsePublishedField "  " `shouldBe` Right Nothing

    it "accepts a full date" $
      parsePublishedField "2020-01-31" `shouldBe` Right (Just (fromGregorian 2020 1 31))

    it "accepts a bare year" $
      parsePublishedField "2007" `shouldBe` Right (Just (fromGregorian 2007 1 1))

    it "rejects text it cannot parse instead of dropping the date" $
      parsePublishedField "2020/01/31" `shouldSatisfy` isLeft

  describe "applyLookup" $ do
    let fetched = sampleBook
          { _title = "Fetched Title"
          , _authors = ["Someone Else"]
          , _tags = []
          , _publisher = Just "Fetched Pub"
          }

    it "keeps the form's tags when the lookup returns none" $ do
      let st = applyLookup fetched (initEditBookState sampleBook)
      parseList (absTags st) `shouldBe` _tags sampleBook

    it "does not overwrite a title or authors already in the form" $ do
      let st = applyLookup fetched (initEditBookState sampleBook)
      absTitle st `shouldBe` "Tarascon Pocket Urologica"
      parseList (absAuthors st) `shouldBe` ["Eco, Umberto"]

    it "fills fields that are empty in the form" $ do
      let st = applyLookup fetched initAddBookState { absIsbn = "9780000000001" }
      absTitle st `shouldBe` "Fetched Title"
      parseList (absAuthors st) `shouldBe` ["Someone Else"]
      absPublisher st `shouldBe` "Fetched Pub"
      absPublished st `shouldBe` "2010-01-01"
