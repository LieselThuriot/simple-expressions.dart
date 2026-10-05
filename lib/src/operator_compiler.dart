part of 'simple_expressions_impl.dart';

enum _OperatorArity { unary, binary, ternary, variadic }

class _OperatorSpec {
  const _OperatorSpec(
    this.arity, {
    this.supportsSingleListArgument = false,
  });

  final _OperatorArity arity;
  final bool supportsSingleListArgument;
}

extension _OperatorCompiler on _ExpressionParser {
  _OperatorSpec _operatorSpec(String operator) {
    switch (operator) {
      case 'not':
      case 'empty':
      case 'len':
      case 'lower':
      case 'upper':
      case 'trim':
      case 'defined':
      case 'int':
      case 'num':
      case 'abs':
      case 'floor':
      case 'ceil':
      case 'sqrt':
        return const _OperatorSpec(_OperatorArity.unary);
      case 'eq':
      case 'contains':
      case 'startswith':
      case 'endswith':
      case 'gt':
      case 'lt':
      case 'match':
      case 'in':
      case 'round':
      case 'pow':
        return const _OperatorSpec(_OperatorArity.binary);
      case 'clamp':
        return const _OperatorSpec(_OperatorArity.ternary);
      case 'or':
      case 'and':
      case 'concat':
        return const _OperatorSpec(_OperatorArity.variadic);
      case 'add':
      case 'sub':
      case 'mul':
      case 'div':
      case 'mod':
      case 'min':
      case 'max':
        return const _OperatorSpec(
          _OperatorArity.variadic,
          supportsSingleListArgument: true,
        );
      case 'if':
        return const _OperatorSpec(_OperatorArity.ternary);
      default:
        _fail('invalid operator: $operator');
    }
  }

  _Compiled _compileUnary(String operator, _Compiled inner) {
    switch (operator) {
      case 'not':
        return _Compiled(
            (model) => inner(model).isTruthy ? _falseValue : _trueValue);
      case 'empty':
        return _Compiled(
            (model) => _isEmpty(inner(model)) ? _trueValue : _falseValue);
      case 'len':
        return _Compiled((model) => _length(inner(model)));
      case 'lower':
        return _Compiled(
            (model) => _Value.string(_falsyText(inner(model)).toLowerCase()));
      case 'upper':
        return _Compiled(
            (model) => _Value.string(_falsyText(inner(model)).toUpperCase()));
      case 'trim':
        return _Compiled((model) => _trim(inner(model)));
      case 'defined':
        return _Compiled(
            (model) => inner(model).isNullish ? _falseValue : _trueValue);
      case 'int':
        return _Compiled((model) =>
            _numericResult(_toNumber(inner(model)).truncateToDouble()));
      case 'num':
        return _Compiled((model) => _numericResult(_toNumber(inner(model))));
      case 'abs':
        return _Compiled(
            (model) => _numericResult(_toNumber(inner(model)).abs()));
      case 'floor':
        return _Compiled(
            (model) => _numericResult(_toNumber(inner(model)).floorToDouble()));
      case 'ceil':
        return _Compiled(
            (model) => _numericResult(_toNumber(inner(model)).ceilToDouble()));
      case 'sqrt':
        return _Compiled(
            (model) => _numericResult(math.sqrt(_toNumber(inner(model)))));
      default:
        _fail('invalid operator: $operator');
    }
  }

  _Compiled _compileBinary(String operator, _Compiled left, _Compiled right) {
    switch (operator) {
      case 'eq':
        return _Compiled((model) =>
            _looseEquals(left(model), right(model)) ? _trueValue : _falseValue);
      case 'contains':
        return _Compiled((model) =>
            _contains(left(model), right(model)) ? _trueValue : _falseValue);
      case 'startswith':
        return _Compiled((model) =>
            _startsWith(left(model), right(model)) ? _trueValue : _falseValue);
      case 'endswith':
        return _Compiled((model) =>
            _endsWith(left(model), right(model)) ? _trueValue : _falseValue);
      case 'in':
        return _Compiled((model) =>
            _inList(left(model), right(model)) ? _trueValue : _falseValue);
      case 'gt':
        return _Compiled((model) {
          final comparison = _compare(left(model), right(model));
          return comparison != null && comparison > 0
              ? _trueValue
              : _falseValue;
        });
      case 'lt':
        return _Compiled((model) {
          final comparison = _compare(left(model), right(model));
          return comparison != null && comparison < 0
              ? _trueValue
              : _falseValue;
        });
      case 'match':
        return _compileMatch(left, right);
      case 'round':
        return _Compiled((model) => _round(left(model), right(model)));
      case 'pow':
        return _Compiled((model) {
          final base = left(model);
          final exponent = right(model);
          return _numericResult(math.pow(_toNumber(base), _toNumber(exponent)));
        });
      default:
        _fail('invalid operator: $operator');
    }
  }

  _Compiled _compileMatch(_Compiled value, _Compiled pattern) {
    final constant = pattern.constantValue;
    if (constant != null &&
        constant.kind == _ValueKind.string &&
        constant.isTruthy) {
      final RegExp regex;
      try {
        regex = RegExp(constant.value as String);
      } on FormatException catch (error) {
        throw ExpressionParseException.withoutPosition(
            'invalid regular expression: ${error.message}');
      }
      return _Compiled((model) =>
          regex.hasMatch(_falsyText(value(model))) ? _trueValue : _falseValue);
    }
    return _Compiled((model) {
      final input = value(model);
      final runtimePattern = pattern(model);
      if (runtimePattern.kind != _ValueKind.string ||
          !runtimePattern.isTruthy) {
        return _falseValue;
      }
      final RegExp regex;
      try {
        regex = RegExp(runtimePattern.value as String);
      } on FormatException catch (error) {
        throw ExpressionEvaluationException(
            'Invalid regular expression: ${error.message}');
      }
      return regex.hasMatch(_falsyText(input)) ? _trueValue : _falseValue;
    });
  }

