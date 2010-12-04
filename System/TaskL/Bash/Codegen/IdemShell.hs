{-# LANGUAGE OverloadedStrings
  #-}


module System.TaskL.Bash.Codegen.IdemShell where


import Data.List (sort, nub)

import Data.ByteString
import qualified Text.ShellEscape as Esc

import Data.ByteString.EncDec
import System.TaskL.IdemShell
import System.TaskL.IdemShell.Path
import System.TaskL.Bash.Program (cmd)
import qualified System.TaskL.Bash.Program as Program
import System.TaskL.Bash.Codegen.Utils


{-| Class of objects that may be translated to Bash programs. Both 'Command'
    and 'Test' can have code generated from them.
 -}
class CodeGen t where
  codeGen                   ::  t -> Program.Term

instance CodeGen Command where
  codeGen command            =  case command of
    CHOWN p o               ->  undefined
    CHMOD p m               ->  undefined
    RM p                    ->  undefined
    CP p' p                 ->  undefined
    LNs p' p                ->  undefined
    TOUCH p                 ->  undefined
    MKDIR p                 ->  undefined
    USERADD u attrs         ->  undefined
    USERDEL u               ->  undefined
    GROUPADD g attrs        ->  undefined
    GROUPDEL g              ->  undefined
    GPASSWDa g users        ->  undefined
    GPASSWDd g users        ->  undefined

instance CodeGen Test where
  codeGen test               =  case collapse test of
    LSo p o                 ->  undefined
    LSm p m                 ->  undefined
    DASHe p                 ->  testFS "-e" p
    DASH_ node p            ->  testFS (nodeTest node) p
    DIFFq p' p              ->  cmd ["diff", "-q", escEnc p, escEnc p']
    LSl p' p                ->  readlinkEq p p'
    GETENT ent              ->  getent ent
    GROUPS u g              ->  (pipeline . fmap cmd)
                                 [["groups", "--", escEnc u]
                                 ,["xargs", "printf", esc "%s\\n"]
                                 ,["sed", esc "1,2 d"]
                                 ,["fgrep", "--line-regexp", "--", escEnc g]]
    Not t                   ->  Program.Bang (codeGen t)
    And t t'                ->  codeGen t `Program.And` codeGen t'
    Or t t'                 ->  codeGen t `Program.Or` codeGen t'
    TRUE                    ->  cmd ["true"]
    FALSE                   ->  cmd ["false"]
   where
    readlinkEq p p'          =  Program.Sequence
      (Program.VarAssign "link_" (escEnc p))
      (cmd ["[", "`readlink -- \"$link_\"`", "=", escEnc p', "]"])


{-| Remove redundant negations.
 -}
collapse                    ::  Test -> Test
collapse (Not (Not test))    =  collapse test
collapse test                =  test

