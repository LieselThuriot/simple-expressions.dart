# Conformance

Cross-language compatibility is specified and tested by the independent [simple-expressions-conformance](https://github.com/LieselThuriot/simple-expressions-conformance) repository.

The pinned `test/fixtures/conformance/` submodule supplies `spec/v1/cases.json`, which is executed by `test/conformance_test.dart`. Initialize it with `git submodule update --init --recursive`. The test reads the corpus in place and does not copy files from the submodule.

The conformance suite is the minimum shared test set. Additional local tests cover Dart APIs and behavior that JSON fixtures cannot represent, including nonfinite values, signed zero, shared references, cyclic models, and the complete Unicode whitespace set.

This implementation supports conformance specification v1 and the agreed portable semantics. Strict numeric operators accept finite numbers and finite decimal/exponent strings only, evaluate and flatten all variadic arguments before leaf conversion, reject active list cycles, and require every result to remain finite. Rounding accepts precision 0 through 308 and uses decimal ties away from zero. Scalar numeric results normalize negative zero, while nested values in live model containers are not traversed and can retain it. Equality and comparison use explicit portable rules rather than host-language coercion; structural list/map equality is cycle-safe with already-visited identity pairs treated as equal. Expression parsing, tokenization, trimming, and numeric conversion share the specified Unicode White_Space set, excluding U+FEFF. Text conversion rejects active cyclic lists. A null model root passes through the adapter rather than being replaced with an empty map, although either root makes references missing.
