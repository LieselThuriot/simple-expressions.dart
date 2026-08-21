part of 'simple_expressions_impl.dart';

class _ExpressionParser {
  _ExpressionParser(String expression) : _tokenizer = _Tokenizer(expression);

  final _Tokenizer _tokenizer;

  _Compiled parse() {
    final result = _parseValue();
    if (_tokenizer.kind != _TokenKind.end) _fail('unexpected trailing input');
    return result;
  }

  _Compiled _parseValue() {
    switch (_tokenizer.kind) {
      case _TokenKind.string:
        final value = _tokenizer.value;
        _tokenizer.next();
        return _Compiled.constant(_Value.string(value));
      case _TokenKind.number:
        final value = double.parse(_tokenizer.value);
        _tokenizer.next();
        return _Compiled.constant(_Value.number(value));
      case _TokenKind.reference:
        final path = _tokenizer.value;
        final segments = _validateReference(path);
        _tokenizer.next();
        if (segments.length == 1) {
          return _Compiled((model) => _resolveSingle(model, path));
        }
        return _Compiled((model) => _resolvePath(model, path, segments));
      case _TokenKind.identifier:
        final identifier = _tokenizer.value;
        _tokenizer.next();
        final normalized = identifier.toLowerCase();
        if (normalized == 'true') {
          return _Compiled.constant(_trueValue);
        }
        if (normalized == 'false') {
          return _Compiled.constant(_falseValue);
        }
        return _parseCall(identifier, normalized);
      case _TokenKind.openBracket:
        return _parseList();
      default:
        _fail('expected an expression');
    }
  }

  _Compiled _parseList() {
    _tokenizer.next();
    if (_tokenizer.kind == _TokenKind.closeBracket) {
      _tokenizer.next();
      return _Compiled.constant(_Value.array(const <_Value>[]));
    }

    final values = <_Compiled>[_parseValue()];
    while (_tokenizer.kind == _TokenKind.comma) {
      _tokenizer.next();
      values.add(_parseValue());
    }
    if (_tokenizer.kind != _TokenKind.closeBracket) {
      _fail('expected closing bracket');
    }
    _tokenizer.next();
    final compiled = List<_Compiled>.of(values, growable: false);
    return _Compiled((model) {
      final items =
          List<_Value>.filled(compiled.length, const _Value.missing());
      for (var index = 0; index < compiled.length; index++) {
        items[index] = compiled[index](model);
      }
      return _Value.array(items);
    });
  }

  _Compiled _parseCall(String operator, String normalized) {
    if (_tokenizer.kind != _TokenKind.openParen) {
      _fail('invalid operator: $operator');
    }
    final spec = _operatorSpec(normalized);
    final arity = spec.arity;
    _tokenizer.next();
    if (_tokenizer.kind == _TokenKind.closeParen) {
      _fail('missing operator argument');
    }

    final left = _parseValue();
    if (arity == _OperatorArity.variadic) {
      if (_tokenizer.kind != _TokenKind.comma) {
        if (_tokenizer.kind != _TokenKind.closeParen ||
            !spec.supportsSingleListArgument) {
          _fail('operator $operator expects at least two arguments');
        }
        _tokenizer.next();
        return _compileVariadic(normalized, [left]);
      }
      final values = <_Compiled>[left];
      while (_tokenizer.kind == _TokenKind.comma) {
        _tokenizer.next();
        values.add(_parseValue());
      }
      if (_tokenizer.kind != _TokenKind.closeParen) {
        _fail('operator $operator expects at least two arguments');
      }
      _tokenizer.next();
      return _compileVariadic(normalized, values);
    }

    if (arity == _OperatorArity.unary) {
      if (_tokenizer.kind != _TokenKind.closeParen) {
        _fail('operator $operator expects one argument');
      }
      _tokenizer.next();
      return _compileUnary(normalized, left);
    }

    if (_tokenizer.kind != _TokenKind.comma) {
      _fail(
          'operator $operator expects ${arity == _OperatorArity.binary ? 'two' : 'three'} arguments');
    }
    _tokenizer.next();
    final right = _parseValue();
    if (arity == _OperatorArity.binary) {
      if (_tokenizer.kind != _TokenKind.closeParen) {
        _fail('operator $operator expects two arguments');
      }
      _tokenizer.next();
      return _compileBinary(normalized, left, right);
    }

    if (_tokenizer.kind != _TokenKind.comma) {
      _fail('operator $operator expects three arguments');
    }
    _tokenizer.next();
    final whenFalse = _parseValue();
    if (_tokenizer.kind != _TokenKind.closeParen) {
      _fail('operator $operator expects three arguments');
    }
    _tokenizer.next();
    return _compileTernary(normalized, left, right, whenFalse);
  }

  static List<String> _validateReference(String path) {
    const unsafe = {'__proto__', 'constructor', 'prototype'};
    final segments = path.split('.');
    for (final segment in segments) {
      if (segment.isEmpty || unsafe.contains(segment)) {
        throw ExpressionParseException.withoutPosition(
            'invalid model reference: #$path');
      }
    }
    return segments;
  }

  Never _fail(String message) =>
      throw ExpressionParseException(message, _tokenizer.position);
}
