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

From a repository checkout, run the package example:

```bash
dart run example/simple_expressions_example.dart
```

The sample is included in the published package's Example tab.

## Syntax

Constants support case-insensitive Booleans, finite signed decimal and exponent-form numeric literals (including `.5` and `5.`), single-, double-, or backtick-quoted strings, and recursive list literals in square brackets. References begin with `#`. For a dotted reference, the evaluator first checks for an exact dotted key and then traverses nested map values. References cannot contain empty segments or the reserved segments `__proto__`, `constructor`, and `prototype`; those restrictions are retained for compatibility with the TypeScript reference.

Operators are case-insensitive. `and` and `or` are variadic and short-circuit. `if` is lazy and evaluates only its selected branch. `in` requires a list; `contains`, `startswith`, and `endswith` require a string left operand. `len` returns `0` for nullish values, a string/list length, or an exact `length` map key, and throws otherwise.

`not`, `empty`, `defined`, `lower`, `upper`, `trim`, `int`, `num`, `abs`, `floor`, `ceil`, and `sqrt` take one argument. `num` accepts scalar values only. `eq`, `contains`, `startswith`, `endswith`, `in`, `gt`, `lt`, `match`, `round`, and `pow` take two. `clamp` and `if` take three. `concat`, `add`, `sub`, `mul`, `div`, `mod`, `min`, and `max` take two or more expression arguments. Each numeric variadic operator also accepts one expression that evaluates to a list.

`in` uses the same equality as `eq`. Null and missing are equal only to each other. Primitive values compare directly when they have the same kind; finite numbers also compare with valid finite decimal strings, and Booleans coerce only against finite numbers or valid finite decimal strings. Blank strings are nonnumeric. Lists compare structurally only with lists, maps only with maps, and structural comparison is cycle-safe. Collections never coerce to scalars for equality.

Strict numeric operators accept finite numbers or finite signed decimal/exponent strings using the literal grammar. Radix strings, blank strings, Booleans, null, missing values, collections used as leaves, and nonfinite values throw `Invalid numeric value`. Every numeric result must also be finite or the operator throws `Invalid numeric result`; `div` and `mod` keep the more specific `Division by zero` error. Numeric variadic operators first evaluate every expression, then recursively flatten all list arguments depth-first, and only then convert leaves. One expression argument is valid syntax but must evaluate to a list. `sub`, `div`, and `mod` require at least two flattened leaves; `min` and `max` require one. Empty lists therefore give `add` the identity `0` and `mul` the identity `1`.

`round` accepts an integer precision from 0 through 308 and rounds exact runtime-number midpoint ties away from zero without multiplying the input by a potentially overflowing scale. Comparisons are ordinal for two strings and numeric for finite number/valid-decimal-string pairs; Booleans, nullish values, blank or invalid strings, and collections make `gt` and `lt` false. Numeric scalar results normalize `-0.0` to `0.0`.

Expression boundaries, tokenizer delimiters, `trim`, and numeric strings use the explicit Unicode White_Space set U+0009-U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000-U+200A, U+2028, U+2029, U+202F, U+205F, and U+3000. U+FEFF is not whitespace. Text conversion detects active cyclic lists and throws `Cyclic list value`; repeated lists that are no longer active are allowed.

The evaluator retains JavaScript-style truthiness: null, missing, false, numeric zero, `NaN`, and empty strings are falsey; lists and maps are truthy. Numeric values are evaluated as Dart `double` values. `trim` preserves null and missing values; other falsey values become empty strings before trimming. `defined` is false only for null and missing values. `match` uses Dart `RegExp`, so patterns that rely on JavaScript-specific regex syntax are not portable.

## Differences from the TypeScript reference

