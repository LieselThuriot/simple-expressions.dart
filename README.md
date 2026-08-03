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

Missing references are represented as `null` by `evaluateValue`, but remain distinct from explicit null internally for `defined`, `empty`, and equality behavior. Numeric values are evaluated as Dart `double` values.

`match` uses Dart `RegExp`, so regular-expression patterns follow Dart's regular-expression syntax rather than JavaScript's in every detail. Expressions and patterns should be treated as trusted input.

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
