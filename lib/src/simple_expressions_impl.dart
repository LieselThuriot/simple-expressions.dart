import 'dart:collection';
import 'dart:math' as math;

part 'operator_compiler.dart';
part 'equality.dart';
part 'number_format.dart';
part 'parser.dart';
part 'runtime.dart';
part 'tokenizer.dart';

typedef _EvaluatorFunction = _Value Function(Object? model);

/// The error raised when an expression cannot be parsed.
class ExpressionParseException extends FormatException {
  /// Creates a parse exception with a zero-based source position.
  ExpressionParseException(String message, this.position)
      : super('Invalid Expression at $position: $message', null, position);

  /// Reports a failure that has no meaningful source position, matching the
  /// upstream `Invalid Expression: {message}` format.
  ExpressionParseException.withoutPosition(String message)
      : position = -1,
        super('Invalid Expression: $message');

  /// The zero-based source position of the failure, or `-1` when unknown.
  final int position;
}

/// A reusable parsed expression.
class SimpleExpression {
  SimpleExpression._compiled(this._evaluator);

  /// Creates a reusable expression from a Boolean or expression string.
  SimpleExpression(Object expression) {
    if (expression is bool) {
      _evaluator = _Compiled.constant(expression ? _trueValue : _falseValue);
    } else if (expression is String) {
      final normalized = expression.trim();
      if (normalized.isEmpty) {
        throw ExpressionParseException.withoutPosition('whitespace');
      }
      _evaluator = SimpleExpressions._getParsedExpression(normalized);
    } else {
      throw ArgumentError('Invalid Expression: unsupported type');
    }
  }

  late final _Compiled _evaluator;

  /// Evaluates the expression and returns its raw value.
  ///
  /// Arrays read from the model are returned as the model's live lists,
  /// not defensive copies.
  Object? evaluateValue(Object? model) => _evaluator(model).toPublicValue();

  /// Evaluates the expression using JavaScript-like truthiness.
  bool evaluate(Object? model) => _evaluator(model).isTruthy;
}

/// Parses expression text into a reusable evaluator.
SimpleExpression parseExpression(String expression) =>
    SimpleExpression._compiled(
        SimpleExpressions._getParsedExpression(expression.trim()));

/// Evaluates an expression and returns its truthiness.
bool executeExpression(Object? model, Object expression) =>
    SimpleExpressions.get(expression).evaluate(model);

/// Controls the evaluator caches and constructs reusable expressions.
class SimpleExpressions {
  SimpleExpressions._();

  static const int _defaultCacheLimit = 1000;
  static int _cacheLimit = _defaultCacheLimit;
  static bool _enabledCaches = true;
  static final LinkedHashMap<String, _Compiled> _parseCache = LinkedHashMap();
  static final LinkedHashMap<String, SimpleExpression> _expressionCache =
      LinkedHashMap();
  static final LinkedHashMap<String, RegExp> _regexCache = LinkedHashMap();

  /// Returns a cached reusable expression when caching is enabled.
  static SimpleExpression get(Object expression) {
    if (expression is! String && expression is! bool) {
      throw ArgumentError('Invalid Expression: unsupported type');
    }
    final key = expression is String ? expression : '$expression';
    if (_enabledCaches) {
      final cached = _expressionCache[key];
      if (cached != null) return cached;
    }

    final result = SimpleExpression(expression);
    if (_enabledCaches) _setCacheValue(_expressionCache, key, result);
    return result;
  }

  /// Clears parsed-expression, reusable-expression, and/or runtime regex caches.
  static void clear({bool? parsed, bool? expression, bool? regex}) {
    final clearAll = parsed == null && expression == null && regex == null;
    if (clearAll || parsed == true) _parseCache.clear();
    if (clearAll || expression == true) _expressionCache.clear();
    if (clearAll || regex == true) _regexCache.clear();
  }

  /// Disables caching and clears existing entries.
  static void disableCaches() {
    _enabledCaches = false;
    clear();
  }

  /// Enables caching without changing the configured cache limit.
  static void enableCaches() {
    _enabledCaches = true;
  }

  /// Sets the FIFO cache limit. Values below 1 throw and do not change cache state.
  static void setCacheLimit(int limit) {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'must be at least 1');
    }
    _cacheLimit = limit;
    _trimCache(_parseCache);
    _trimCache(_expressionCache);
    _trimCache(_regexCache);
  }

  // Callers pass already-trimmed input.
  static _Compiled _getParsedExpression(String expression) {
    if (expression.isEmpty) {
      throw ExpressionParseException.withoutPosition('formatting');
    }
    if (_enabledCaches) {
      final cached = _parseCache[expression];
      if (cached != null) return cached;
    }

    final result = _ExpressionParser(expression).parse();
    if (_enabledCaches) _setCacheValue(_parseCache, expression, result);
    return result;
  }

  static RegExp _getRuntimeRegExp(String pattern) {
    if (_enabledCaches) {
      final cached = _regexCache[pattern];
      if (cached != null) return cached;
    }

    final result = RegExp(pattern);
    if (_enabledCaches) _setCacheValue(_regexCache, pattern, result);
    return result;
  }

  static void _setCacheValue<T>(
      LinkedHashMap<String, T> cache, String key, T value) {
    if (cache.length >= _cacheLimit) cache.remove(cache.keys.first);
    cache[key] = value;
  }

  static void _trimCache<T>(LinkedHashMap<String, T> cache) {
    while (cache.length > _cacheLimit) {
      cache.remove(cache.keys.first);
    }
  }
}
