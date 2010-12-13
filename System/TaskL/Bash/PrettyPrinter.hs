{-| Pretty printer for Bash. Not very pretty right now.
 -}

module System.TaskL.Bash.PrettyPrinter where

import Data.Binary.Builder
import Data.ByteString

import System.TaskL.Bash.Program



prettyprint term = case term of
  SimpleCommand [] -> prettyprint Empty
  Empty ->
  Bang t ->
  And t t' ->
  Or t t' ->
  Pipe t t' ->
  Sequence t t' ->
  Background t t' ->
  Group t ->
  Subshell t ->
  IfThen t t' ->
  IfThenElse t t' t'' ->
  ForDoDone var vals t ->
  VarAssign var val ->
  DictDecl var pairs ->
  DictUpdate var key val ->
  DictAssign var pairs ->


{- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 

  Line break algorithm for simple commands and arguments of for loops:

    IF the width of the current line with the given word added is greater
       than 79 columns
    THEN
      IF moving the word to the following line causes the line to be shorter
      THEN
        do it
      ELSE
        add the current word to the current line
      DONE
    ELSE
      add the current word to the current line
    DONE

 - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -}

