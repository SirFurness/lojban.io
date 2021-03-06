{-# LANGUAGE OverloadedStrings #-}

-- | This module provides utilities for manipulating numbers in Lojban.
module Language.Lojban.Numbers
( numberToLojban
, lojbanToNumber
) where

import Text.Read (readMaybe)
import Control.Applicative ((<$>), (<*>))
import qualified Data.Text as T

-- | Converts a decimal digit character into the corresponding Lojban cmavo.
digitToLojban :: Char -> T.Text
digitToLojban '0' = "no"
digitToLojban '1' = "pa"
digitToLojban '2' = "re"
digitToLojban '3' = "ci"
digitToLojban '4' = "vo"
digitToLojban '5' = "mu"
digitToLojban '6' = "xa"
digitToLojban '7' = "ze"
digitToLojban '8' = "bi"
digitToLojban '9' = "so"

-- | Converts Lojban cmavo into the corresponding decimal digit character.
lojbanToDigit :: T.Text -> Maybe Char
lojbanToDigit "no" = Just '0'
lojbanToDigit "pa" = Just '1'
lojbanToDigit "re" = Just '2'
lojbanToDigit "ci" = Just '3'
lojbanToDigit "vo" = Just '4'
lojbanToDigit "mu" = Just '5'
lojbanToDigit "xa" = Just '6'
lojbanToDigit "ze" = Just '7'
lojbanToDigit "bi" = Just '8'
lojbanToDigit "so" = Just '9'
lojbanToDigit _ = Nothing

-- | Converts an integer into Lojban text.
numberToLojban :: Integer -> T.Text
numberToLojban = T.concat . map digitToLojban . show

-- | Converts Lojban text into an integer.
--
-- Supports the separator "ki'o", e.g. "pa ki'o ci" (1003).
lojbanToNumber :: T.Text -> Maybe Integer
lojbanToNumber t =
    case sequence subnumbers of
        Just subnumbers' -> readMaybe $ T.unpack $ T.concat subnumbers'
        Nothing -> Nothing
    where subnumbers = map (fmap $ T.justifyRight 3 '0') $ map simpleLojbanToNumberText $ T.splitOn "ki'o" t

simpleLojbanToNumber :: T.Text -> Maybe Integer
simpleLojbanToNumber t =
    case x of
        Just x' -> readMaybe $ T.unpack x'
        Nothing -> Nothing
    where x = simpleLojbanToNumberText t

simpleLojbanToNumberText :: T.Text -> Maybe T.Text
simpleLojbanToNumberText "" = Just ""
simpleLojbanToNumberText text =
    T.cons <$> lojbanToDigit prefix <*> simpleLojbanToNumberText suffix
    where (prefix, suffix) = T.splitAt 2 text
