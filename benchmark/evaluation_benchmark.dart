// Measures the per-evaluation cost of the model access path. Expression
// parsing is cached globally, so after warmup every benchmark here measures
// model access only. Mirrors the C# EvaluationBenchmarks scenarios.
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:simple_expressions/simple_expressions.dart';

const String simpleRule = 'and(eq(#User.Name, "Ada"), gt(#Score, 5))';
const String dottedRule = 'eq(#User.Address.City.Name, "Brussels")';
const String membershipRule = 'in(#User.Role, #AllowedRoles)';
const String largeMembershipRule = 'in(#User.Role, #ManyRoles)';
const String arrayEqualityRule = 'eq(#AllowedRoles, #AllowedRoles2)';

// Twenty distinct rules, as a rules-engine caller would have.
const List<String> ruleSet = [
  'eq(#Score, 8)',
  'gt(#Score, 5)',
  'lt(#Score, 10)',
  'defined(#Score)',
  'eq(#User.Name, "Ada")',
  'startswith(#User.Name, "A")',
  'endswith(#User.Name, "a")',
  'contains(#User.Role, "engineer")',
  'not(empty(#User.Role))',
  'defined(#User.Address)',
  'eq(#User.Address.City.Name, "Brussels")',
  'gt(#User.Address.City.Population, 100)',
  'in(#User.Role, #AllowedRoles)',
  'eq(len(#AllowedRoles), 2)',
  'empty(#Missing)',
  'or(eq(#Score, 1), eq(#Score, 8))',
  'and(defined(#User), defined(#Score))',
  'match(#User.Name, "^A")',
  'upper(#User.Name)',
  'concat(#User.Name, "!")',
];

Map<String, Object?> makeModel(int payloadEntries) {
  // Payload is never referenced by any expression; under lazy access it
  // should be free.
  final payload = <String, Object?>{};
  for (var index = 0; index < payloadEntries; index++) {
    payload['field$index'] = <String, Object?>{
      'Index': index,
      'Label': 'label-$index',
      'Enabled': index.isEven,
      'Nested': <String, Object?>{
        'A': index,
        'B': 'b$index',
        'C': <String, Object?>{'D': index * 2},
      },
    };
  }

  return <String, Object?>{
    'User': <String, Object?>{
      'Name': 'Ada',
      'Role': 'engineer',
      'Address': <String, Object?>{
        'City': <String, Object?>{'Name': 'Brussels', 'Population': 1200},
      },
    },
    'Score': 8,
    'AllowedRoles': <String>['editor', 'engineer'],
    'AllowedRoles2': <String>['editor', 'engineer'],
    'ManyRoles': <String>[
      for (var index = 0; index < 100; index++) 'role-$index',
      'engineer',
    ],
    'Payload': payload,
  };
}

final Map<String, Object?> smallModel = makeModel(0);
final Map<String, Object?> largeModel = makeModel(200);
final Expression parsedSimpleRule = parseExpression(simpleRule);

class EvaluationBenchmark extends BenchmarkBase {
  EvaluationBenchmark(super.name, this._body);

  final void Function() _body;

  @override
  void run() => _body();
}

void main() {
  // Warm the expression caches so the measured loop is model access only.
  executeExpression(smallModel, simpleRule);
  executeExpression(smallModel, dottedRule);
  executeExpression(smallModel, membershipRule);
  executeExpression(smallModel, largeMembershipRule);
  executeExpression(smallModel, arrayEqualityRule);
  for (final rule in ruleSet) {
    executeExpression(smallModel, rule);
  }

  final benchmarks = <EvaluationBenchmark>[
    EvaluationBenchmark('One rule, small model',
        () => executeExpression(smallModel, simpleRule)),
    EvaluationBenchmark('One rule, large model',
        () => executeExpression(largeModel, simpleRule)),
    EvaluationBenchmark('20 rules, one small model', () {
      for (final rule in ruleSet) {
        executeExpression(smallModel, rule);
      }
    }),
    EvaluationBenchmark('20 rules, one large model', () {
      for (final rule in ruleSet) {
        executeExpression(largeModel, rule);
      }
    }),
    EvaluationBenchmark('Deep dotted path, large model',
        () => executeExpression(largeModel, dottedRule)),
    EvaluationBenchmark('in() over model array',
        () => executeExpression(smallModel, membershipRule)),
    EvaluationBenchmark('in() over 101-entry model array',
        () => executeExpression(smallModel, largeMembershipRule)),
    EvaluationBenchmark('eq() of two model arrays',
        () => executeExpression(smallModel, arrayEqualityRule)),
    EvaluationBenchmark('Pre-parsed expression, small model',
        () => parsedSimpleRule.evaluate(smallModel)),
  ];

  for (final benchmark in benchmarks) {
    benchmark.report();
  }
}
