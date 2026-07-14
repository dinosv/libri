module Libri.TUI.App
  ( runTUI
  , TUIState (..)
  ) where

import Brick
import Brick.Widgets.Border
import Control.Applicative ((<|>))
import Control.Monad (void, when)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Value(..))
import Data.List (nub, sort, sortBy)
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, listToMaybe, fromMaybe, isJust)
import Data.Ord (comparing)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import Data.Time (Day, getCurrentTime, fromGregorian, parseTimeM, defaultTimeLocale)
import Text.Read (readMaybe)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import qualified Graphics.Vty as V
import Graphics.Vty.CrossPlatform (mkVty)
import Lens.Micro ((^.), (&), (.~), (%~))
import Libri.ISBN.OpenLibrary (fetchByISBN)
import Libri.Search.Fuzzy (searchBooks)
import Libri.Storage.Yaml (loadBooksWithErrors, loadLocations, saveBook, deleteBook)
import Libri.TUI.CommandBar (CommandBarState(..), Command(..), initCommandBarState, parseCommand, completeNext, renderCommandBar)
import Libri.TUI.Views.AddBook
import Libri.TUI.Views.BookDetails (renderBookDetails)
import Libri.TUI.Views.BookList (renderBookList)
import Libri.TUI.Views.GroupedList (ListItem(..), buildGroupedList, renderGroupedList, nextSelectableIndex, prevSelectableIndex, firstSelectableIndex, lastSelectableIndex)
import Libri.TUI.Views.TagSidebar (TagEntry, buildTagEntries, entryToFilter, entryLabel, renderTagSidebar)
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
  , tuiConfirmDelete :: Maybe BookId -- ID of the book armed for deletion,
                                     -- so navigating away cannot delete
                                     -- a different book unconfirmed
  , tuiAddBookState :: Maybe AddBookState   -- Add/Edit form state
  , tuiMoveBookState :: Maybe MoveBookState -- Move dialog state
  , tuiPendingKey :: Maybe Char     -- For two-key sequences like 'st', 'sa', 'sd'
  , tuiCommandBarState :: Maybe CommandBarState
  , tuiSidebarFocus :: Bool         -- Tag sidebar has keyboard focus
  , tuiTagIndex :: Int              -- Selected entry in the tag sidebar
  }
  deriving (Show)

-- | Run the TUI application
runTUI :: Config -> IO ()
runTUI cfg = do
  -- Load initial data
  (loadErrs, books') <- loadBooksWithErrors cfg
  locsResult <- loadLocations cfg

  let locs = either (const []) id locsResult
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
        , tuiMessage = Just $
            "Loaded " <> T.pack (show (length books')) <> " books"
            <> (if null loadErrs
                  then ""
                  else " (" <> T.pack (show (length loadErrs)) <> " files unreadable)")
        , tuiConfirmDelete = Nothing
        , tuiAddBookState = Nothing
        , tuiMoveBookState = Nothing
        , tuiPendingKey = Nothing
        , tuiCommandBarState = Nothing
        , tuiSidebarFocus = False
        , tuiTagIndex = 0
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
           Just abs' -> [withFormMessage (tuiMessage st) (renderAddBook abs')]
           Nothing -> [mainLayout st appSt visibleBooks selectedBook]
       ViewEdit _ ->
         case tuiAddBookState st of
           Just abs' -> [withFormMessage (tuiMessage st) (renderEditBook abs')]
           Nothing -> [mainLayout st appSt visibleBooks selectedBook]
       ViewMove _ ->
         case tuiMoveBookState st of
           Just mbs -> [withFormMessage (tuiMessage st) (renderMoveBook mbs)]
           Nothing -> [mainLayout st appSt visibleBooks selectedBook]
       _ -> [mainLayout st appSt visibleBooks selectedBook]

-- | Show the status message underneath dialog views, which otherwise
-- give no feedback for validation and save errors
withFormMessage :: Maybe Text -> Widget Name -> Widget Name
withFormMessage Nothing w = w
withFormMessage (Just m) w = vBox [w, withAttr helpAttr $ padLeftRight 1 $ txt m]

