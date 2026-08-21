part of 'simple_expressions_impl.dart';

const int _plainNotationMinExponent = -6;
const int _plainNotationMaxExponent = 21;

/// Renders a double as its shortest round-trip decimal, using plain notation for
/// magnitudes in `[1e-6, 1e21)` and lowercase exponent notation outside that range.
String _formatNumber(double value) {
  if (value.isNaN) return 'NaN';
  if (value == double.infinity) return 'Infinity';
  if (value == double.negativeInfinity) return '-Infinity';
  if (value == 0) return '0';

  var text = value.toStringAsExponential();
  final negative = text.startsWith('-');
  if (negative) text = text.substring(1);

  final separator = text.indexOf('e');
  // toStringAsExponential normalises to a single leading digit, so the
  // exponent is already the decimal exponent of that digit.
  final exponent = int.parse(text.substring(separator + 1));
  final digits = text.substring(0, separator).replaceFirst('.', '');

  final formatted = exponent >= _plainNotationMinExponent &&
          exponent < _plainNotationMaxExponent
      ? _toPlainNotation(digits, exponent)
      : _toExponentNotation(digits, exponent);

  return negative ? '-$formatted' : formatted;
}

String _toPlainNotation(String digits, int exponent) {
  if (exponent < 0) {
    return '0.${'0' * (-exponent - 1)}$digits';
  }
  if (exponent >= digits.length - 1) {
    return digits + '0' * (exponent - digits.length + 1);
  }
  return '${digits.substring(0, exponent + 1)}.${digits.substring(exponent + 1)}';
}

String _toExponentNotation(String digits, int exponent) {
  final mantissa = digits.length == 1
      ? digits
      : '${digits.substring(0, 1)}.${digits.substring(1)}';
  return '${mantissa}e${exponent < 0 ? '-' : '+'}${exponent.abs()}';
}
