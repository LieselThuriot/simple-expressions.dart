# Conformance

Cross-language compatibility is specified and tested by the independent [simple-expressions-conformance](https://github.com/LieselThuriot/simple-expressions-conformance) repository.

The pinned `test/fixtures/conformance/` submodule supplies `spec/v1/cases.json`, which is executed by `test/conformance_test.dart`. Initialize it with `git submodule update --init --recursive`. The test reads the corpus in place and does not copy files from the submodule.

The conformance suite is the minimum shared test set. The additional local tests cover Dart-specific APIs and intentional port-specific semantics.

This implementation supports conformance specification v1. Numeric inputs must be finite numbers or finite JavaScript-compatible numeric strings; variadic numeric operators recursively flatten lists and reject active cycles. Equality is structural for lists and maps and cycle-safe, with already-visited identity pairs treated as equal. A null model root is passed through by the adapter rather than replaced with an empty map, although either root makes references missing.
