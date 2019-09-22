{-# LANGUAGE OverloadedStrings, TupleSections #-}

module BrilTypes where

import Data.Aeson
import Data.Char (toLower)
import Data.Foldable (toList)
import Data.List (intercalate)
import Data.Maybe (fromJust, fromMaybe, isJust)
import Lens

import qualified Data.Map.Lazy as Map
import qualified Data.Sequence as Seq

newtype Program = Program { functions :: Map.Map String Function }
    deriving Show

instance FromJSON Program where
    parseJSON = withObject "Program" $ \v ->
        Program . Map.fromList . map (\f -> (name f, f)) <$>
        v .: "functions"

data Function = Function {
    name :: String,
    body :: Seq.Seq Instruction,
    labels :: Map.Map String Int
}   deriving Show

instance FromJSON Function where
    parseJSON = withObject "Function" $ \v -> do
        n <- v .: "name"
        insts <- v .: "instrs"
        let labelMap =
                Map.fromListWithKey (\l -> error ("repeated label: " ++ l)) $
                map (over _fst (fromJust . label)) $
                filter (isJust . label . fst) $
                zip (toList insts) [0 ..]
        return $ Function n insts labelMap

data Instruction = Instruction {
    breakpoint :: Breakpoint,
    label :: Maybe String,
    op :: Maybe String,
    dest :: Maybe String,
    typ :: Maybe Type,
    value :: Maybe BrilValue,
    args :: [String]
}

instance Show Instruction where
    show = show . classify

data ClassifiedInst =
    Label String
  | Const String Type BrilValue
  | ValueOp String Type String [String]
  | EffectOp String [String]

instance Show ClassifiedInst where
    show (Label l) = l ++ ":"
    show (Const d t v) =
        d ++ ": " ++ show t ++ " = const " ++ show v ++ ";"
    show (ValueOp d t o as) =
        d ++ ": " ++ show t ++ " = " ++ intercalate " " (o:as) ++ ";"
    show (EffectOp o as) = 
        intercalate " " (o:as) ++ ";"

classify :: Instruction -> ClassifiedInst
classify (Instruction b l o d t v a) =
    if isJust l then
        Label $ fromJust l
    else if o == Just "const" then
        Const (fromJust d) (fromJust t) (fromJust v)
    else if isJust d then
        ValueOp (fromJust d) (fromJust t) (fromJust o) a
    else
        EffectOp (fromJust o) a

instance FromJSON Instruction where
    parseJSON = withObject "Instruction" $ \v -> Instruction No
        <$> v .:? "label"
        <*> v .:? "op"
        <*> v .:? "dest"
        <*> v .:? "type"
        <*> v .:? "value"
        <*> (fromMaybe [] <$> v .:? "args")

data BrilValue = BrilInt Int | BrilBool Bool

instance Show BrilValue where
    show (BrilInt x) = show x
    show (BrilBool x) = map toLower $ show x

instance FromJSON BrilValue where
    parseJSON v@(Number _) = BrilInt <$> parseJSON v
    parseJSON v@(Bool _) = BrilBool <$> parseJSON v
    parseJSON _ = fail "Value"

data Type = IntType | BoolType

instance Show Type where
    show IntType = "int"
    show BoolType = "bool"

instance FromJSON Type where
    parseJSON = withText "Type" $ \s -> case s of
        "int" -> return IntType
        "bool" -> return BoolType
        _ -> fail "Type"

data DebugState = DebugState {
    program :: Map.Map String Function,
    callStack :: [FunctionState]
}

_callStack :: Lens' DebugState [FunctionState]
_callStack = lens callStack $ \d c -> d { callStack = c }

data FunctionState = FunctionState {
    functionName :: String,
    position :: Int,
    variables :: Map.Map String BrilValue
}

_variables :: Lens' FunctionState (Map.Map String BrilValue)
_variables = lens variables $ \f v -> f { variables = v }

_position :: Lens' FunctionState Int
_position = lens position $ \f p -> f { position = p }

data Breakpoint = No | Yes
    deriving (Eq, Show)

data Command