  _Compiled _compileVariadic(String operator, List<_Compiled> values) {
    switch (operator) {
      case 'or':
        return _Compiled((model) {
          for (final value in values) {
            if (value(model).isTruthy) return _trueValue;
          }
          return _falseValue;
        });
      case 'and':
        return _Compiled((model) {
          for (final value in values) {
            if (!value(model).isTruthy) return _falseValue;
          }
          return _trueValue;
        });
      case 'concat':
        if (values.every((value) => value.constantValue != null)) {
          final buffer = StringBuffer();
          for (final value in values) {
            _writeConcatValue(buffer, value.constantValue!);
          }
          return _Compiled.constant(_Value.string(buffer.toString()));
        }
        return _Compiled((model) {
          final buffer = StringBuffer();
          for (final value in values) {
            _writeConcatValue(buffer, value(model));
          }
          return _Value.string(buffer.toString());
        });
      case 'add':
        return _compileNumericVariadic(values, _NumericOperation.add, operator);
      case 'sub':
        return _compileNumericVariadic(
            values, _NumericOperation.subtract, operator);
      case 'mul':
        return _compileNumericVariadic(
            values, _NumericOperation.multiply, operator);
      case 'div':
        return _compileNumericVariadic(
            values, _NumericOperation.divide, operator);
      case 'mod':
        return _compileNumericVariadic(
            values, _NumericOperation.modulo, operator);
      case 'min':
        return _compileNumericVariadic(
            values, _NumericOperation.minimum, operator);
      case 'max':
        return _compileNumericVariadic(
            values, _NumericOperation.maximum, operator);
      default:
        _fail('invalid operator: $operator');
    }
  }

  _Compiled _compileTernary(
    String operator,
    _Compiled condition,
    _Compiled whenTrue,
    _Compiled whenFalse,
  ) {
    switch (operator) {
      case 'if':
        return _Compiled((model) =>
            condition(model).isTruthy ? whenTrue(model) : whenFalse(model));
      case 'clamp':
        return _Compiled((model) {
          final value = condition(model);
          final minimum = whenTrue(model);
          final maximum = whenFalse(model);
          return _numericResult(math.min(
              math.max(_toNumber(value), _toNumber(minimum)),
              _toNumber(maximum)));
        });
      default:
        _fail('invalid operator: $operator');
    }
  }

  static _Compiled _compileNumericVariadic(
      List<_Compiled> arguments, _NumericOperation operation, String name) {
    return _Compiled((model) {
      final evaluated = <_Value>[];
      for (final argument in arguments) {
        evaluated.add(argument(model));
      }
      if (arguments.length == 1 && evaluated.single.kind != _ValueKind.array) {
        throw ExpressionEvaluationException(
            'Invalid Expression: operator $name expects at least two arguments '
            'or one list argument');
      }

      final leaves = <_Value>[];
      final activeLists = HashSet<List>.identity();
      for (final value in evaluated) {
        _flattenNumeric(value, leaves, activeLists);
      }

      final numbers = [for (final leaf in leaves) _toNumber(leaf)];

      switch (operation) {
        case _NumericOperation.subtract:
        case _NumericOperation.divide:
        case _NumericOperation.modulo:
          if (leaves.length < 2) {
            final operatorName = '${name[0].toUpperCase()}${name.substring(1)}';
            throw ExpressionEvaluationException(
                '$operatorName requires at least two values');
          }
        case _NumericOperation.minimum:
          if (leaves.isEmpty) {
            throw ExpressionEvaluationException(
                'Min requires at least one value');
          }
        case _NumericOperation.maximum:
          if (leaves.isEmpty) {
            throw ExpressionEvaluationException(
                'Max requires at least one value');
          }
        case _NumericOperation.add:
        case _NumericOperation.multiply:
      }

      switch (operation) {
        case _NumericOperation.add:
          return _numericResult(numbers.fold(0.0, (sum, value) => sum + value));
        case _NumericOperation.multiply:
          return _numericResult(
              numbers.fold(1.0, (product, value) => product * value));
        case _NumericOperation.subtract:
          return _numericResult(
              _foldNumeric(numbers, (result, value) => result - value));
        case _NumericOperation.divide:
          return _numericResult(_foldNumeric(numbers, (result, value) {
            if (value == 0) {
              throw ExpressionEvaluationException('Division by zero');
            }
            return result / value;
          }));
        case _NumericOperation.modulo:
          return _numericResult(_foldNumeric(numbers, _signedRemainder));
        case _NumericOperation.minimum:
          return _numericResult(numbers.reduce(math.min));
        case _NumericOperation.maximum:
          return _numericResult(numbers.reduce(math.max));
      }
    });
  }

  static void _flattenNumeric(
      _Value value, List<_Value> leaves, Set<List> activeLists) {
    if (value.kind != _ValueKind.array) {
      leaves.add(value);
      return;
    }

    final items = value.value as List;
    if (!activeLists.add(items)) {
      throw ExpressionEvaluationException('Invalid numeric value');
    }
    try {
      for (final item in items) {
        _flattenNumeric(_arrayItem(item), leaves, activeLists);
      }
    } finally {
      activeLists.remove(items);
    }
  }

  static double _foldNumeric(
      List<double> values, double Function(double, double) operation) {
    var result = values.first;
    for (final value in values.skip(1)) {
      result = operation(result, value);
    }
    return result;
  }
}

enum _NumericOperation {
  add,
  subtract,
  multiply,
  divide,
  modulo,
  minimum,
  maximum
}
