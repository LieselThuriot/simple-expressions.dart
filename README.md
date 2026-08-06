# simple_expressions

A small, dependency-free Dart package for parsing and evaluating simple expressions against JSON-like model values.

This package is licensed under the ISC License.

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

`executeExpression` and `Expression.evaluate` return expression truthiness. `parseExpression` returns a reusable `Expression` whose `evaluateValue` method preserves the expression result's type. Expression models are JSON-like values: maps, lists, strings, numbers, booleans, and null.

## Expression Syntax

Constants include case-insensitive `true` and `false`, signed/decimal/exponent numeric literals, strings quoted with single quotes, double quotes, or backticks, and recursive lists in square brackets.

Model references start with `#`. Nested values use dots, such as `#user.name`. An exact dotted map key takes precedence over nested traversal. References only resolve map keys; list indexes and list properties are not traversed. The segments `__proto__`, `constructor`, and `prototype` are rejected.

Operators are case-insensitive: `not`, `eq`, `or`, `and`, `contains`, `startswith`, `endswith`, `in`, `gt`, `lt`, `empty`, `len`, `lower`, `upper`, `trim`, `defined`, `concat`, `match`, and `if`.

Parsed expressions and `Expression` instances are cached by default with a FIFO limit of 1,000 entries. Use `SimpleExpressions.setCacheLimit`, `clear`, `disableCaches`, and `enableCaches` to manage caching.

Missing references are represented as `null` by `evaluateValue`. Internally a missing reference stays distinct from an explicit null, but the two are equal to each other under `eq` and behave identically for `defined` and `empty`. Numeric values are evaluated as Dart `double` values.

`match` uses Dart `RegExp`, so regular-expression patterns follow Dart's regular-expression syntax rather than JavaScript's in every detail. Expressions and patterns should be treated as trusted input.

## Differences from the TypeScript reference

This port tracks the [TypeScript reference](https://github.com/LieselThuriot/simple-expressions) for grammar, operators, and evaluation order. It deliberately does not reproduce every JavaScript coercion quirk. The differences below are intentional and covered by the shared parity corpus in `test/parity/cases.json`.

| Behaviour | TypeScript | This port |
| --- | --- | --- |
| String to number | `Number("")` is `0`, `"Infinity"` is a keyword | A string converts only if it parses as a number; `""` and `"   "` are `NaN` |
| `eq` on two lists or maps | Reference equality, so `eq(#a, #b)` on equal-looking lists is false | Structural equality: same length or key set, and every pair loosely equal, to a depth of 64 |
| `parseExpression` | Returns `(model) => value` | Returns an `Expression`; call `evaluateValue(model)` for the raw value or `evaluate(model)` for truthiness |
| Class name | `SimpleExpression` | `Expression` |
| Missing vs null | Distinguishable in results (`undefined` vs `null`) | Both surface as `null` from `evaluateValue`, and are equal under `eq` |
| Model values | Any JavaScript object | Only `Map` keys resolve; a value of an unsupported runtime type is treated as an empty object |

Numbers render as their shortest round-trip decimal, in plain notation for magnitudes in `[1e-6, 1e21)` and lowercase exponent notation outside it — the same rule the C# port uses, and the same output JavaScript produces for these values.

## Example

Run the executable sample from this repository:

```bash
dart run tool/simple_expressions_example.dart
```

The sample is kept in the repository for development and is excluded from packages published with `dart pub publish`.

## Development

```bash
dart pub get
dart format .
dart analyze
dart test
```
