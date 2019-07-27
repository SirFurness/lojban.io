module Courses.Util.ExerciseUtils
( simplifyCanonicalAnswer
) where

import Core
import Courses.Util.Vocabulary
import Language.Lojban.Core
import Language.Lojban.Refinement (simplifyTerminatorsInSentence)

-- * Terminator ellisis
-- | Decorates an exercise so that 'simplifyTerminatorsInSentence' is applied to its canonical answer.
simplifyCanonicalAnswer :: Exercise -> Exercise
simplifyCanonicalAnswer (TypingExercise title sentences validate canonicalAnswer) = TypingExercise title sentences validate (simplifyTerminatorsInSentence canonicalAnswer)
simplifyCanonicalAnswer x = x