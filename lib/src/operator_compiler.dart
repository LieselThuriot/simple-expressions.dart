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
            (model) => _Value.string(_falsyString(inner(model)).toLowerCase()));
      case 'upper':
        return _Compiled(
            (model) => _Value.string(_falsyString(inner(model)).toUpperCase()));
      case 'trim':
        return _Compiled((model) => _trim(inner(model)));
      case 'defined':
        return _Compiled(
            (model) => inner(model).isNullish ? _falseValue : _trueValue);
      case 'int':
        return _Compiled((model) =>
            _Value.number(_truncate(_mathNumber(inner(model), strict: true))));
      case 'num':
        return _Compiled((model) => _Value.number(_num(inner(model))));
      case 'abs':
        return _Compiled((model) =>
            _Value.number(_mathNumber(inner(model), strict: true).abs()));
      case 'floor':
        return _Compiled((model) =>
            _Value.number(_floor(_mathNumber(inner(model), strict: true))));
      case 'ceil':
        return _Compiled((model) =>
            _Value.number(_ceil(_mathNumber(inner(model), strict: true))));
      case 'sqrt':
        return _Compiled((model) =>
            _Value.number(math.sqrt(_mathNumber(inner(model), strict: true))));
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
        return _Compiled((model) =>
            _compare(left(model), right(model)) > 0 ? _trueValue : _falseValue);
      case 'lt':
        return _Compiled((model) =>
            _compare(left(model), right(model)) < 0 ? _trueValue : _falseValue);
      case 'match':
        return _compileMatch(left, right);
      case 'round':
        return _Compiled((model) => _round(left(model), right(model)));
      case 'pow':
        return _Compiled((model) => _Value.number(math.pow(
            _mathNumber(left(model), strict: true),
            _mathNumber(right(model), strict: true))));
      default:
        _fail('invalid operator: $operator');
    }
  }

  _Compiled _compileMatch(_Compiled value, _Compiled pattern) {
    final constant = pattern.constantValue;
    if (constant != null &&
        constant.kind == _ValueKind.string &&
        constant.isTruthy) {
      final regex = RegExp(constant.value as String);
      return _Compiled((model) =>
          regex.hasMatch(_regexInput(value(model))) ? _trueValue : _falseValue);
    }
    return _Compiled((model) {
      final runtimePattern = pattern(model);
      if (runtimePattern.kind != _ValueKind.string ||
          !runtimePattern.isTruthy) {
        return _falseValue;
      }
      final regex = RegExp(runtimePattern.value as String);
      return regex.hasMatch(_regexInput(value(model)))
          ? _trueValue
          : _falseValue;
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
        return _Compiled((model) => _Value.number(math.min(
            math.max(_mathNumber(condition(model), strict: true),
                _mathNumber(whenTrue(model), strict: true)),
            _mathNumber(whenFalse(model), strict: true))));
      default:
        _fail('invalid operator: $operator');
    }
  }

  static _Compiled _compileNumericVariadic(
      List<_Compiled> arguments, _NumericOperation operation, String name) {
    return _Compiled((model) {
      final numbers = <double>[];
      final activeLists = HashSet<List>.identity();
      for (final argument in arguments) {
        final value = argument(model);
        if (arguments.length == 1 && value.kind != _ValueKind.array) {
          throw StateError(
              'operator $name expects at least two arguments or one list argument');
        }
        _flattenNumeric(value, numbers, activeLists);
      }

      switch (operation) {
        case _NumericOperation.subtract:
        case _NumericOperation.divide:
        case _NumericOperation.modulo:
          if (numbers.length < 2) {
            final operatorName = '${name[0].toUpperCase()}${name.substring(1)}';
            throw StateError('$operatorName requires at least two values');
          }
        case _NumericOperation.minimum:
          if (numbers.isEmpty) {
            throw StateError('Min requires at least one value');
          }
        case _NumericOperation.maximum:
          if (numbers.isEmpty) {
            throw StateError('Max requires at least one value');
          }
        case _NumericOperation.add:
        case _NumericOperation.multiply:
      }

      switch (operation) {
        case _NumericOperation.add:
          return _Value.number(numbers.fold(0, (sum, value) => sum + value));
        case _NumericOperation.multiply:
          return _Value.number(
              numbers.fold(1, (product, value) => product * value));
        case _NumericOperation.subtract:
          return _Value.number(
              _foldNumeric(numbers, (result, value) => result - value));
        case _NumericOperation.divide:
          return _Value.number(_foldNumeric(numbers, (result, value) {
            if (value == 0) throw StateError('Division by zero');
            return result / value;
          }));
        case _NumericOperation.modulo:
          return _Value.number(_foldNumeric(numbers, _javascriptRemainder));
        case _NumericOperation.minimum:
          return _Value.number(numbers.reduce(_javascriptMin));
        case _NumericOperation.maximum:
          return _Value.number(numbers.reduce(_javascriptMax));
      }
    });
  }

  static void _flattenNumeric(
      _Value value, List<double> numbers, Set<List> activeLists) {
    if (value.kind != _ValueKind.array) {
      numbers.add(_mathNumber(value, strict: true));
      return;
    }

    final items = value.value as List;
    if (!activeLists.add(items)) throw StateError('Invalid numeric value');
    try {
      for (final item in items) {
        _flattenNumeric(_arrayItem(item), numbers, activeLists);
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