-- | Get books filtered by search query and sorted
getVisibleBooks :: AppState -> [Book]
getVisibleBooks st =
  let query = st ^. searchQuery
      filtered = applyFilter (st ^. activeFilter) (st ^. books)
      sorted = applySortOrder (st ^. sortField) (st ^. sortOrder) filtered
      threshold = st ^. config . fuzzyThreshold
  in if T.null query
       then sorted
       else searchBooks threshold query sorted

applyFilter :: Maybe Filter -> [Book] -> [Book]
applyFilter Nothing bks = bks
applyFilter (Just f) bks = filter (matchesFilter f) bks

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

-- | Reload books from disk, sorted by title
reloadBooks :: Config -> IO ([(FilePath, LibriError)], [Book])
reloadBooks cfg = do
  (errs, bks) <- loadBooksWithErrors cfg
  pure (errs, sortBy (comparing (^. title)) bks)

-- | Index to select after the visible list changes: the first book row,
-- skipping section headers when grouping is active
resetIndex :: AppState -> Int
resetIndex appSt =
  case appSt ^. groupMode of
    Nothing -> 0
    Just gf ->
      let items = buildGroupedList gf (appSt ^. sortField) (appSt ^. sortOrder) (getVisibleBooks appSt)
      in firstSelectableIndex items

-- | Get the currently selected book
getSelectedBook :: AppState -> [Book] -> Maybe Book
getSelectedBook st visibleBks =
  case st ^. groupMode of
    Nothing ->
      let idx = st ^. selectedIndex
      in if idx >= 0 && idx < length visibleBks
           then Just (visibleBks !! idx)
           else Nothing
    Just gf ->
      let items = buildGroupedList gf (st ^. sortField) (st ^. sortOrder) visibleBks
          idx = st ^. selectedIndex
      in case drop idx items of
           (BookRow b : _) -> Just b
           _ -> Nothing

-- | Main layout with tag sidebar, list and details
mainLayout :: TUIState -> AppState -> [Book] -> Maybe Book -> Widget Name
mainLayout tst st visibleBooks selectedBook =
  let msg = tuiMessage tst
      mCbs = tuiCommandBarState tst
      entries = buildTagEntries (st ^. books)
      tagIdx = clampTagIndex entries (tuiTagIndex tst)
  in vBox
    [ -- Header
      withAttr headerAttr $ padAll 1 $
        hBox
          [ txt "libri"
          , padLeft Max $ txt $ T.pack (show (length visibleBooks)) <> " books"
          ]
    , hBorder
    , -- Main content
      hBox
        [ -- Left: Tag sidebar
          hLimit 22 $
            titledBorder "Tags" $
              padAll 1 $ renderTagSidebar entries tagIdx (tuiSidebarFocus tst) (st ^. activeFilter)
        , vBorder
        , -- Middle: Book list
          hLimitPercent 55 $
            titledBorder ("Books" <> searchIndicator st <> filterIndicator st) $
              vBox
                [ padAll 1 $ renderBookArea st visibleBooks
                , hBorder
                , renderSearchLine st
                ]
        , vBorder
        , -- Right: Book details
          titledBorder "Details" $
            renderBookDetails selectedBook
        ]
    , hBorder
    , -- Footer with status/help
      renderFooter st msg
    , -- Command bar (always at the very bottom when active)
      renderCommandLine st mCbs
    ]

-- | Keep the sidebar selection inside the current entry list
clampTagIndex :: [TagEntry] -> Int -> Int
clampTagIndex entries idx = max 0 (min (length entries - 1) idx)

-- | Search indicator in title
searchIndicator :: AppState -> Text
searchIndicator st =
  let query = st ^. searchQuery
  in if T.null query
       then ""
       else " [/" <> query <> "]"

