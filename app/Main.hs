module Main (main) where

import Libri.CLI.Commands
import Libri.Storage.Yaml (loadConfig, initDataDir)
import Libri.TUI.App (runTUI)
import Libri.Types (defaultConfig)
import System.IO (hPutStrLn, stderr)

main :: IO ()
main = do
  -- Parse command-line options
  opts <- parseOptions

  -- Load configuration
  cfgResult <- loadConfig (optConfigPath opts)
  cfg <- case cfgResult of
    Left err -> do
      hPutStrLn stderr $ "Warning: Could not load config: " <> show err
      hPutStrLn stderr "Using default configuration"
      pure defaultConfig
    Right c -> pure c

  -- Initialize data directory
  initDataDir cfg

  -- Run the appropriate command
  case optCommand opts of
    CmdTUI -> runTUI cfg
    cmd -> runCommand cfg cmd
