import 'package:simple_expressions/simple_expressions.dart';

void main() {
  final model = {
    'user': {'name': 'Ada', 'role': 'engineer'},
    'score': 8,
    'allowedRoles': ['editor', 'engineer'],
  };

  final isReady = executeExpression(
    model,
    'and(eq(#user.name, "Ada"), gt(#score, 5))',
  );
  final greeting = parseExpression(
    'concat("Hello, ", #user.name, "!")',
  ).evaluateValue(model);
  final status = parseExpression(
    'if(and(gt(#score, 5), lt(#score, 10)), "ready", "keep practicing")',
  ).evaluateValue(model);
  final hasAccess = executeExpression(
    model,
    'in(#user.role, #allowedRoles)',
  );

  print('Ready: $isReady');
  print('Greeting: $greeting');
  print('Status: $status');
  print('Role allowed: $hasAccess');
}
