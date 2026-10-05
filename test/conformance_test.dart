import 'dart:convert';
import 'dart:io';

import 'package:simple_expressions/simple_expressions.dart';
import 'package:test/test.dart';

import 'support/conformance_validator.dart';

void main() {
  final decoded = jsonDecode(
    File('test/fixtures/conformance/spec/v1/cases.json').readAsStringSync(),
  );
  final cases = validateCorpus(decoded);

  for (final item in cases) {
    test('v1/${item['id']}', () {
      final expression = item['expression'] as String;
      final model =
          item.containsKey('model') ? item['model'] : const <String, Object?>{};

      if (item.containsKey('error')) {
        final expected = item['error'] as String;
        expect(
          () => parseExpression(expression).evaluateValue(model),
          throwsA(predicate((Object error) => errorMatches(error, expected))),
        );
      } else if (item.containsKey('truthy')) {
        expect(executeExpression(model, expression), item['truthy']);
      } else {
        expect(
            matchesValue(item['value'],
                parseExpression(expression).evaluateValue(model)),
            isTrue);
      }
    });
  }
}
