/// Locale-aware display formatting for canonical API strings (spec 01 D-01).
///
/// Parse and write paths keep the canonical form — dot decimals and
/// `yyyy-MM-dd` dates; only this display layer renders vi-VN's `dd/MM/yyyy`
/// dates and comma decimals. All math stays string-based.
library;

final RegExp _isoDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Renders a canonical `yyyy-MM-dd` date for the active locale.
///
/// vi-VN: `2026-08-20` → `20/08/2026`; other locales keep the canonical form.
/// Null or non-ISO input passes through so deliberate unknown states and
/// free-form demo values stay untouched.
String? formatDisplayDate(String? isoDate, String localeName) {
  if (isoDate == null) return null;
  if (!localeName.startsWith('vi')) return isoDate;
  final match = _isoDatePattern.firstMatch(isoDate);
  if (match == null) return isoDate;
  return '${match.group(3)}/${match.group(2)}/${match.group(1)}';
}

/// Renders a canonical dot decimal (`41.5`) with the locale's separator.
///
/// vi-VN uses the decimal comma (`41,5`); other locales keep the canonical
/// form. The value is never parsed to a binary double (D-01).
String formatDisplayDecimal(String canonical, String localeName) =>
    localeName.startsWith('vi')
    ? canonical.replaceAll('.', ',')
    : canonical;