This port follows the portable behavior defined by [simple-expressions-conformance](https://github.com/LieselThuriot/simple-expressions-conformance). The remaining platform differences are Dart model representation, Dart `RegExp`, and the public evaluator shape.

| Behaviour | TypeScript | This port |
| --- | --- | --- |
| `parseExpression` | Returns `(model) => value` | Returns a `SimpleExpression`; call `evaluateValue(model)` for the raw value or `evaluate(model)` for truthiness |
| Missing vs null | Distinguishable in results (`undefined` vs `null`) | Both surface as `null` from `evaluateValue`, and are equal under `eq` |
| Model values | Any JavaScript object | String keys in Dart `Map` values resolve; list indexes are not traversed, and an unsupported runtime type is treated as an empty object |

Numbers use the same formatting rule as the TypeScript reference: the shortest round-trip decimal, plain notation for magnitudes in `[1e-6, 1e21)`, and lowercase exponent notation outside that range.

Structural equality applies recursively to lists and maps and is cycle-safe; cyclic graphs are compared by already-visited identity pairs rather than by requiring identical aliasing topology. Equality conversion remains non-throwing and is separate from strict numeric-operator input validation.

## Model Access

Models are read when an expression asks for a value. Nothing is copied or converted up front, so an expression only visits the parts of a model that it references.

Model values can be Dart maps and lists, along with strings, numbers, booleans, and null. Reference segments resolve exact String keys in Dart maps; non-string keys are not coerced. A non-map model root resolves every reference to a missing value.

Keep these details in mind:

- Model values are read live at evaluation time. Mutations made between evaluations are visible to the next evaluation.
- Scalar numeric values normalize negative zero. Because live model lists and maps are not copied or traversed on return, a `-0.0` nested inside one may remain observable.
- List indexes and list properties are not traversed through references.
- A value with an unsupported Dart runtime type is treated as an empty object.
- Missing references surface as `null` from `evaluateValue`. Internally, missing and explicit null remain distinct, but `eq`, `defined`, and `empty` treat them the same.
- A null or other non-map model root is preserved by the API but cannot resolve references, so references evaluate as missing.

## Caching

Parsed evaluators and expression wrappers returned by `SimpleExpressions.get` are cached by default. Both caches use the configured FIFO limit of 1,000 entries; cache hits do not refresh FIFO order. Boolean expressions and their lowercase equivalent strings share expression-cache keys (`true` with `"true"`, and `false` with `"false"`). Use `clear(parsed: true, expression: true)` for selective clearing, `setCacheLimit` to change both limits, and `disableCaches`/`enableCaches` to control caching. Disabling caches also clears existing entries. Literal `match` patterns are compiled eagerly into their parsed evaluator; model-supplied patterns are compiled when evaluated.

## Errors

Parse-time failures (malformed syntax, unknown operators, non-finite literals, invalid references, and invalid constant regex patterns) throw `ExpressionParseException`, which extends `FormatException`. Failures while evaluating a parsed expression (invalid numeric values, division by zero, cyclic lists, and invalid model-supplied regex patterns) throw `ExpressionEvaluationException`, which extends `StateError`. Passing a value that is neither a string nor a Boolean throws an `ArgumentError`.

## Security

Expressions and regex patterns are trusted input. Regex evaluation can be vulnerable to catastrophic backtracking. Do not use untrusted expressions or patterns as an authorization boundary.

## Development

The development and publishing commands below are run from the root of a
repository checkout. Initialize the shared test fixtures first:

```bash
git submodule update --init --recursive
```

### Local Dart SDK

Use the current stable Dart SDK for development. The library supports Dart
3.0+, but the repository's `lints` development dependency requires Dart 3.8
or later.

```bash
dart pub get
dart format .
dart analyze
dart test
```

### Docker Compose

The repository includes a Compose environment using `dart:stable` and host
networking. Use Docker Engine on Linux, or enable host networking in a
supported Docker Desktop installation (4.34 or later).

Create the untracked `.env` file from the repository's `.env.example`:

```bash
cp .env.example .env
```

Set `DART_PROJECT_PATH` to the absolute checkout path accessible to your
Docker daemon. For example, on a Linux host:

```dotenv
DART_PROJECT_PATH=/home/you/projects/simple_expressions_dart
```

With a Docker daemon running in WSL, a checkout on the Windows C: drive may
instead use `/mnt/c/path/to/simple_expressions_dart`. Choose the path for
your Docker environment.

Once the mount is configured, run the complete development check:

```bash
docker compose run --rm verify
```

This installs dependencies, formats the checkout, runs analysis, and runs
the tests. You can also override the path for a command; for example, from
PowerShell when using a WSL-hosted daemon:

```powershell
$env:DART_PROJECT_PATH = '/mnt/c/path/to/simple_expressions_dart'
docker compose run --rm verify
```

Individual commands are also available through the `dart` service:

```bash
docker compose run --rm dart pub get
docker compose run --rm dart format .
docker compose run --rm dart analyze
docker compose run --rm dart test
```

To open a shell in the Dart container:

```bash
docker compose run --rm shell
```

To check the package's pub.dev score locally with Pana (the check fails unless the package receives every available point):

```bash
docker compose run --rm pana
```

Pana is activated in the shared pub cache, so subsequent runs reuse the
downloaded package.

## Publishing

Sign in to pub.dev with the Google account that has permission to publish this package:

```bash
docker compose run --rm pub-login
```

Open the sign-in URL printed by the command and approve access. With host networking, the browser may be able to reach the callback directly. If it cannot reach the callback listener, copy the browser's final `http://localhost:<port>?...` URL and request it inside the running container from a second terminal:

```bash
docker ps --filter name=pub-login
docker exec -it <container-id> curl 'http://localhost:<port>?...'
```

Use the exact callback URL from your browser in place of the example URL. The login command will finish and save credentials when the callback succeeds.

Both publishing commands first run Pana and stop unless it reports the maximum score. Check what would be uploaded:

```bash
docker compose run --rm publish-dry-run
```

Before publishing, update the version in `pubspec.yaml` and add its release notes to `CHANGELOG.md`. Then publish; this runs pub.dev's interactive review and confirmation:

```bash
docker compose run --rm publish
```

The token is stored in the persistent `dart-publish-config` volume, separate from the shared package cache and the checkout. It remains available to later publishing runs; remove it with `docker compose down --volumes` when you want to clear it (this also removes the regular pub cache).

## Conformance

This package supports conformance specification v1. See [CONFORMANCE.md](https://github.com/LieselThuriot/simple-expressions.dart/blob/master/CONFORMANCE.md) for compatibility details. The repository pins the corpus at `test/fixtures/conformance/`.
