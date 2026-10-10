import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/format/decimal_format.dart';

/// D-01 (spec06): farm area converts between m² and ha with exact decimal
/// math — never through a binary double — and invalid input surfaces a
/// deliberate unknown instead of a fabricated number.
void main() {
  group('formatAreaHectares', () {
    test('converts whole square metres to hectares exactly', () {
      expect(formatAreaHectares('32000'), '3.2');
      expect(formatAreaHectares('10000'), '1');
      expect(formatAreaHectares('4000'), '0.4');
      expect(formatAreaHectares('1'), '0.0001');
      expect(formatAreaHectares('0'), '0');
    });

    test('keeps fractional precision without binary rounding', () {
      // NUMERIC(14,2) extreme: exact quotient, no double artifacts.
      expect(formatAreaHectares('999999999999.99'), '99999999.999999');
      expect(formatAreaHectares('12.34'), '0.001234');
      expect(formatAreaHectares('15000.50'), '1.50005');
    });

    test('returns null for missing or invalid input', () {
      expect(formatAreaHectares(null), isNull);
      expect(formatAreaHectares(''), isNull);
      expect(formatAreaHectares('abc'), isNull);
      expect(formatAreaHectares('-5'), isNull);
      expect(formatAreaHectares('1.2.3'), isNull);
    });
  });
}
