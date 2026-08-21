# 1.2.0

- Added mathematical operators: `int`, `num`, `abs`, `floor`, `ceil`, `sqrt`, `add`, `sub`, `mul`, `div`, `mod`, `min`, `max`, `round`, `pow`, and `clamp`.
- Added one-level list expansion for `add`, `mul`, `min`, and `max`, including support for a single list argument.
- Added validation for division by zero, modulo by zero, and invalid round precision.
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
