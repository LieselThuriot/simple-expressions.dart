# 2.0.0

This major release adopts the portable v1 evaluation rules. Review existing expressions and error handling when upgrading from 1.x, especially equality, comparisons, whitespace handling, and cache limits.

- Added mathematical operators: `int`, `num`, `abs`, `floor`, `ceil`, `sqrt`, `add`, `sub`, `mul`, `div`, `mod`, `min`, `max`, `round`, `pow`, and `clamp`.
- Added recursive, depth-first list expansion for `add`, `sub`, `mul`, `div`, `mod`, `min`, and `max`, including a single expression that evaluates to a list. Empty lists give `add` and `mul` the identities 0 and 1.
- Numeric operators require finite numbers or finite decimal/exponent strings and reject nonfinite results. Division and modulo by zero report `Division by zero`.
- Added rounding with precision 0 through 308 and exact runtime-number midpoint ties away from zero. Rounding works on native Dart and the JavaScript backend without overflowing a binary scaling intermediate.
- Aligned equality and comparisons with the portable v1 contract: blank strings are not numeric, collections do not coerce to scalars, and lists/maps compare structurally with cycle detection. Two strings compare in ordinal UTF-16 order; unsupported comparison operands return false.
- Standardized expression boundaries, token separators, numeric trimming, and `trim` on Unicode White_Space, excluding U+FEFF.
- Added `ExpressionEvaluationException` for evaluation failures and consistent `ExpressionParseException` reporting for parse failures. Active cyclic lists produce controlled numeric/text conversion errors.
- Corrected cache-limit behavior so values below 1 throw without changing cache state.

# 1.1.0

- Aligned `eq` with the reference implementations by supporting structural equality for lists, including nested lists and loose element comparison.
- Added shared conformance coverage for structural list equality.

# 1.0.1

- Corrected the public parsed-expression class name to `SimpleExpression` to match the TypeScript reference.
- This release replaces the retracted 1.0.0 release, which exposed the class as `Expression`.

# 1.0.0

- Initial stable release.
- Added expression parsing and evaluation for Dart and Flutter.
- Added model references, operators, caching, and conformance tests.
