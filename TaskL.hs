{-# LANGUAGE OverloadedStrings
           , TupleSections
           , TemplateHaskell
           , ScopedTypeVariables
           , GeneralizedNewtypeDeriving #-}
module TaskL where

import           Control.Applicative
import           Control.Arrow
import           Control.Monad
import           Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.ByteString.UTF8 as ByteString (fromString)
import           Data.Either
import           Data.Maybe
import           Data.Monoid
import           Data.String
import           Data.Set (Set)
import qualified Data.Set as Set
import           Data.Map (Map)
import qualified Data.Map as Map
import           Data.Tree (Tree(..), Forest)
import qualified Data.Tree as Tree
import           System.IO
import           System.Environment
import           System.Exit

import qualified Data.Attoparsec.ByteString.Char8 as Attoparsec
import           Data.FileEmbed
import           Data.Graph.Wrapper (Graph)
import           Data.Graph.Wrapper as Graph
import           Data.Yaml
import qualified Text.ShellEscape as Esc
import qualified Language.Bash as Bash

import           JSONTree


data Cmd = Cmd Program [Argument] deriving (Eq, Ord)
instance Show Cmd where
  show (Cmd program args) = unwords (p2s program : map a2s args)
   where p2s (ShHTTP b)   = ByteString.unpack b
         p2s (Path b)     = ByteString.unpack b
         a2s (Str b)      = ByteString.unpack b

data Program = ShHTTP ByteString | Path ByteString deriving (Eq, Ord, Show)
instance IsString Program where fromString = Path . ByteString.pack

data Argument = Str ByteString deriving (Eq, Ord, Show)
instance IsString Argument where fromString = Str . ByteString.pack


-- | Render a command section to a Bash command line.
command :: Cmd -> Bash.Statement ()
command (Cmd p args) = case p of ShHTTP url -> bash "curl_sh" (Str url:args)
                                 Path path  -> bash path args
 where bash a b = Bash.SimpleCommand (Bash.literal a) (arg <$> b)

arg :: Argument -> Bash.Expression ()
arg (Str b) = Bash.literal b

-- | Calculate a linear schedule from a graph if there are no cycles, or
--   return the cycles.
schedule :: (Eq t) => Graph t t -> Either [[t]] [t]
schedule g | a == []   = Right b
           | otherwise = Left a
 where (a, b) = partitionEithers
                (scc2either <$> Graph.stronglyConnectedComponents g)
       scc2either (Graph.CyclicSCC ts) = Left ts
       scc2either (Graph.AcyclicSCC t) = Right t

-- | Generate Bash function declaration for task schedule.
tasks :: [Cmd] -> Bash.Statement ()
tasks  = Bash.Function "tasks" . anno . and . (command <$>)
 where anno = Bash.Annotated ()
       and cmds = case cmds of [   ] -> Bash.SimpleCommand "msg" ["No tasks."]
                               [cmd] -> cmd
                               cmd:t -> Bash.Sequence (anno cmd) (anno (and t))

script :: [Cmd] -> ByteString
script list = header <> Bash.bytes (tasks list) <> "\n" <> footer


-- | A task name could be present multiple times in a document or collection
--   of documents (for example, the @_@ default task). The "leftmost"
--   (earliest) definition overrides later definitions.
merge :: (Ord t) => [(t, [t])] -> Map t (Set t)
merge  = (Set.fromList <$>) . Map.fromListWith const

-- | Convert from a 'Map' of adjacencies to a list of adjacencies.
adjacencies :: (Ord t) => Map t (Set t) -> [(t, [t])]
adjacencies  = Map.toAscList . (Set.toAscList <$>)

-- | Merge adjacency lists and produce a graph.
graph :: (Ord t) => Map t (Set t) -> Graph t t
graph  = Graph.fromListSimple . adjacencies


frame, header, footer :: ByteString
frame            = $(embedFile "frame.bash")
(header, footer) = (ByteString.unlines *** ByteString.unlines)
                 . second (drop 1 . dropWhile (/= "}"))
                 . span (/= "function tasks {")
                 $ ByteString.lines frame


data Definition = Definition Name [Cmd] [Name]

newtype Name = Name ByteString deriving (Eq, Ord, Show, IsString)

program :: Attoparsec.Parser Program
program  = (ShHTTP <$> url) <|> (Path <$> Attoparsec.takeByteString)

url :: Attoparsec.Parser ByteString
url  = (<>) <$> (Attoparsec.string "http://" <|> Attoparsec.string "https://")
            <*> Attoparsec.takeByteString

name :: Attoparsec.Parser Name
name  = (Name . ByteString.intercalate "." <$> labels) <* Attoparsec.endOfInput
 where labels = Attoparsec.sepBy1 label (Attoparsec.char '.')

call :: Attoparsec.Parser Name
call  = Attoparsec.string "//" *> name

label :: Attoparsec.Parser ByteString
label  = label' <|> ByteString.singleton <$> ld
 where ldu = Attoparsec.takeWhile1 (Attoparsec.inClass "a-zA-Z0-9_")
       ld  = Attoparsec.satisfy (Attoparsec.inClass "a-zA-Z0-9")
       label' = do b <- ByteString.cons <$> ld <*> ldu
                   if ByteString.last b == '_' then mzero else return b

task :: Tree ByteString -> Either String (Either Name Cmd)
task (Node s ts)  =  either Left (Right . (`Cmd` (Str . rootLabel <$> ts)))
                 <$> Attoparsec.parseOnly (Attoparsec.eitherP call program) s

-- | Parse a definition. Note that one may define @_@ (taken to be the default
--   if a module is loaded but no specific task is asked for) but that name is
--   not callable.
definition :: Tree ByteString -> Either (ByteString, String) Definition
definition (Node s ts) = either (Left . (s,)) Right $ do
  whoami              <- Attoparsec.parseOnly (main <|> name) s
  (names, commands)   <- partitionEithers <$> mapM task ts
  return $ Definition whoami commands names
 where
  main = Name <$> Attoparsec.string "_"


data Module = Module (Map Name (Set Cmd)) (Map Name (Set Name))
 deriving (Eq, Ord, Show)

-- | Compile any number of loaded, semi-structured text trees to a module. Any
--   trees that fail to parse are returned in a separate list, to be used for
--   warnings. (At a later stage, absent definitions can result in compiler
--   failure.)
compiledModule :: Forest ByteString -> (Module, [(ByteString, String)])
compiledModule trees = (mod, failed)
 where (failed, defined) = partitionEithers (definition <$> trees)
       (bodies, dependencies) = unzip [ ((name, body), (name, names))
                                      | Definition name body names <- defined ]
       leaves    = (,[]) <$> (Set.toList . missing . merge) dependencies
       missing m = Set.difference (Set.unions $ Map.elems m) (Map.keysSet m)
       mod       = Module (Set.fromList <$> Map.fromList bodies)
                          (merge (leaves ++ dependencies))

-- | Clip an adjacency list to include only those entries reachable from the
--   given key. If no key is given, then the key @_@ is used if it is
--   in the map; otherwise, the entire adjacency list is returned.
--
--   If a key is given and it is not in the map, then 'Nothing' is returned.
subMap :: Maybe Name -> Map Name (Set Name) -> Maybe (Map Name (Set Name))
subMap name m = maybe (get "_" <|> Just m) get name
 where get key = reachable <$ guard (Map.member key m)
        where keys      = Set.fromList $ Graph.reachableVertices (graph m) key
              reachable = Map.fromList
                          [ (k,v) | (k,v) <- Map.toList m, Set.member k keys ]


data MetaTask = Start Name | Done Name | Run Cmd deriving (Eq, Ord)
instance Show MetaTask where
  show (Start (Name b)) = "//" ++ ByteString.unpack b ++ " (start)"
  show (Done (Name b))  = "//" ++ ByteString.unpack b ++ " (completion)"
  show (Run cmd)        = show cmd

crush :: Module -> Map MetaTask (Set MetaTask)
crush (Module defs deps) = Map.fromListWith Set.union $
 [ (Run cmd, Set.singleton (Start n)) | (n, cmds)  <- Map.toList defs
                                      , cmd        <- Set.toList cmds ] ++
 [ (Done n, Set.map Run cmds)         | (n, cmds)  <- Map.toList defs ] ++
 [ (Start n, Set.map Done names)      | (n, names) <- Map.toList deps ] ++
 [ (Done n, Set.singleton (Start n))  | (n, _)     <- Map.toList deps ]

undefinedTasks :: Module -> [Name]
undefinedTasks (Module defs deps) = Set.toList $
  Map.keysSet deps `Set.difference` Map.keysSet defs

taskSchedule :: Module -> Either [Name] (Either [[MetaTask]] [MetaTask])
taskSchedule mod = case undefinedTasks mod of
  [ ] -> Right . schedule . graph . crush $ mod
  h:t -> Left (h:t)

unMeta :: MetaTask -> Cmd
unMeta (Start (Name b)) = Cmd "msg" ["-_-", Str b]
unMeta (Done (Name b))  = Cmd "msg" ["^_^", Str b]
unMeta (Run cmd)        = cmd

shell :: [MetaTask] -> ByteString
shell  = script . (unMeta <$>)


main :: IO ()
main = do
  arg <- (ByteString.pack <$>) . listToMaybe <$> getArgs
  Just (trees :: Forest ByteString) <- decode <$> ByteString.hGetContents stdin
  let (Module defs deps, failed) = compiledModule trees
  task <- case arg of
            Nothing -> return Nothing
            Just b  -> case Attoparsec.parseOnly name b of
                         Right name -> return (Just name)
                         Left _     -> msg "Invalid task name." >> exitFailure
  (failed /= []) `when` do msg "Some definitions were not loadable:"
                           mapM_ (msg . ByteString.pack . show) failed
  case subMap task deps of
    Nothing    -> msg "Failed to find requested task." >> exitFailure
    Just deps' -> tryCompile (Module defs deps')
 where
  unName (Name b) = b
  msg = ByteString.hPutStrLn stderr
  out = ByteString.hPutStrLn stdout
  tryCompile mod = case taskSchedule mod of
    Right (Right tasks) -> out (shell tasks)
    Right (Left cycles) -> do msg "Scheduling failure due to cycles:"
                              mapM_ (mapM_ msg . prettyPrintCycle) cycles
                              exitFailure
    Left names          -> do msg "Can not compile these undefined tasks:"
                              mapM_ (msg . unName) names
                              exitFailure

prettyPrintCycle :: [MetaTask] -> [ByteString]
prettyPrintCycle metas = withPrefixes False (meta <$> metas)
 where meta (Start (Name b)) = "//" <> b <> " (start)"
       meta (Done (Name b))  = "//" <> b <> " (done)"
       meta (Run cmd)        = ByteString.pack (show cmd)
       withPrefixes _     [     ] = [         ]
       withPrefixes False [  h  ] = ["╳ " <<> h]
       withPrefixes False (h:s:t) = ("╔ " <<> h) : withPrefixes True (s:t)
       withPrefixes True  (h:s:t) = ("║ " <<> h) : withPrefixes True (s:t)
       withPrefixes True  [  h  ] = ["╚ " <<> h]
       s <<> b = ByteString.fromString s <> b
