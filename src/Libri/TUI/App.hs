module Libri.TUI.App
  ( runTUI
  , TUIState (..)
  ) where

import Brick
import Brick.Widgets.Border
import Control.Monad (void, when)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Value(..))
import Data.List (nub, sortBy)
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, listToMaybe, fromMaybe)
import Data.Ord (comparing)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import Data.Time (Day, getCurrentTime, fromGregorian)
import Text.Read (readMaybe)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import qualified Graphics.Vty as V
import Graphics.Vty.CrossPlatform (mkVty)
import Lens.Micro ((^.), (&), (.~), (%~))
import Libri.ISBN.OpenLibrary (fetchByISBN)
import Libri.Search.Fuzzy (searchBooks)
import Libri.Storage.Yaml (loadBooks, loadLocations, saveBook, deleteBook)
import Libri.TUI.Views.AddBook
import Libri.TUI.Views.BookDetails (renderBookDetails)
import Libri.TUI.Views.BookList (renderBookList)
import Libri.TUI.Views.MoveBook
import Libri.TUI.Views.Search (renderSearchBar)
import Libri.TUI.Widgets.Common
import Libri.Types
import System.Environment (lookupEnv)
import System.IO (hClose, hFlush)
import System.IO.Temp (withSystemTempFile)
import System.Process (callProcess)

-- | Extended TUI state
data TUIState = TUIState
  { tuiAppState :: AppState
  , tuiMessage :: Maybe Text        -- Status message
  , tuiConfirmDelete :: Bool        -- Confirm delete dialog
  , tuiAddBookState :: Maybe AddBookState   -- Add/Edit form state
  , tuiMoveBookState :: Maybe MoveBookState -- Move dialog state
  , tuiPendingKey :: Maybe Char     -- For two-key sequences like 'st', 'sa', 'sd'
  }
  deriving (Show)

-- | Run the TUI application
runTUI :: Config -> IO ()
runTUI cfg = do
  -- Load initial data
  booksResult <- loadBooks cfg
  locsResult <- loadLocations cfg

  let books' = either (const []) id booksResult
      locs = either (const []) id locsResult
      sortedBooks = sortBy (comparing (^. title)) books'

  let initialState = TUIState
        { tuiAppState = AppState
            { _books = sortedBooks
            , _locations = locs
            , _config = cfg
            , _selectedIndex = 0
            , _searchQuery = ""
            , _currentView = ViewList
            , _sortField = SortByTitle
            , _sortOrder = Ascending
            , _activeFilter = Nothing
            , _groupMode = Nothing
            }
        , tuiMessage = case booksResult of
            Left err -> Just $ "Error loading books: " <> T.pack (show err)
            Right bs -> Just $ "Loaded " <> T.pack (show (length bs)) <> " books"
        , tuiConfirmDelete = False
        , tuiAddBookState = Nothing
        , tuiMoveBookState = Nothing
        , tuiPendingKey = Nothing
        }

  -- Run the app
  let buildVty = mkVty V.defaultConfig
  initialVty <- buildVty
  void $ customMain initialVty buildVty Nothing app initialState

-- | The Brick application
app :: App TUIState e Name
app = App
  { appDraw = drawUI
  , appChooseCursor = showFirstCursor
  , appHandleEvent = handleEvent
  , appStartEvent = pure ()
  , appAttrMap = const theMap
  }

-- | Draw the UI
drawUI :: TUIState -> [Widget Name]
drawUI st =
  let appSt = tuiAppState st
      visibleBooks = getVisibleBooks appSt
      selectedBook = getSelectedBook appSt visibleBooks
  in case appSt ^. currentView of
       ViewAdd ->
         case tuiAddBookState st of
           Just abs' -> [renderAddBook abs']
           Nothing -> [mainLayout appSt visibleBooks selectedBook (tuiMessage st)]
       ViewEdit _ ->
         case tuiAddBookState st of
           Just abs' -> [renderEditBook abs']
           Nothing -> [mainLayout appSt visibleBooks selectedBook (tuiMessage st)]
       ViewMove _ ->
         case tuiMoveBookState st of
           Just mbs -> [renderMoveBook mbs]
           Nothing -> [mainLayout appSt visibleBooks selectedBook (tuiMessage st)]
       _ -> [mainLayout appSt visibleBooks selectedBook (tuiMessage st)]

