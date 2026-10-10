import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable form fields named in spec 02 §4. Both keep input shaping here and
/// leave semantic validation (positive amounts, past/future windows) to the
/// caller, which owns the exact string contract (FarmlyDecimal / ISO dates).

/// Exact-decimal numeric input (spec 02 §4 [DecimalField]): decimal keyboard,
/// at most one dot/comma separator, no locale grouping so the exact decimal
/// string survives typing. Used by the harvest form.
class DecimalField extends StatelessWidget {
  const DecimalField({
    required this.controller,
    this.labelText,
    this.hintText,
    this.errorText,
    this.helperText,
    this.helperStyle,
    this.autofocus = false,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String? labelText;
  final String? hintText;
  final String? errorText;
  final String? helperText;
  final TextStyle? helperStyle;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [_DecimalInputFormatter()],
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        errorText: errorText,
        helperText: helperText,
        helperStyle: helperStyle,
      ),
      onSubmitted: onSubmitted,
    );
  }
}

class _DecimalInputFormatter extends TextInputFormatter {
  static final RegExp _pattern = RegExp(r'^\d*([.,]\d*)?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty || _pattern.hasMatch(text)) return newValue;
    return oldValue;
  }
}

/// ISO local-date input, `yyyy-MM-dd` (spec 02 §4 [LocalDateField]): keeps
/// the canonical date string the API and records use. Shape validation only;
/// callers validate the calendar window.
class LocalDateField extends StatelessWidget {
  const LocalDateField({
    required this.controller,
    this.labelText,
    this.hintText,
    this.errorText,
    this.helperText,
    this.helperStyle,
    this.autofocus = false,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String? labelText;
  final String? hintText;
  final String? errorText;
  final String? helperText;
  final TextStyle? helperStyle;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.datetime,
      inputFormatters: [_IsoDateInputFormatter()],
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText ?? '2026-10-06',
        errorText: errorText,
        helperText: helperText,
        helperStyle: helperStyle,
      ),
      onSubmitted: onSubmitted,
    );
  }
}

class _IsoDateInputFormatter extends TextInputFormatter {
  static final RegExp _pattern = RegExp(r'^\d{0,4}(-\d{0,2}(-\d{0,2})?)?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty || _pattern.hasMatch(text)) return newValue;
    return oldValue;
  }
}
