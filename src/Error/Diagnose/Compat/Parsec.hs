{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE FlexibleContexts #-}

{-# OPTIONS -Wno-name-shadowing #-}

module Error.Diagnose.Compat.Parsec
( diagnosticFromParseError
, errorDiagnosticFromParseError
, warningDiagnosticFromParseError
, module Error.Diagnose.Compat.Hints
) where

import Data.Bifunctor (second)
import Data.Function ((&))
import Data.Maybe (fromMaybe)
import Data.List (intercalate)
import Data.String (IsString(..))
import Data.Void (Void)

import Error.Diagnose
import Error.Diagnose.Compat.Hints (HasHints(..))

import qualified Text.Parsec.Error as PE
import qualified Text.Parsec.Pos as PP

-- | Generates a diagnostic from a 'PE.ParseError'.
diagnosticFromParseError
  :: forall msg. (IsString msg, HasHints Void msg)
  => (PE.ParseError -> Bool)         -- ^ Determine whether the diagnostic is an error or a warning
  -> msg                             -- ^ The main error of the diagnostic
  -> Maybe [msg]                     -- ^ Default hints
  -> PE.ParseError                   -- ^ The 'PE.ParseError' to transform into a 'Diagnostic'
  -> Diagnostic msg
diagnosticFromParseError isError msg (fromMaybe [] -> defaultHints) error =
  let pos     = fromSourcePos $ PE.errorPos error
      markers = toMarkers pos $ PE.errorMessages error
      report = (msg & if isError error then err else warn) markers (defaultHints <> hints (undefined :: Void))
  in addReport def report
  where
    fromSourcePos :: PP.SourcePos -> Position
    fromSourcePos pos =
      let start = both fromIntegral (PP.sourceLine pos, PP.sourceColumn pos)
          end   = second (+ 1) start
      in Position start end (PP.sourceName pos)

    toMarkers :: Position -> [PE.Message] -> [(Position, Marker msg)]
    toMarkers source []   = [ (source, This $ fromString "<<unknown error>>") ]
    toMarkers source msgs =
      let putTogether []                        = ([], [], [], [])
          putTogether (PE.SysUnExpect thing:ms) = let (a, b, c, d) = putTogether ms in (thing:a, b, c, d)
          putTogether (PE.UnExpect thing:ms)    = let (a, b, c, d) = putTogether ms in (a, thing:b, c, d)
          putTogether (PE.Expect thing:ms)      = let (a, b, c, d) = putTogether ms in (a, b, thing:c, d)
          putTogether (PE.Message thing:ms)     = let (a, b, c, d) = putTogether ms in (a, b, c, thing:d)

          (sysUnexpectedList, unexpectedList, expectedList, messages) = putTogether msgs
      in [ (source, marker) | unexpected <- if null unexpectedList then sysUnexpectedList else unexpectedList
                            , let marker = This $ fromString $ "unexpected " <> unexpected ]
      <> [ (source, marker) | msg <- messages
                            , let marker = This $ fromString msg ]
      <> [ (source, Where $ fromString $ "expected any of " <> intercalate ", " expectedList) ]

-- | Generates an error diagnostic from a 'PE.ParseError'.
errorDiagnosticFromParseError
  :: forall msg. (IsString msg, HasHints Void msg)
  => msg                  -- ^ The main error message of the diagnostic
  -> Maybe [msg]          -- ^ Default hints
  -> PE.ParseError        -- ^ The 'PE.ParseError' to convert
  -> Diagnostic msg
errorDiagnosticFromParseError = diagnosticFromParseError (const True)

-- | Generates a warning diagnostic from a 'PE.ParseError'.
warningDiagnosticFromParseError
  :: forall msg. (IsString msg, HasHints Void msg)
  => msg                  -- ^ The main error message of the diagnostic
  -> Maybe [msg]          -- ^ Default hints
  -> PE.ParseError        -- ^ The 'PE.ParseError' to convert
  -> Diagnostic msg
warningDiagnosticFromParseError = diagnosticFromParseError (const False)



------------------------------------
------------ INTERNAL --------------
------------------------------------

-- | Applies a computation to both element of a tuple.
--
--   > both f = bimap @(,) f f
both :: (a -> b) -> (a, a) -> (b, b)
both f ~(x, y) = (f x, f y)

