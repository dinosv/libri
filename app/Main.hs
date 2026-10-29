module Main (main) where

import Control.Monad (when)
import Data.Maybe (fromMaybe, isJust)
import Libri.CLI.Commands
import Libri.Storage.Yaml (loadConfig, initDataDir, defaultConfigPath, getDataDir)
import Libri.TUI.App (runTUI)
import System.Directory (makeAbsolute)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

main :: IO ()
main = do
  -- Parse command-line options
  opts <- parseOptions

  -- Load configuration. A config that is broken, or that was named
  -- with --config but does not exist, is fatal: falling back to the
  -- defaults would quietly open (and write to) a different library.
  let explicit = optConfigPath opts
  cfgResult <- loadConfig (isJust explicit) (fromMaybe defaultConfigPath explicit)
  cfg <- case cfgResult of
    Left err -> do
      hPutStrLn stderr $ "Error: could not load config: " <> show err
      exitFailure
    Right c -> pure c

  -- Initialize data directory, saying so when it is new: an empty
  -- library usually means libri is looking in the wrong place
  created <- initDataDir cfg
  when created $ do
    dir <- getDataDir cfg >>= makeAbsolute
    hPutStrLn stderr $ "Note: no library found; created a new empty one at " <> dir
    hPutStrLn stderr $ "      (set dataDir in " <> defaultConfigPath <> " to use an existing library)"

  -- Run the appropriate command
  case optCommand opts of
    CmdTUI -> runTUI cfg
    cmd -> runCommand cfg cmd
