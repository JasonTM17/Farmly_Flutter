/// Exact decimal-string formatting for quantities and areas.
///
/// API quantities are canonical decimal strings (spec 01): UI must convert
/// with string math only — never parse to a binary double (D-01).
library;

final RegExp _decimalPattern = RegExp(r'^\d+(\.\d+)?$');

/// Formats a canonical decimal area in square metres as hectares.
///
/// `32000` → `3.2`, `1` → `0.0001`, `999999999999.99` → `99999999.999999`.
/// Returns null for null/invalid input so callers can show a deliberate
/// unknown state instead of a fabricated number.
String? formatAreaHectares(String? areaM2) {
  if (areaM2 == null || !_decimalPattern.hasMatch(areaM2)) return null;
  final dot = areaM2.indexOf('.');
  final intPart = dot < 0 ? areaM2 : areaM2.substring(0, dot);
  final fracPart = dot < 0 ? '' : areaM2.substring(dot + 1);

  // Dividing by 10000 shifts the decimal point left 4 places; scale the
  // fractional digits accordingly, then place the point with zero padding.
  final digits = intPart + fracPart;
  final scale = fracPart.length + 4;
  final padded = digits.padLeft(scale + 1, '0');
  final whole = padded.substring(0, padded.length - scale);
  var frac = padded.substring(padded.length - scale);

  frac = frac.replaceAll(RegExp(r'0+$'), '');
  final normalizedWhole = whole.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  return frac.isEmpty ? normalizedWhole : '$normalizedWhole.$frac';
}
