import 'package:simple_expressions/simple_expressions.dart';
import 'package:test/test.dart';

void main() {
  test('supports structural equality for port models', () {
    expect(
      executeExpression({
        'a': [1, 2],
        'b': [1, 2],
      }, 'eq(#a, #b)'),
      isTrue,
    );
    expect(
      executeExpression({
        'a': [
          1,
          [2, 3]
        ],
        'b': [
          1,
          [2, 3]
        ],
      }, 'eq(#a, #b)'),
      isTrue,
    );
    expect(
      executeExpression({
        'a': {'x': 1},
        'b': {'x': 1},
      }, 'eq(#a, #b)'),
      isTrue,
    );
  });

  test('does not convert empty or blank strings to zero', () {
    expect(executeExpression({'value': ''}, 'eq(#value, 0)'), isFalse);
    expect(executeExpression({'value': '   '}, 'eq(#value, 0)'), isFalse);
  });
}
