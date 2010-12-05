{-# LANGUAGE OverloadedStrings
  #-}


module System.TaskL.Bash.Codegen.IdemShell where

import Prelude hiding (concat)
import Data.List (sort, nub)

import Data.ByteString hiding (map)
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
    DASHe p                 ->  undefined
    DASH_ node p            ->  undefined
    DIFFq p' p              ->  undefined
    LSl p' p                ->  undefined
    GETENTu u               ->  undefined
    GETENTg g               ->  undefined
    GROUPS u g              ->  undefined
    Not t                   ->  undefined
    And t t'                ->  undefined
    Or t t'                 ->  undefined
    TRUE                    ->  undefined
    FALSE                   ->  undefined


{-| Remove redundant negations.
 -}
collapse                    ::  Test -> Test
collapse (Not (Not test))    =  collapse test
collapse test                =  test


fullModeRE                  ::  Mode -> ByteString
fullModeRE (Mode ur uw ux us gr gw gx gs or ow ox ot) =
  (concat . map (flippedModeRE ur uw ux us gr gw gx gs or ow ox ot))
    [Idx0,Idx1,Idx2,Idx3,Idx4,Idx5,Idx6,Idx7,Idx8]
 where
  flippedModeRE ur  uw  ux  us  gr  gw  gx  gs  or  ow  ox  ot  idx =
         modeRE idx ur  uw  ux  us  gr  gw  gx  gs  or  ow  ox  ot


modeRE :: ModeIdx -> TriState -> TriState -> TriState -> TriState
                  -> TriState -> TriState -> TriState -> TriState
                  -> TriState -> TriState -> TriState -> TriState -> ByteString
modeRE    Idx0    On  _   _   _    _   _   _   _    _   _   _   _   =  "r"
modeRE    Idx0    Off _   _   _    _   _   _   _    _   _   _   _   =  "-"
modeRE    Idx0    _   _   _   _    _   _   _   _    _   _   _   _   =  "."
modeRE    Idx1    _   On  _   _    _   _   _   _    _   _   _   _   =  "w"
modeRE    Idx1    _   Off _   _    _   _   _   _    _   _   _   _   =  "-"
modeRE    Idx1    _   _   _   _    _   _   _   _    _   _   _   _   =  "."
modeRE    Idx2    _   _   On  On   _   _   _   _    _   _   _   _   =  "s"
modeRE    Idx2    _   _   On  Off  _   _   _   _    _   _   _   _   =  "x"
modeRE    Idx2    _   _   On  _    _   _   _   _    _   _   _   _   =  "[sx]"
modeRE    Idx2    _   _   Off On   _   _   _   _    _   _   _   _   =  "S"
modeRE    Idx2    _   _   Off Off  _   _   _   _    _   _   _   _   =  "-"
modeRE    Idx2    _   _   Off _    _   _   _   _    _   _   _   _   =  "[sS]"
modeRE    Idx2    _   _   _   _    _   _   _   _    _   _   _   _   =  "."
modeRE    Idx3    _   _   _   _    On  _   _   _    _   _   _   _   =  "r"
modeRE    Idx3    _   _   _   _    Off _   _   _    _   _   _   _   =  "-"
modeRE    Idx3    _   _   _   _    _   _   _   _    _   _   _   _   =  "."
modeRE    Idx4    _   _   _   _    _   On  _   _    _   _   _   _   =  "w"
modeRE    Idx4    _   _   _   _    _   Off _   _    _   _   _   _   =  "-"
modeRE    Idx4    _   _   _   _    _   _   _   _    _   _   _   _   =  "."
modeRE    Idx5    _   _   _   _    _   _   On  On   _   _   _   _   =  "s"
modeRE    Idx5    _   _   _   _    _   _   On  Off  _   _   _   _   =  "x"
modeRE    Idx5    _   _   _   _    _   _   On  _    _   _   _   _   =  "[sx]"
modeRE    Idx5    _   _   _   _    _   _   Off On   _   _   _   _   =  "S"
modeRE    Idx5    _   _   _   _    _   _   Off Off  _   _   _   _   =  "-"
modeRE    Idx5    _   _   _   _    _   _   Off _    _   _   _   _   =  "[sS]"
modeRE    Idx5    _   _   _   _    _   _   _   _    _   _   _   _   =  "."
modeRE    Idx6    _   _   _   _    _   _   _   _    On  _   _   _   =  "r"
modeRE    Idx6    _   _   _   _    _   _   _   _    Off _   _   _   =  "-"
modeRE    Idx6    _   _   _   _    _   _   _   _    _   _   _   _   =  "."
modeRE    Idx7    _   _   _   _    _   _   _   _    _   On  _   _   =  "w"
modeRE    Idx7    _   _   _   _    _   _   _   _    _   Off _   _   =  "-"
modeRE    Idx7    _   _   _   _    _   _   _   _    _   _   _   _   =  "."
modeRE    Idx8    _   _   _   _    _   _   _   _    _   _   On  On  =  "t"
modeRE    Idx8    _   _   _   _    _   _   _   _    _   _   On  Off =  "x"
modeRE    Idx8    _   _   _   _    _   _   _   _    _   _   On  _   =  "[tx]"
modeRE    Idx8    _   _   _   _    _   _   _   _    _   _   Off On  =  "T"
modeRE    Idx8    _   _   _   _    _   _   _   _    _   _   Off Off =  "-"
modeRE    Idx8    _   _   _   _    _   _   _   _    _   _   Off _   =  "[tT]"
modeRE    Idx8    _   _   _   _    _   _   _   _    _   _   _   _   =  "."


data ModeIdx = Idx0 | Idx1 | Idx2 | Idx3 | Idx4 | Idx5 | Idx6 | Idx7 | Idx8