-- | Get books filtered by search query and sorted
getVisibleBooks :: AppState -> [Book]
getVisibleBooks st =
  let query = st ^. searchQuery
      allBooks = st ^. books
      sorted = applySortOrder (st ^. sortField) (st ^. sortOrder) allBooks
      threshold = st ^. config . fuzzyThreshold
  in if T.null query
       then sorted
       else searchBooks threshold query sorted

-- | Apply sort order to books
applySortOrder :: SortField -> SortOrder -> [Book] -> [Book]
applySortOrder field order bks =
  let cmp = case field of
        SortByTitle  -> comparing (T.toLower . (^. title))
        SortByAuthor -> comparing (maybe "" (T.toLower . head') . nonEmpty . (^. authors))
        SortByDate   -> comparing (^. published)
      sorted = sortBy cmp bks
  in case order of
       Ascending  -> sorted
       Descending -> reverse sorted
  where
    head' (x :| _) = x
    nonEmpty [] = Nothing
    nonEmpty (x:xs) = Just (x :| xs)

-- | Get the currently selected book
getSelectedBook :: AppState -> [Book] -> Maybe Book
getSelectedBook st visibleBooks =
  let idx = st ^. selectedIndex
  in if idx >= 0 && idx < length visibleBooks
       then Just (visibleBooks !! idx)
       else Nothing

-- | Main layout with list and details
mainLayout :: AppState -> [Book] -> Maybe Book -> Maybe Text -> Widget Name
mainLayout st visibleBooks selectedBook msg =
  vBox
    [ -- Header
      withAttr headerAttr $ padAll 1 $
        hBox
          [ txt "libri"
          , padLeft Max $ txt $ T.pack (show (length visibleBooks)) <> " books"
          ]
    , hBorder
    , -- Main content
      hBox
        [ -- Left: Book list
          hLimitPercent 50 $
            titledBorder ("Books" <> searchIndicator st) $
              vBox
                [ padAll 1 $ renderBookList visibleBooks (st ^. selectedIndex)
                , hBorder
                , renderSearchOrHelp st
                ]
        , vBorder
        , -- Right: Book details
          titledBorder "Details" $
            renderBookDetails selectedBook
        ]
    , hBorder
    , -- Footer with status/help
      renderFooter st msg
    ]

-- | Search indicator in title
searchIndicator :: AppState -> Text
searchIndicator st =
  let query = st ^. searchQuery
  in if T.null query
       then ""
       else " [/" <> query <> "]"

-- | Render search bar or help text
renderSearchOrHelp :: AppState -> Widget Name
renderSearchOrHelp st =
  padAll 1 $ case st ^. currentView of
    ViewSearch -> renderSearchBar (st ^. searchQuery) True
    _ -> renderSearchBar (st ^. searchQuery) False

-- | Render the footer
renderFooter :: AppState -> Maybe Text -> Widget Name
renderFooter st msg =
  padLeftRight 1 $
    vBox
      [ case msg of
          Just m -> withAttr helpAttr $ txt m
          Nothing -> emptyWidget
      , hBox
          [ keyHelp
              [ ("/", "Search")
              , ("a", "Add")
              , ("e", "Edit")
              , ("d", "Delete")
              , ("m", "Move")
              , ("?", "Help")
              , ("q", "Quit")
              ]
          , padLeft Max $ renderSortIndicator st
          ]
      ]

-- | Render sort indicator showing current sort and shortcuts
renderSortIndicator :: AppState -> Widget Name
renderSortIndicator st =
  let arrow = case st ^. sortOrder of
        Ascending  -> "↑"
        Descending -> "↓"
      fieldName = case st ^. sortField of
        SortByTitle  -> "Title"
        SortByAuthor -> "Author"
        SortByDate   -> "Date"
  in withAttr helpAttr $
       hBox
         [ txt $ "[st]Title [sa]Author [sd]Date | "
         , withAttr labelAttr $ txt $ fieldName <> " " <> arrow
         ]

-- | Handle events
handleEvent :: BrickEvent Name e -> EventM Name TUIState ()
handleEvent ev = do
  st <- get
  let appSt = tuiAppState st

  case appSt ^. currentView of
    ViewSearch -> do
      -- Handle search input
      case ev of
        VtyEvent (V.EvKey V.KEsc []) ->
          put $ st { tuiAppState = appSt & currentView .~ ViewList
                                         & searchQuery .~ ""
                   , tuiMessage = Nothing
                   }
        VtyEvent (V.EvKey V.KEnter []) ->
          put $ st { tuiAppState = appSt & currentView .~ ViewList
                                         & selectedIndex .~ 0
                   , tuiMessage = Just $ "Search: " <> (appSt ^. searchQuery)
                   }
        VtyEvent (V.EvKey V.KBS []) ->
          put $ st { tuiAppState = appSt & searchQuery %~ T.dropEnd 1 }
        VtyEvent (V.EvKey (V.KChar c) []) ->
          put $ st { tuiAppState = appSt & searchQuery %~ (<> T.singleton c) }
        _ -> pure ()

    ViewAdd -> handleAddEditEvent ev st

    ViewEdit _ -> handleAddEditEvent ev st

    ViewMove _ -> handleMoveEvent ev st

    ViewList -> handleListViewEvent ev st

    _ -> handleListViewEvent ev st

-- | Handle events in list view
handleListViewEvent :: BrickEvent Name e -> TUIState -> EventM Name TUIState ()
handleListViewEvent ev st = do
  let appSt = tuiAppState st
      cfg = appSt ^. config
      visibleBooks = getVisibleBooks appSt

  case ev of
    -- Quit
    VtyEvent (V.EvKey (V.KChar 'q') []) -> halt
    VtyEvent (V.EvKey V.KEsc []) ->
      if tuiConfirmDelete st
        then put $ st { tuiConfirmDelete = False, tuiMessage = Just "Delete cancelled" }
        else halt

    -- Navigation
    VtyEvent (V.EvKey V.KUp []) ->
      put $ st { tuiAppState = appSt & selectedIndex %~ max 0 . subtract 1 }
    VtyEvent (V.EvKey V.KDown []) ->
      put $ st { tuiAppState = appSt & selectedIndex %~ min (length visibleBooks - 1) . (+ 1) }
    VtyEvent (V.EvKey (V.KChar 'k') []) ->
      put $ st { tuiAppState = appSt & selectedIndex %~ max 0 . subtract 1 }
    VtyEvent (V.EvKey (V.KChar 'j') []) ->
      put $ st { tuiAppState = appSt & selectedIndex %~ min (length visibleBooks - 1) . (+ 1) }
    VtyEvent (V.EvKey V.KHome []) ->
      put $ st { tuiAppState = appSt & selectedIndex .~ 0 }
    VtyEvent (V.EvKey V.KEnd []) ->
      put $ st { tuiAppState = appSt & selectedIndex .~ max 0 (length visibleBooks - 1) }
    VtyEvent (V.EvKey V.KPageUp []) ->
      put $ st { tuiAppState = appSt & selectedIndex %~ max 0 . subtract 10 }
    VtyEvent (V.EvKey V.KPageDown []) ->
      put $ st { tuiAppState = appSt & selectedIndex %~ min (length visibleBooks - 1) . (+ 10) }

    -- Search
    VtyEvent (V.EvKey (V.KChar '/') []) ->
      put $ st { tuiAppState = appSt & currentView .~ ViewSearch
               , tuiMessage = Just "Type to search, Enter to confirm, Esc to cancel"
               }

    -- Clear search
    VtyEvent (V.EvKey (V.KChar 'c') [V.MCtrl]) ->
      put $ st { tuiAppState = appSt & searchQuery .~ ""
                                     & selectedIndex .~ 0
               , tuiMessage = Just "Search cleared"
               }

    -- Delete (only when no pending key)
    VtyEvent (V.EvKey (V.KChar 'd') []) | tuiPendingKey st == Nothing ->
      case getSelectedBook appSt visibleBooks of
        Nothing -> pure ()
        Just book ->
          if tuiConfirmDelete st
            then do
              -- Actually delete
              result <- liftIO $ deleteBook cfg book
              case result of
                Left err ->
                  put $ st { tuiMessage = Just $ "Error: " <> T.pack (show err)
                           , tuiConfirmDelete = False
                           }
                Right () -> do
                  -- Reload books
                  booksResult <- liftIO $ loadBooks cfg
                  let newBooks = either (const []) (sortBy (comparing (^. title))) booksResult
                  put $ st { tuiAppState = appSt & books .~ newBooks
                                                 & selectedIndex %~ min (length newBooks - 1) . max 0
                           , tuiMessage = Just $ "Deleted: " <> (book ^. title)
                           , tuiConfirmDelete = False
                           }
            else
              put $ st { tuiMessage = Just $ "Press 'd' again to delete: " <> (book ^. title)
                       , tuiConfirmDelete = True
                       }

    -- Refresh
    VtyEvent (V.EvKey (V.KChar 'r') []) -> do
      booksResult <- liftIO $ loadBooks cfg
      let newBooks = either (const []) (sortBy (comparing (^. title))) booksResult
      put $ st { tuiAppState = appSt & books .~ newBooks
               , tuiMessage = Just $ "Refreshed: " <> T.pack (show (length newBooks)) <> " books"
               }

    -- Help
    VtyEvent (V.EvKey (V.KChar '?') []) ->
      put $ st { tuiMessage = Just "j/k:nav /search a:add e:edit d:del m:move r:refresh q:quit" }

    -- Add new book (only when no pending key)
    VtyEvent (V.EvKey (V.KChar 'a') []) | tuiPendingKey st == Nothing ->
      put $ st { tuiAppState = appSt & currentView .~ ViewAdd
               , tuiAddBookState = Just initAddBookState
               , tuiMessage = Nothing
               }

    -- Edit selected book
    VtyEvent (V.EvKey (V.KChar 'e') []) ->
      case getSelectedBook appSt visibleBooks of
        Nothing -> put $ st { tuiMessage = Just "No book selected" }
        Just book ->
          put $ st { tuiAppState = appSt & currentView .~ ViewEdit (book ^. bookId)
                   , tuiAddBookState = Just (initEditBookState book)
                   , tuiMessage = Nothing
                   }

    -- Move selected book
    VtyEvent (V.EvKey (V.KChar 'm') []) ->
      case getSelectedBook appSt visibleBooks of
        Nothing -> put $ st { tuiMessage = Just "No book selected" }
        Just book ->
          let predefinedLocs = appSt ^. locations
              -- Collect unique locations from all books
              usedLocs = nub $ catMaybes $ map (^. location) (appSt ^. books)
              -- Merge: predefined first, then any used locations not in predefined
              allLocs = predefinedLocs ++ filter (`notElem` predefinedLocs) usedLocs
          in put $ st { tuiAppState = appSt & currentView .~ ViewMove (book ^. bookId)
                      , tuiMoveBookState = Just (initMoveBookState book allLocs)
                      , tuiMessage = Nothing
                      }

    -- Sort: 's' starts sort sequence
    VtyEvent (V.EvKey (V.KChar 's') []) ->
      put $ st { tuiPendingKey = Just 's'
               , tuiMessage = Just "Sort: [t]itle [a]uthor [d]ate"
               , tuiConfirmDelete = False
               }

    -- Sort by title: 't' after 's'
    VtyEvent (V.EvKey (V.KChar 't') []) | tuiPendingKey st == Just 's' ->
      let newOrder = if appSt ^. sortField == SortByTitle
                       then toggleSortOrder (appSt ^. sortOrder)
                       else Ascending
      in put $ st { tuiAppState = appSt & sortField .~ SortByTitle
                                        & sortOrder .~ newOrder
                                        & selectedIndex .~ 0
                  , tuiPendingKey = Nothing
                  , tuiMessage = Just $ "Sorted by title " <> sortArrow newOrder
                  , tuiConfirmDelete = False
                  }

    -- Sort by author: 'a' after 's'
    VtyEvent (V.EvKey (V.KChar 'a') []) | tuiPendingKey st == Just 's' ->
      let newOrder = if appSt ^. sortField == SortByAuthor
                       then toggleSortOrder (appSt ^. sortOrder)
                       else Ascending
      in put $ st { tuiAppState = appSt & sortField .~ SortByAuthor
                                        & sortOrder .~ newOrder
                                        & selectedIndex .~ 0
                  , tuiPendingKey = Nothing
                  , tuiMessage = Just $ "Sorted by author " <> sortArrow newOrder
                  , tuiConfirmDelete = False
                  }

    -- Sort by date: 'd' after 's'
    VtyEvent (V.EvKey (V.KChar 'd') []) | tuiPendingKey st == Just 's' ->
      let newOrder = if appSt ^. sortField == SortByDate
                       then toggleSortOrder (appSt ^. sortOrder)
                       else Ascending
      in put $ st { tuiAppState = appSt & sortField .~ SortByDate
                                        & sortOrder .~ newOrder
                                        & selectedIndex .~ 0
                  , tuiPendingKey = Nothing
                  , tuiMessage = Just $ "Sorted by date " <> sortArrow newOrder
                  , tuiConfirmDelete = False
                  }

    -- Any other key clears the confirm delete state, pending key, and message
    VtyEvent (V.EvKey _ _) ->
      when (tuiConfirmDelete st || tuiPendingKey st /= Nothing) $
        put $ st { tuiConfirmDelete = False, tuiPendingKey = Nothing, tuiMessage = Nothing }

    _ -> pure ()

-- | Toggle sort order
toggleSortOrder :: SortOrder -> SortOrder
toggleSortOrder Ascending  = Descending
toggleSortOrder Descending = Ascending

-- | Get arrow for sort order
sortArrow :: SortOrder -> Text
sortArrow Ascending  = "↑"
sortArrow Descending = "↓"

-- | Handle events in add/edit view
handleAddEditEvent :: BrickEvent Name e -> TUIState -> EventM Name TUIState ()
handleAddEditEvent ev st = do
  let appSt = tuiAppState st
      cfg = appSt ^. config

  case tuiAddBookState st of
    Nothing -> put $ st { tuiAppState = appSt & currentView .~ ViewList }
    Just abs' -> case ev of
      -- Custom field editing mode handlers (must come before general Esc/Enter)
      VtyEvent (V.EvKey V.KEsc []) | absEditingCustom abs' ->
        -- Exit custom fields editing mode
        put $ st { tuiAddBookState = Just $ abs' { absEditingCustom = False } }

      VtyEvent (V.EvKey V.KEnter []) | absEditingCustom abs' ->
        -- Edit selected custom field value in external editor
        if null (absCustomFields abs')
          then pure ()
          else do
            let idx = absCustomFieldIdx abs'
                (key, oldValue) = absCustomFields abs' !! idx
            suspendAndResume $ do
              editor <- fromMaybe "vim" <$> lookupEnv "EDITOR"
              withSystemTempFile "libri-custom.txt" $ \path handle -> do
                T.hPutStr handle oldValue
                hFlush handle
                hClose handle
                callProcess editor [path]
                newValue <- T.strip <$> T.readFile path
                let newFields = take idx (absCustomFields abs') ++
                                [(key, newValue)] ++
                                drop (idx + 1) (absCustomFields abs')
                pure $ st { tuiAddBookState = Just $ abs' { absCustomFields = newFields }
                          , tuiMessage = Just $ "Updated: " <> key
                          }

      VtyEvent (V.EvKey V.KEnter []) | absCurrentField abs' == 9 ->
        -- Enter custom fields editing mode
        put $ st { tuiAddBookState = Just $ abs' { absEditingCustom = True, absCustomFieldIdx = 0 } }

      VtyEvent (V.EvKey V.KEsc []) ->
        -- Cancel, return to list
        put $ st { tuiAppState = appSt & currentView .~ ViewList
                 , tuiAddBookState = Nothing
                 , tuiMessage = Just "Cancelled"
                 }

      VtyEvent (V.EvKey V.KEnter []) ->
        if T.null (absTitle abs')
          then put $ st { tuiMessage = Just "Title is required" }
          else do
            now <- liftIO getCurrentTime
            newId <- case absOriginalId abs' of
              Just origId -> pure origId
              Nothing -> do
                if T.null (absIsbn abs')
                  then liftIO $ UUID.toText <$> UUID.nextRandom
                  else pure (T.filter (\c -> c /= '-' && c /= ' ') (absIsbn abs'))

            let addedTime = fromMaybe now (absOriginalAdded abs')
                book = Book
                  { _bookId = newId
                  , _isbn = if T.null (absIsbn abs') then Nothing else Just (absIsbn abs')
                  , _title = absTitle abs'
                  , _authors = parseCommaSeparated (absAuthors abs')
                  , _series = Nothing
                  , _seriesIndex = Nothing
                  , _publisher = if T.null (absPublisher abs') then Nothing else Just (absPublisher abs')
                  , _published = parseYear (absPublished abs')
                  , _tags = parseCommaSeparated (absTags abs')
                  , _rating = parseRating (absRating abs')
                  , _comments = if T.null (absComments abs') then Nothing else Just (absComments abs')
                  , _location = if T.null (absLocation abs') then Nothing else Just (absLocation abs')
                  , _custom = Map.fromList $ map (\(k, v) -> (k, String v)) (absCustomFields abs')
                  , _added = addedTime
                  , _modified = now
                  }
            result <- liftIO $ saveBook cfg book
            case result of
              Left err ->
                put $ st { tuiMessage = Just $ "Error: " <> T.pack (show err) }
              Right () -> do
                -- Reload books
                booksResult <- liftIO $ loadBooks cfg
                let newBooks = either (const []) (sortBy (comparing (^. title))) booksResult
                put $ st { tuiAppState = appSt & books .~ newBooks
                                               & currentView .~ ViewList
                         , tuiAddBookState = Nothing
                         , tuiMessage = Just $ "Saved: " <> absTitle abs'
                         }

      VtyEvent (V.EvKey (V.KChar '\t') []) ->
        -- Move to next field (skip if in custom editing mode)
        if absEditingCustom abs'
          then pure ()
          else put $ st { tuiAddBookState = Just $ abs' { absCurrentField = (absCurrentField abs' + 1) `mod` 10 } }

      VtyEvent (V.EvKey V.KBackTab []) ->
        -- Move to previous field (skip if in custom editing mode)
        if absEditingCustom abs'
          then pure ()
          else put $ st { tuiAddBookState = Just $ abs' { absCurrentField = (absCurrentField abs' - 1 + 10) `mod` 10 } }

      VtyEvent (V.EvKey V.KBS []) ->
        -- Backspace in current field (skip if in custom editing mode)
        if absEditingCustom abs'
          then pure ()
          else put $ st { tuiAddBookState = Just $ updateCurrentField (T.dropEnd 1) abs' }

      VtyEvent (V.EvKey (V.KChar 'e') [V.MCtrl]) ->
        -- Edit comments in external editor
        if absCurrentField abs' == 8 && not (absEditingCustom abs')
          then suspendAndResume $ do
            editor <- fromMaybe "vim" <$> lookupEnv "EDITOR"
            withSystemTempFile "libri-comment.txt" $ \path handle -> do
              T.hPutStr handle (absComments abs')
              hFlush handle
              hClose handle
              callProcess editor [path]
              newComments <- T.readFile path
              pure $ st { tuiAddBookState = Just $ abs' { absComments = T.strip newComments }
                        , tuiMessage = Just "Comments updated"
                        }
          else pure ()

      VtyEvent (V.EvKey (V.KChar 'j') []) | absEditingCustom abs' ->
        -- Navigate down in custom fields
        let maxIdx = max 0 (length (absCustomFields abs') - 1)
        in put $ st { tuiAddBookState = Just $ abs' { absCustomFieldIdx = min maxIdx (absCustomFieldIdx abs' + 1) } }

      VtyEvent (V.EvKey (V.KChar 'k') []) | absEditingCustom abs' ->
        -- Navigate up in custom fields
        put $ st { tuiAddBookState = Just $ abs' { absCustomFieldIdx = max 0 (absCustomFieldIdx abs' - 1) } }

      VtyEvent (V.EvKey (V.KChar 'a') []) | absEditingCustom abs' ->
        -- Add new custom field (for now, add placeholder that user can edit)
        let newField = ("new_field", "")
            newFields = absCustomFields abs' ++ [newField]
            newIdx = length newFields - 1
        in put $ st { tuiAddBookState = Just $ abs' { absCustomFields = newFields, absCustomFieldIdx = newIdx }
                    , tuiMessage = Just "Added field - press Enter to edit value"
                    }

      VtyEvent (V.EvKey (V.KChar 'd') []) | absEditingCustom abs' ->
        -- Delete selected custom field
        if null (absCustomFields abs')
          then pure ()
          else
            let idx = absCustomFieldIdx abs'
                fields = absCustomFields abs'
                newFields = take idx fields ++ drop (idx + 1) fields
                newIdx = min (absCustomFieldIdx abs') (max 0 (length newFields - 1))
            in put $ st { tuiAddBookState = Just $ abs' { absCustomFields = newFields, absCustomFieldIdx = newIdx }
                        , tuiMessage = Just "Field deleted"
                        }

      VtyEvent (V.EvKey (V.KChar 'r') []) | absEditingCustom abs' ->
        -- Rename selected custom field key
        if null (absCustomFields abs')
          then pure ()
          else do
            let idx = absCustomFieldIdx abs'
                (oldKey, value) = absCustomFields abs' !! idx
            suspendAndResume $ do
              editor <- fromMaybe "vim" <$> lookupEnv "EDITOR"
              withSystemTempFile "libri-fieldname.txt" $ \path handle -> do
                T.hPutStr handle oldKey
                hFlush handle
                hClose handle
                callProcess editor [path]
                newKey <- T.strip <$> T.readFile path
                let newFields = take idx (absCustomFields abs') ++
                                [(newKey, value)] ++
                                drop (idx + 1) (absCustomFields abs')
                pure $ st { tuiAddBookState = Just $ abs' { absCustomFields = newFields }
                          , tuiMessage = Just $ "Renamed: " <> oldKey <> " → " <> newKey
                          }

      VtyEvent (V.EvKey (V.KChar 'l') [V.MCtrl]) ->
        -- Lookup ISBN
        if T.null (absIsbn abs')
          then put $ st { tuiMessage = Just "Enter an ISBN first" }
          else do
            put $ st { tuiMessage = Just $ "Looking up ISBN: " <> absIsbn abs' }
            result <- liftIO $ fetchByISBN (absIsbn abs')
            case result of
              Left err ->
                put $ st { tuiMessage = Just $ "Lookup failed: " <> T.pack (show err) }
              Right book -> do
                -- Update form fields with fetched data
                let newAbs = abs'
                      { absTitle = book ^. title
                      , absAuthors = T.intercalate ", " (book ^. authors)
                      , absPublisher = maybe (absPublisher abs') id (book ^. publisher)
                      , absPublished = maybe (absPublished abs') (T.pack . show) (book ^. published)
                      , absLocation = maybe (absLocation abs') id (book ^. location)
                      , absTags = T.intercalate ", " (book ^. tags)
                      }
                put $ st { tuiAddBookState = Just newAbs
                         , tuiMessage = Just $ "Found: " <> (book ^. title)
                         }

      VtyEvent (V.EvKey (V.KChar c) []) ->
        -- Add character to current field (skip if in custom editing mode)
        if absEditingCustom abs'
          then pure ()
          else put $ st { tuiAddBookState = Just $ updateCurrentField (<> T.singleton c) abs' }

      _ -> pure ()

-- | Handle events in move view
handleMoveEvent :: BrickEvent Name e -> TUIState -> EventM Name TUIState ()
handleMoveEvent ev st = do
  let appSt = tuiAppState st
      cfg = appSt ^. config
      allBooks = appSt ^. books

  case tuiMoveBookState st of
    Nothing -> put $ st { tuiAppState = appSt & currentView .~ ViewList }
    Just mbs -> case ev of
      VtyEvent (V.EvKey V.KEsc []) ->
        -- Cancel, return to list
        put $ st { tuiAppState = appSt & currentView .~ ViewList
                 , tuiMoveBookState = Nothing
                 , tuiMessage = Just "Cancelled"
                 }

      VtyEvent (V.EvKey V.KEnter []) ->
        -- Apply the move
        let locs = mbsLocations mbs
            idx = mbsSelectedIndex mbs
            newLoc = if idx >= 0 && idx < length locs
                       then Just (locs !! idx)
                       else Nothing
            targetBookId = mbsBookId mbs
        in case findBookById targetBookId allBooks of
             Nothing ->
               put $ st { tuiMessage = Just "Book not found"
                        , tuiAppState = appSt & currentView .~ ViewList
                        , tuiMoveBookState = Nothing
                        }
             Just book -> do
               let updatedBook = book & location .~ newLoc
               result <- liftIO $ saveBook cfg updatedBook
               case result of
                 Left err ->
                   put $ st { tuiMessage = Just $ "Error: " <> T.pack (show err) }
                 Right () -> do
                   -- Reload books
                   booksResult <- liftIO $ loadBooks cfg
                   let newBooks = either (const []) (sortBy (comparing (^. title))) booksResult
                   put $ st { tuiAppState = appSt & books .~ newBooks
                                                  & currentView .~ ViewList
                            , tuiMoveBookState = Nothing
                            , tuiMessage = Just $ "Moved: " <> (book ^. title) <> " → " <> maybe "(none)" id newLoc
                            }

      -- Navigation
      VtyEvent (V.EvKey V.KUp []) ->
        put $ st { tuiMoveBookState = Just $ mbs { mbsSelectedIndex = max 0 (mbsSelectedIndex mbs - 1) } }
      VtyEvent (V.EvKey V.KDown []) ->
        put $ st { tuiMoveBookState = Just $ mbs { mbsSelectedIndex = min (length (mbsLocations mbs) - 1) (mbsSelectedIndex mbs + 1) } }
      VtyEvent (V.EvKey (V.KChar 'k') []) ->
        put $ st { tuiMoveBookState = Just $ mbs { mbsSelectedIndex = max 0 (mbsSelectedIndex mbs - 1) } }
      VtyEvent (V.EvKey (V.KChar 'j') []) ->
        put $ st { tuiMoveBookState = Just $ mbs { mbsSelectedIndex = min (length (mbsLocations mbs) - 1) (mbsSelectedIndex mbs + 1) } }

      _ -> pure ()

-- | Find a book by its ID
findBookById :: BookId -> [Book] -> Maybe Book
findBookById bid = listToMaybe . filter (\b -> b ^. bookId == bid)

-- | Parse year text to Day (January 1st of that year)
parseYear :: Text -> Maybe Day
parseYear t =
  case readMaybe (T.unpack t) of
    Just year | year >= 1000 && year <= 9999 -> Just (fromGregorian year 1 1)
    _ -> Nothing

-- | Parse rating text to Maybe Int (1-5)
parseRating :: Text -> Maybe Int
parseRating t =
  case T.unpack t of
    [c] | c `elem` ("12345" :: String) -> Just (read [c])
    _ -> Nothing
