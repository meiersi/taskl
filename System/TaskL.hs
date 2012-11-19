{-# LANGUAGE OverloadedStrings
           , TupleSections
           , TemplateHaskell
           , ScopedTypeVariables
           , GeneralizedNewtypeDeriving #-}
module System.TaskL where

import           Control.Applicative
import           Control.Arrow
import           Control.Monad
import           Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as ByteString
import           Data.Either
import           Data.Monoid
import           Data.Set (Set)
import qualified Data.Set as Set
import           Data.Map (Map)
import qualified Data.Map as Map
import           Data.Tree (Tree(..), Forest)
import qualified Data.Tree as Tree

import qualified Data.Attoparsec.ByteString.Char8 as Attoparsec
import           Data.FileEmbed
import           Data.Graph.Wrapper (Graph)
import qualified Data.Graph.Wrapper as Graph
import qualified Language.Bash as Bash


data Task = Task Call [ByteString] deriving (Eq, Ord, Show)

data Call = Cmd Cmd | Abstract ByteString deriving (Eq, Ord, Show)

data Cmd = ShHTTP ByteString | Path ByteString deriving (Eq, Ord, Show)


 ----------------- Parsing (input in raw and semi-raw forms) ------------------

tasks :: Tree [ByteString] -> Either String (Tree Task)
tasks (Node argv subs) = Node <$> task argv <*> mapM tasks subs

task :: [ByteString] -> Either String Task
task [   ] = Left "Empty argument vector."
task (h:t) = Task <$> Attoparsec.parseOnly call h <*> Right t

call :: Attoparsec.Parser Call
call  = (Abstract <$> name) <|> (Cmd <$> cmd)

cmd :: Attoparsec.Parser Cmd
cmd  = (ShHTTP <$> url) <|> (Path <$> Attoparsec.takeByteString)

url :: Attoparsec.Parser ByteString
url  = (<>) <$> (Attoparsec.string "http://" <|> Attoparsec.string "https://")
            <*> Attoparsec.takeByteString

name :: Attoparsec.Parser ByteString
name  = (<>) <$> Attoparsec.string "//"
             <*> (ByteString.intercalate "." <$> labels)
             <*  Attoparsec.endOfInput
 where labels = Attoparsec.sepBy1 label (Attoparsec.char '.')

label :: Attoparsec.Parser ByteString
label  = label' <|> ByteString.singleton <$> ld
 where ldu = Attoparsec.takeWhile1 (Attoparsec.inClass "a-zA-Z0-9_")
       ld  = Attoparsec.satisfy (Attoparsec.inClass "a-zA-Z0-9")
       label' = do b <- ByteString.cons <$> ld <*> ldu
                   if ByteString.last b == '_' then mzero else return b


 ------------ Graph utilities (works with multiple representations) -----------

-- | Provide a traversal of the graph that visits each node once if there are
--   no cycles or return the cycles.
schedule :: (Eq t) => Graph t t -> Either [[t]] [t]
schedule g = if cycles == [] then Right traversal else Left cycles
 where (cycles, traversal) = partitionEithers (scc2either <$> sccs)
       sccs = Graph.stronglyConnectedComponents g
       scc2either (Graph.CyclicSCC ts) = Left ts
       scc2either (Graph.AcyclicSCC t) = Right t

-- | Convert a forest into an adjacency list, backed by a 'Map'.
forestMap :: (Ord t) => Forest t -> Map t (Set t)
forestMap  = asMap . concatMap adjacencies

-- | Transform a tree to an adjacency list representation of its edges.
--   Duplicate edges are retained.
adjacencies :: Tree t -> [(t, [t])]
adjacencies (Node t [ ]) = (t, []) : []
adjacencies (Node t sub) = (t, Tree.rootLabel <$> sub)
                         : concatMap adjacencies sub

-- | Merge an adjacency list represented as tuples to a representation backed
--   by maps of sets, eliminating duplicate edges.
asMap :: (Ord t) => [(t, [t])] -> Map t (Set t)
asMap  = (Set.fromList <$>) . Map.fromListWith (++)

-- | Convert from a 'Map' representation of adjacency lists to a list backed
--   representation.
unMap :: (Ord t) => Map t (Set t) -> [(t, [t])]
unMap  = Map.toAscList . (Set.toAscList <$>)

-- | Merge adjacency lists and produce a graph.
graph :: (Ord t) => Map t (Set t) -> Graph t t
graph  = Graph.fromListSimple . unMap

-- | Clip an adjacency list to include only those entries reachable from the
--   given key. If the key given is not in the map, then 'Nothing' is returned.
cull :: (Ord t) => t -> Map t (Set t) -> Maybe (Map t (Set t))
cull key m = reachable <$ guard (Map.member key m)
 where keys      = Set.fromList $ Graph.reachableVertices (graph m) key
       reachable = Map.fromList [ (k,v) | (k,v) <- Map.toList m
                                        , Set.member k keys     ]


 ----------------------------- Shell generation -------------------------------

-- | Embed commands in the template script.
script :: [(Cmd, [ByteString])] -> ByteString
script list = header <> Bash.bytes (functionTasks list) <> "\n" <> footer

-- | Render a command to abstract Bash.
compile :: (Cmd, [ByteString]) -> Bash.Statement ()
compile (cmd, args) = case cmd of ShHTTP url -> bash curlSh (url:args)
                                  Path path  -> bash path args
 where bash a b = Bash.SimpleCommand (Bash.literal a) (Bash.literal <$> b)
       curlSh   = "curl_sh"

-- | Translate a task to a concrete shell command. Abstract tasks become a
--   message announcing their completion.
command :: Task -> (Cmd, [ByteString])
command (Task (Cmd cmd)    args) = (cmd, args)
command (Task (Abstract name) _) = (Path "msg", ["-_-", name])

-- | Generate Bash function, called @tasks@, with the commands in sequence.
functionTasks :: [(Cmd, [ByteString])] -> Bash.Statement ()
functionTasks  = Bash.Function "tasks" . anno . and . (compile <$>)
 where anno = Bash.Annotated ()
       and cmds = case cmds of [   ] -> Bash.SimpleCommand "msg" ["No tasks."]
                               [cmd] -> cmd
                               cmd:t -> Bash.Sequence (anno cmd) (anno (and t))

frame, header, footer :: ByteString
frame            = $(embedFile "frame.bash")
(header, footer) = (ByteString.unlines *** ByteString.unlines)
                 . second (drop 1 . dropWhile (/= "}"))
                 . span (/= "function tasks {")
                 $ ByteString.lines frame

