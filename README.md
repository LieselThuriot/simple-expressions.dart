# simple_expressions

![simple-expressions logo](https://raw.githubusercontent.com/LieselThuriot/simple-expressions.dart/refs/heads/master/simple-expressions.png)

[![pub package](https://img.shields.io/pub/v/simple_expressions.svg)](https://pub.dev/packages/simple_expressions)
[![license](https://img.shields.io/github/license/LieselThuriot/simple-expressions.dart.svg)](https://github.com/LieselThuriot/simple-expressions.dart/blob/master/LICENSE)

A dependency-free Dart and Flutter package for parsing and evaluating trusted expressions against JSON-like model values.

Requires Dart 3.0 or later.

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

`SimpleExpression` accepts a string or Boolean. `SimpleExpressions.get` returns a cached reusable expression when caching is enabled. `ExpressionParseException` exposes the zero-based source position for positioned parse errors.

## Example

Run the package example:

```bash
dart run example/simple_expressions_example.dart
```

The sample is included in the published package's Example tab.

## Syntax

Constants support case-insensitive Booleans, signed, decimal, and exponent-form numeric literals, single-, double-, or backtick-quoted strings, and recursive list literals in square brackets. References begin with `#`. For a dotted reference, the evaluator first checks for an exact dotted key and then traverses nested map values. References cannot contain empty segments or the reserved segments `__proto__`, `constructor`, and `prototype`; those restrictions are retained for compatibility with the TypeScript reference.

Operators are case-insensitive. `and` and `or` are variadic and short-circuit. `if` is lazy and evaluates only its selected branch. `in` requires a list; `contains`, `startswith`, and `endswith` require a string left operand. `len` returns `0` for nullish values, a string/list length, or an exact `length` map key, and throws otherwise.

`not`, `empty`, `defined`, `lower`, `upper`, `trim`, `int`, `num`, `abs`, `floor`, `ceil`, and `sqrt` take one argument. `num` accepts scalar values only. `eq`, `contains`, `startswith`, `endswith`, `in`, `gt`, `lt`, `match`, `round`, and `pow` take two. `clamp` and `if` take three. `concat`, `add`, `sub`, `mul`, `div`, `mod`, `min`, and `max` take two or more expression arguments. Each numeric variadic operator also accepts one expression that evaluates to a list.

`in` uses the same loose equality as `eq`. `trim` preserves null and missing values; other falsey values become empty strings before trimming. `defined` is false only for null and missing values. Lists may contain nested lists, model references, and operator expressions. Numeric operators throw `Invalid numeric value` for empty, blank, or invalid strings. `div` and `mod` throw `Division by zero` for zero divisors; `min` and `max` throw for empty lists.

Numeric inputs must be finite numbers or strings accepted by JavaScript `Number`, including decimal, exponent, hexadecimal, binary, and octal forms. Booleans, null, missing values, maps, lists used as leaves, blank or invalid strings, `NaN`, and infinities throw `Invalid numeric value`. Numeric variadic operators flatten list arguments recursively in depth-first order and reject active cyclic lists. `sub`, `div`, and `mod` require at least two flattened leaves; `min` and `max` require one. Empty lists therefore give the `add` identity `0` and `mul` identity `1`. Calculations may produce `NaN` or infinity as top-level results, but enclosing numeric operators reject those results as inputs. `round` requires a non-negative safe-integer precision, and `div`/`mod` throw for a zero divisor.

The evaluator uses JavaScript-style truthiness, loose equality, and value conversion where those rules can be represented by Dart values. Numeric values are evaluated as Dart `double` values. `match` uses Dart `RegExp`, so patterns that rely on JavaScript-specific regex syntax are not portable.

## Differences from the TypeScript reference

This port follows the [TypeScript reference](https://github.com/LieselThuriot/simple-expressions) for grammar, operators, evaluation order, and selected safety rules. The main portability differences are Dart map/value representation, Dart `RegExp`, and the documented empty-string equality rule. Cross-language compatibility is tested separately in [simple-expressions-conformance](https://github.com/LieselThuriot/simple-expressions-conformance).

| Behaviour | TypeScript | This port |
| --- | --- | --- |
| Equality of empty strings and zero | `eq("", 0)` is true through JavaScript loose equality | `eq("", 0)` is false |
| `parseExpression` | Returns `(model) => value` | Returns a `SimpleExpression`; call `evaluateValue(model)` for the raw value or `evaluate(model)` for truthiness |
| Missing vs null | Distinguishable in results (`undefined` vs `null`) | Both surface as `null` from `evaluateValue`, and are equal under `eq` |
| Model values | Any JavaScript object | String keys in Dart `Map` values resolve; list indexes are not traversed, and an unsupported runtime type is treated as an empty object |

Numbers use the same formatting rule as the TypeScript reference: the shortest round-trip decimal, plain notation for magnitudes in `[1e-6, 1e21)`, and lowercase exponent notation outside that range.

Structural equality applies recursively to lists and maps and is cycle-safe; cyclic graphs are compared by already-visited identity pairs rather than by requiring identical aliasing topology. Loose `eq` conversions remain non-throwing and are separate from strict numeric-operator input validation. Unlike the TypeScript reference, Dart treats empty and blank strings as unequal to numeric zero in `eq`.

## Model Access

Models are read when an expression asks for a value. Nothing is copied or converted up front, so an expression only visits the parts of a model that it references.

Model values can be Dart maps and lists, along with strings, numbers, booleans, and null. Reference segments resolve exact String keys in Dart maps; non-string keys are not coerced. A non-map model root resolves every reference to a missing value.

Keep these details in mind:

- Model values are read live at evaluation time. Mutations made between evaluations are visible to the next evaluation.
- List indexes and list properties are not traversed through references.
- A value with an unsupported Dart runtime type is treated as an empty object.
- Missing references surface as `null` from `evaluateValue`. Internally, missing and explicit null remain distinct, but `eq`, `defined`, and `empty` treat them the same.
- A null or other non-map model root is preserved by the API but cannot resolve references, so references evaluate as missing.

## Caching

Parsed evaluators and expression wrappers returned by `SimpleExpressions.get` are cached by default. Both caches use the configured FIFO limit of 1,000 entries; cache hits do not refresh FIFO order. Use `clear(parsed: true, expression: true)` for selective clearing, `setCacheLimit` to change both limits, and `disableCaches`/`enableCaches` to control caching. Disabling caches also clears existing entries. Literal `match` patterns are compiled eagerly into their parsed evaluator; model-supplied patterns are compiled when evaluated.

## Security

Expressions and regex patterns are trusted input. Regex evaluation can be vulnerable to catastrophic backtracking. Do not use untrusted expressions or patterns as an authorization boundary.

## Development

```bash
dart pub get
dart format .
dart analyze
dart test
```

## Conformance

This package supports conformance specification v1. The pinned corpus is documented in `CONFORMANCE.md` and initialized at `test/fixtures/conformance`.
