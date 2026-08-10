# simple_expressions

![simple-expressions logo](https://raw.githubusercontent.com/LieselThuriot/simple-expressions.dart/refs/heads/master/simple-expressions.png)

[![pub package](https://img.shields.io/pub/v/simple_expressions.svg)](https://pub.dev/packages/simple_expressions)
[![license](https://img.shields.io/pub/l/simple_expressions.svg)](https://pub.dev/packages/simple_expressions/license)

A Dart package for parsing and evaluating expressions against JSON-like model values.

This package is licensed under the ISC License.

## Install

```bash
dart pub add simple_expressions
```

## Usage

```dart
import 'package:simple_expressions/simple_expressions.dart';

final model = {
  'user': {'name': 'Ada'},
  'score': 8,
};

executeExpression(model, 'and(eq(#user.name, "Ada"), gt(#score, 5))');
// true

final expression = parseExpression('concat("Hello, ", #user.name)');
expression.evaluateValue(model);
// "Hello, Ada"
```

`executeExpression` and `SimpleExpression.evaluate` return the expression's truthiness. `parseExpression` returns a reusable `SimpleExpression`; call `evaluateValue` when you need the raw result. Missing and null values appear as `null` at the public API boundary.

## Example

Run the package example:

```bash
dart run example/simple_expressions_example.dart
```

The sample is included in the published package's Example tab.

## Syntax

Constants support case-insensitive Booleans, signed, decimal, and exponent-form numeric literals, single-, double-, or backtick-quoted strings, and recursive list literals in square brackets. References begin with `#`. For a dotted reference, the evaluator first checks for an exact dotted key and then traverses nested map values. References cannot contain empty segments or the reserved segments `__proto__`, `constructor`, and `prototype`; those restrictions are retained for compatibility with the TypeScript reference.

Operators are case-insensitive:

`not`, `empty`, `len`, `lower`, `upper`, `trim`, `defined`, `eq`, `contains`, `startswith`, `endswith`, `in`, `gt`, `lt`, `match`, variadic `and`/`or`/`concat`, and lazy `if`.

`in` requires a list and uses the same loose equality as `eq`. `trim` preserves null and missing values; other falsey values become empty strings before trimming. `defined` is false only for null and missing values. Lists may contain nested lists, model references, and operator expressions.

The evaluator uses JavaScript-style truthiness, loose equality, and value conversion where those rules can be represented by Dart values. Numeric values are evaluated as Dart `double` values. `match` uses Dart `RegExp`, so patterns that rely on JavaScript-specific regex syntax are not portable.

## Differences from the TypeScript reference

This port follows the [TypeScript reference](https://github.com/LieselThuriot/simple-expressions) for grammar, operators, evaluation order, and selected safety rules. It does not reproduce every JavaScript coercion quirk. Cross-language compatibility is tested separately in [simple-expressions-conformance](https://github.com/LieselThuriot/simple-expressions-conformance).

| Behaviour | TypeScript | This port |
| --- | --- | --- |
| String to number | `Number("")` is `0`, `"Infinity"` is a keyword | A string converts only if it parses as a number; `""` and `"   "` are `NaN` |
| `parseExpression` | Returns `(model) => value` | Returns a `SimpleExpression`; call `evaluateValue(model)` for the raw value or `evaluate(model)` for truthiness |
| Missing vs null | Distinguishable in results (`undefined` vs `null`) | Both surface as `null` from `evaluateValue`, and are equal under `eq` |
| Model values | Any JavaScript object | String keys in Dart `Map` values resolve; list indexes are not traversed, and an unsupported runtime type is treated as an empty object |

Numbers use the same formatting rule as the TypeScript reference: the shortest round-trip decimal, plain notation for magnitudes in `[1e-6, 1e21)`, and lowercase exponent notation outside that range.

## Model Access

Models are read when an expression asks for a value. Nothing is copied or converted up front, so an expression only visits the parts of a model that it references.

Model values can be Dart maps and lists, along with strings, numbers, booleans, and null. Map keys are matched as strings. A non-map model root resolves every reference to a missing value.

Keep these details in mind:

- Model values are read live at evaluation time. Mutations made between evaluations are visible to the next evaluation.
- List indexes and list properties are not traversed through references.
- A value with an unsupported Dart runtime type is treated as an empty object.
- Missing references surface as `null` from `evaluateValue`. Internally, missing and explicit null remain distinct, but `eq`, `defined`, and `empty` treat them the same.

## Caching

Parsed expressions and `SimpleExpression` instances are cached by default. Both caches use a FIFO limit of 1,000 entries. Use `SimpleExpressions.setCacheLimit`, `clear`, `disableCaches`, and `enableCaches` to control them. Disabling caches also clears existing entries.

## Security

Expressions and regex patterns are trusted input. Regex evaluation can be vulnerable to catastrophic backtracking. Do not use untrusted expressions or patterns as an authorization boundary.

## Development

```bash
dart pub get
dart format .
dart analyze
dart test
```