renderBookArea :: AppState -> [Book] -> Widget Name
renderBookArea st bks =
  case st ^. groupMode of
    Nothing -> renderBookList bks (st ^. selectedIndex)
    Just gf ->
      let items = buildGroupedList gf (st ^. sortField) (st ^. sortOrder) bks
      in renderGroupedList items (st ^. selectedIndex)

filterIndicator :: AppState -> Text
filterIndicator st =
  case st ^. activeFilter of
    Nothing -> ""
    Just (FilterTag t)      -> " [tag:" <> t <> "]"
    Just (FilterAuthor a)   -> " [author:" <> a <> "]"
    Just (FilterTagExact t) -> " [tag:" <> t <> "]"
    Just FilterUntagged     -> " [untagged]"

renderSearchLine :: AppState -> Widget Name
renderSearchLine st =
  padAll 1 $ case st ^. currentView of
    ViewSearch -> renderSearchBar (st ^. searchQuery) True
    _          -> renderSearchBar (st ^. searchQuery) False

renderCommandLine :: AppState -> Maybe CommandBarState -> Widget Name
renderCommandLine st mCbs =
  case st ^. currentView of
    ViewCommand -> case mCbs of
      Just cbs -> padLeftRight 1 $ renderCommandBar cbs
      Nothing  -> emptyWidget
    _ -> emptyWidget

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
              [ ("Tab", "Tags")
              , ("/", "Search")
              , (":", "Command")
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
          let newAppSt = appSt & currentView .~ ViewList
                               & searchQuery .~ ""
          in put $ st { tuiAppState = newAppSt & selectedIndex .~ resetIndex newAppSt
                      , tuiMessage = Nothing
                      }
        VtyEvent (V.EvKey V.KEnter []) ->
          let newAppSt = appSt & currentView .~ ViewList
          in put $ st { tuiAppState = newAppSt & selectedIndex .~ resetIndex newAppSt
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

    ViewCommand -> handleCommandBarEvent ev st

    ViewList -> handleListViewEvent ev st

    _ -> handleListViewEvent ev st

-- | Handle events in list view
handleListViewEvent :: BrickEvent Name e -> TUIState -> EventM Name TUIState ()
handleListViewEvent ev st = do
  let appSt = tuiAppState st
      cfg = appSt ^. config
      visibleBooks = getVisibleBooks appSt
      -- Grouped-mode item list, when grouping is active
      mItems = case appSt ^. groupMode of
        Nothing -> Nothing
        Just gf -> Just (buildGroupedList gf (appSt ^. sortField) (appSt ^. sortOrder) visibleBooks)
      firstIdx = maybe 0 firstSelectableIndex mItems
      lastIdx = maybe (max 0 (length visibleBooks - 1)) lastSelectableIndex mItems
      pageUpIdx i = case mItems of
        Nothing -> max 0 (i - 10)
        Just items -> iterate (prevSelectableIndex items) i !! 10
      pageDownIdx i = case mItems of
        Nothing -> max 0 (min (length visibleBooks - 1) (i + 10))
        Just items -> iterate (nextSelectableIndex items) i !! 10
      -- Tag sidebar state
      entries = buildTagEntries (appSt ^. books)
      tagIdx = clampTagIndex entries (tuiTagIndex st)
      handleSidebarKey key = case key of
        V.KChar 'q' -> halt
        V.KEsc ->
          put $ st { tuiSidebarFocus = False }
        V.KChar '\t' ->
          put $ st { tuiSidebarFocus = False }
        V.KUp ->
          put $ st { tuiTagIndex = clampTagIndex entries (tagIdx - 1) }
        V.KChar 'k' ->
          put $ st { tuiTagIndex = clampTagIndex entries (tagIdx - 1) }
        V.KDown ->
          put $ st { tuiTagIndex = clampTagIndex entries (tagIdx + 1) }
        V.KChar 'j' ->
          put $ st { tuiTagIndex = clampTagIndex entries (tagIdx + 1) }
        V.KEnter ->
          case drop tagIdx entries of
            (entry : _) ->
              let newFilter = entryToFilter entry
                  newAppSt = appSt & activeFilter .~ newFilter
                  msg = case newFilter of
                    Nothing -> "Showing all books"
                    Just _ -> "Filter: " <> entryLabel entry
              in put $ st { tuiAppState = newAppSt & selectedIndex .~ resetIndex newAppSt
                          , tuiSidebarFocus = False
                          , tuiTagIndex = tagIdx
                          , tuiMessage = Just msg
                          }
            [] -> pure ()
        _ -> pure ()
      -- Complete or cancel a pending 's' sort sequence
      applySort sf =
        let newOrder = if appSt ^. sortField == sf
                         then toggleSortOrder (appSt ^. sortOrder)
                         else Ascending
            newAppSt = appSt & sortField .~ sf
                             & sortOrder .~ newOrder
        in put $ st { tuiAppState = newAppSt & selectedIndex .~ resetIndex newAppSt
                    , tuiPendingKey = Nothing
                    , tuiMessage = Just $ "Sorted by " <> sortFieldName sf <> " " <> sortArrow newOrder
                    , tuiConfirmDelete = Nothing
                    }

  case ev of
    -- Tag sidebar focused: it owns the keys until focus returns
    VtyEvent (V.EvKey key _) | tuiSidebarFocus st ->
      handleSidebarKey key

    -- Focus the tag sidebar
    VtyEvent (V.EvKey (V.KChar '\t') []) ->
      put $ st { tuiSidebarFocus = True
               , tuiConfirmDelete = Nothing
               , tuiMessage = Just "Tags: j/k to move, Enter to filter, Esc to return"
               }

    -- Pending sort sequence: the next key either completes it or cancels it,
    -- so stale pending state can never hijack later 'a'/'d' presses
    VtyEvent (V.EvKey key _) | tuiPendingKey st == Just 's' ->
      case key of
        V.KChar 't' -> applySort SortByTitle
        V.KChar 'a' -> applySort SortByAuthor
        V.KChar 'd' -> applySort SortByDate
        _ -> put $ st { tuiPendingKey = Nothing, tuiMessage = Nothing }

    -- Quit
    VtyEvent (V.EvKey (V.KChar 'q') []) -> halt
    VtyEvent (V.EvKey V.KEsc []) ->
      if isJust (tuiConfirmDelete st)
        then put $ st { tuiConfirmDelete = Nothing, tuiMessage = Just "Delete cancelled" }
        else halt

    -- Navigation
    VtyEvent (V.EvKey V.KUp []) -> navigateUp st appSt visibleBooks
    VtyEvent (V.EvKey V.KDown []) -> navigateDown st appSt visibleBooks
    VtyEvent (V.EvKey (V.KChar 'k') []) -> navigateUp st appSt visibleBooks
    VtyEvent (V.EvKey (V.KChar 'j') []) -> navigateDown st appSt visibleBooks
    VtyEvent (V.EvKey V.KHome []) ->
      put $ st { tuiAppState = appSt & selectedIndex .~ firstIdx }
    VtyEvent (V.EvKey V.KEnd []) ->
      put $ st { tuiAppState = appSt & selectedIndex .~ lastIdx }
    VtyEvent (V.EvKey V.KPageUp []) ->
      put $ st { tuiAppState = appSt & selectedIndex %~ pageUpIdx }
    VtyEvent (V.EvKey V.KPageDown []) ->
      put $ st { tuiAppState = appSt & selectedIndex %~ pageDownIdx }

    -- Search
    VtyEvent (V.EvKey (V.KChar '/') []) ->
      put $ st { tuiAppState = appSt & currentView .~ ViewSearch
               , tuiMessage = Just "Type to search, Enter to confirm, Esc to cancel"
               }

    -- Clear search
    VtyEvent (V.EvKey (V.KChar 'c') [V.MCtrl]) ->
      let newAppSt = appSt & searchQuery .~ ""
      in put $ st { tuiAppState = newAppSt & selectedIndex .~ resetIndex newAppSt
                  , tuiMessage = Just "Search cleared"
                  }

    -- Delete: first press arms deletion of the selected book; the second
    -- press only deletes if the selection is still that same book
    VtyEvent (V.EvKey (V.KChar 'd') []) ->
      case getSelectedBook appSt visibleBooks of
        Nothing -> pure ()
        Just book ->
          if tuiConfirmDelete st == Just (book ^. bookId)
            then do
              -- Actually delete
              result <- liftIO $ deleteBook cfg book
              case result of
                Left err ->
                  put $ st { tuiMessage = Just $ "Error: " <> T.pack (show err)
                           , tuiConfirmDelete = Nothing
                           }
                Right () -> do
                  -- Reload books
                  (_, newBooks) <- liftIO $ reloadBooks cfg
                  put $ st { tuiAppState = appSt & books .~ newBooks
                                                 & selectedIndex %~ max 0 . min (length newBooks - 1)
                           , tuiMessage = Just $ "Deleted: " <> (book ^. title)
                           , tuiConfirmDelete = Nothing
                           }
            else
              put $ st { tuiMessage = Just $ "Press 'd' again to delete: " <> (book ^. title)
                       , tuiConfirmDelete = Just (book ^. bookId)
                       }

    -- Refresh
    VtyEvent (V.EvKey (V.KChar 'r') []) -> do
      (errs, newBooks) <- liftIO $ reloadBooks cfg
      put $ st { tuiAppState = appSt & books .~ newBooks
               , tuiMessage = Just $ "Refreshed: " <> T.pack (show (length newBooks)) <> " books"
                   <> (if null errs then "" else " (" <> T.pack (show (length errs)) <> " files unreadable)")
               , tuiConfirmDelete = Nothing
               }

    -- Command bar
    VtyEvent (V.EvKey (V.KChar ':') []) ->
      let allTags = nub $ sort $ concatMap (^. tags) (appSt ^. books)
          allAuthors = nub $ sort $ concatMap (^. authors) (appSt ^. books)
          cbs = initCommandBarState allTags allAuthors
      in put $ st { tuiAppState = appSt & currentView .~ ViewCommand
                  , tuiCommandBarState = Just cbs
                  , tuiMessage = Just "Type command, Tab to complete, Enter to execute"
                  }

    -- Help
    VtyEvent (V.EvKey (V.KChar '?') []) ->
      put $ st { tuiMessage = Just "j/k:nav /search a:add e:edit d:del m:move r:refresh q:quit" }

    -- Add new book
    VtyEvent (V.EvKey (V.KChar 'a') []) ->
      put $ st { tuiAppState = appSt & currentView .~ ViewAdd
               , tuiAddBookState = Just initAddBookState
               , tuiMessage = Nothing
               , tuiConfirmDelete = Nothing
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
               , tuiConfirmDelete = Nothing
               }

    -- Any other key clears the confirm delete state and message
    VtyEvent (V.EvKey _ _) ->
      when (isJust (tuiConfirmDelete st)) $
        put $ st { tuiConfirmDelete = Nothing, tuiMessage = Nothing }

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
            let mOrig = absOriginal abs'
            newId <- case mOrig of
              Just orig -> pure (orig ^. bookId)
              Nothing -> do
                if T.null (absIsbn abs')
                  then liftIO $ UUID.toText <$> UUID.nextRandom
                  else pure (T.filter (\c -> c /= '-' && c /= ' ') (absIsbn abs'))

            -- Adding (not editing) must never silently overwrite or
            -- duplicate an existing book that shares the same ID/ISBN
            let normIsbn = T.filter (\c -> c /= '-' && c /= ' ')
                newIsbn = if T.null (absIsbn abs')
                            then Nothing
                            else Just (normIsbn (absIsbn abs'))
                sameBook b =
                  b ^. bookId == newId
                    || (case (newIsbn, b ^. isbn) of
                          (Just ni, Just bi) -> normIsbn bi == ni
                          _ -> False)
                clashes = mOrig == Nothing && any sameBook (appSt ^. books)
            if clashes
              then put $ st { tuiMessage = Just "A book with this ISBN already exists -- edit it instead" }
              else do
                let -- Preserve the original JSON value of a custom field
                    -- whose rendered text was not changed in the form
                    origCustom = maybe Map.empty (^. custom) mOrig
                    keepValue (k, v) = case Map.lookup k origCustom of
                      Just old | valueToText old == v -> (k, old)
                      _ -> (k, String v)
                    book = Book
                      { _bookId = newId
                      , _isbn = if T.null (absIsbn abs') then Nothing else Just (absIsbn abs')
                      , _title = absTitle abs'
                      , _authors = parseCommaSeparated (absAuthors abs')
                      -- The form has no series fields; keep original values
                      , _series = mOrig >>= (^. series)
                      , _seriesIndex = mOrig >>= (^. seriesIndex)
                      , _publisher = if T.null (absPublisher abs') then Nothing else Just (absPublisher abs')
                      , _published = parsePublished (absPublished abs')
                      , _tags = parseCommaSeparated (absTags abs')
                      , _rating = parseRating (absRating abs')
                      , _comments = if T.null (absComments abs') then Nothing else Just (absComments abs')
                      , _location = if T.null (absLocation abs') then Nothing else Just (absLocation abs')
                      , _custom = Map.fromList $ map keepValue (absCustomFields abs')
                      , _added = maybe now (^. added) mOrig
                      , _modified = now
                      }
                result <- liftIO $ saveBook cfg book
                case result of
                  Left err ->
                    put $ st { tuiMessage = Just $ "Error: " <> T.pack (show err) }
                  Right () -> do
                    -- Reload books
                    (_, newBooks) <- liftIO $ reloadBooks cfg
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
                   (_, newBooks) <- liftIO $ reloadBooks cfg
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

-- | Parse the published field: accepts a full date ("2020-01-31", the
-- format the edit form displays for existing dates) or a bare year
parsePublished :: Text -> Maybe Day
parsePublished t =
  let s = T.strip t
  in parseTimeM True defaultTimeLocale "%Y-%m-%d" (T.unpack s) <|> parseYear s

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

-- | Handle events in command bar view
handleCommandBarEvent :: BrickEvent Name e -> TUIState -> EventM Name TUIState ()
handleCommandBarEvent ev st = do
  let appSt = tuiAppState st

  case tuiCommandBarState st of
    Nothing -> put $ st { tuiAppState = appSt & currentView .~ ViewList }
    Just cbs -> case ev of
      VtyEvent (V.EvKey V.KEsc []) ->
        put $ st { tuiAppState = appSt & currentView .~ ViewList
                 , tuiCommandBarState = Nothing
                 , tuiMessage = Nothing
                 }

      VtyEvent (V.EvKey V.KEnter []) ->
        executeCommand (parseCommand (cbsInput cbs)) st

      VtyEvent (V.EvKey (V.KChar '\t') []) ->
        put $ st { tuiCommandBarState = Just (completeNext cbs) }

      VtyEvent (V.EvKey V.KBS []) ->
        let newInput = T.dropEnd 1 (cbsInput cbs)
        in put $ st { tuiCommandBarState = Just $ cbs
                        { cbsInput = newInput
                        , cbsCompletionIndex = Nothing
                        , cbsCompletingCommand = False
                        }
                    }

      VtyEvent (V.EvKey (V.KChar c) []) ->
        let newInput = cbsInput cbs <> T.singleton c
        in put $ st { tuiCommandBarState = Just $ cbs
                        { cbsInput = newInput
                        , cbsCompletionIndex = Nothing
                        , cbsCompletingCommand = False
                        }
                    }

      _ -> pure ()

-- | Execute a parsed command
executeCommand :: Command -> TUIState -> EventM Name TUIState ()
executeCommand cmd st = do
  let appSt = tuiAppState st
  case cmd of
    CmdFilterTag t ->
      let newAppSt = appSt & activeFilter .~ Just (FilterTag t)
                           & currentView .~ ViewList
      in put $ st { tuiAppState = newAppSt & selectedIndex .~ resetIndex newAppSt
                  , tuiCommandBarState = Nothing
                  , tuiMessage = Just $ "Filter: tag = " <> t
                  }
    CmdFilterAuthor a ->
      let newAppSt = appSt & activeFilter .~ Just (FilterAuthor a)
                           & currentView .~ ViewList
      in put $ st { tuiAppState = newAppSt & selectedIndex .~ resetIndex newAppSt
                  , tuiCommandBarState = Nothing
                  , tuiMessage = Just $ "Filter: author = " <> a
                  }
    CmdGroup gf ->
      let newAppSt = appSt & groupMode .~ Just gf
                            & currentView .~ ViewList
      in put $ st { tuiAppState = newAppSt & selectedIndex .~ resetIndex newAppSt
                  , tuiCommandBarState = Nothing
                  , tuiMessage = Just $ "Grouped by " <> groupFieldName gf
                  }
    CmdGroupNone ->
      put $ st { tuiAppState = appSt & groupMode .~ Nothing
                                      & currentView .~ ViewList
                                      & selectedIndex .~ 0
               , tuiCommandBarState = Nothing
               , tuiMessage = Just "Grouping cleared"
               }
    CmdSort sf ->
      let newAppSt = appSt & sortField .~ sf
                           & currentView .~ ViewList
      in put $ st { tuiAppState = newAppSt & selectedIndex .~ resetIndex newAppSt
                  , tuiCommandBarState = Nothing
                  , tuiMessage = Just $ "Sorted by " <> sortFieldName sf
                  }
    CmdClear ->
      put $ st { tuiAppState = appSt & activeFilter .~ Nothing
                                      & groupMode .~ Nothing
                                      & currentView .~ ViewList
                                      & selectedIndex .~ 0
               , tuiCommandBarState = Nothing
               , tuiMessage = Just "Filters and grouping cleared"
               }
    CmdNeedsArg _cmd hint ->
      put $ st { tuiMessage = Just $ "Usage: " <> hint }
    CmdUnknown t ->
      put $ st { tuiAppState = appSt & currentView .~ ViewList
               , tuiCommandBarState = Nothing
               , tuiMessage = Just $ "Unknown command: " <> t
               }

groupFieldName :: GroupField -> Text
groupFieldName GroupByTag = "tag"
groupFieldName GroupByAuthor = "author"

sortFieldName :: SortField -> Text
sortFieldName SortByTitle = "title"
sortFieldName SortByAuthor = "author"
sortFieldName SortByDate = "date"

-- | Navigate up, skipping section headers in grouped mode
navigateUp :: TUIState -> AppState -> [Book] -> EventM Name TUIState ()
navigateUp st appSt visibleBks =
  case appSt ^. groupMode of
    Nothing ->
      put $ st { tuiAppState = appSt & selectedIndex %~ max 0 . subtract 1 }
    Just gf ->
      let items = buildGroupedList gf (appSt ^. sortField) (appSt ^. sortOrder) visibleBks
          newIdx = prevSelectableIndex items (appSt ^. selectedIndex)
      in put $ st { tuiAppState = appSt & selectedIndex .~ newIdx }

-- | Navigate down, skipping section headers in grouped mode
navigateDown :: TUIState -> AppState -> [Book] -> EventM Name TUIState ()
navigateDown st appSt visibleBks =
  case appSt ^. groupMode of
    Nothing ->
      put $ st { tuiAppState = appSt & selectedIndex %~ max 0 . min (length visibleBks - 1) . (+ 1) }
    Just gf ->
      let items = buildGroupedList gf (appSt ^. sortField) (appSt ^. sortOrder) visibleBks
          newIdx = nextSelectableIndex items (appSt ^. selectedIndex)
      in put $ st { tuiAppState = appSt & selectedIndex .~ newIdx }
