{-# LANGUAGE MultiParamTypeClasses
           , OverloadedStrings
  #-}

module System.TaskL.Op.Parser where

import Data.Tree

import Data.Number.Natural
import Text.ParserCombinators.UU hiding (Parser)

import System.TaskL.Op
import System.TaskL.Task
import System.TaskL.IndexForest


type Parser t                =  P (Str Op Natural) t


pCode                       ::  OpCode -> Parser Op
pCode code                   =  pSym (test, s, auto)
 where
  test (Op (code', _))       =  code == code'
  s                         ::  String
  s                          =  show code ++ ", _"
  auto                       =  Op (code, (Node (Index [], Package "" [])[]))


instance IsLocationUpdatedBy Natural Op where
  advance p _                =  p + 1

