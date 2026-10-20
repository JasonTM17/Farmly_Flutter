import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

bool _timeZonesInitialized = false;

/// Formats the farm's civil date for an instant, using the IANA timezone from
/// the bootstrapped farm row. Callers must not fall back to device-local time.
String farmlyTaskCivilDateAtUtc(DateTime instant, String timezoneName) {
  final farmTime = farmlyTaskDateTimeAtUtc(instant, timezoneName);
  return _formatFarmlyDate(farmTime.year, farmTime.month, farmTime.day);
}

/// Converts an instant to the farm's IANA timezone without using the device
/// timezone. Returned [DateTime] retains the farm-local calendar fields.
DateTime farmlyTaskDateTimeAtUtc(DateTime instant, String timezoneName) {
  if (timezoneName.trim().isEmpty) {
    throw ArgumentError.value(
      timezoneName,
      'timezoneName',
      'must not be empty',
    );
  }
  if (!_timeZonesInitialized) {
    timezone_data.initializeTimeZones();
    _timeZonesInitialized = true;
  }
  try {
    return timezone.TZDateTime.from(
      instant.toUtc(),
      timezone.getLocation(timezoneName),
    );
  } on Object {
    throw FormatException('Unsupported farm timezone: $timezoneName');
  }
}

/// Returns whether a template is scheduled for [occurrenceDate]. Weekday
/// numbering matches PostgreSQL DOW: Sunday=0 through Saturday=6.
bool farmlyTaskScheduleIncludesDate({
  required String frequency,
  required List<int> daysOfWeek,
  required String? startsOn,
  required String? endsOn,
  required String occurrenceDate,
}) {
  final occurrence = _parseFarmlyDate(occurrenceDate);
  if (occurrence == null ||
      !farmlyTaskDateWithinWindow(
        startsOn: startsOn,
        endsOn: endsOn,
        occurrenceDate: occurrenceDate,
      )) {
    return false;
  }

  if (frequency == 'daily') return daysOfWeek.isEmpty;
  if (frequency != 'weekly' ||
      daysOfWeek.isEmpty ||
      daysOfWeek.length > 7 ||
      daysOfWeek.any((day) => day < 0 || day > 6)) {
    return false;
  }
  return daysOfWeek.contains(occurrence.weekday % 7);
}

/// Returns whether [occurrenceDate] falls within a template's inclusive civil
/// date window. Invalid or non-canonical dates fail closed.
bool farmlyTaskDateWithinWindow({
  required String? startsOn,
  required String? endsOn,
  required String occurrenceDate,
}) {
  final occurrence = _parseFarmlyDate(occurrenceDate);
  final start = _parseFarmlyDate(startsOn);
  if (occurrence == null || start == null || occurrence.isBefore(start)) {
    return false;
  }
  final end = endsOn == null ? null : _parseFarmlyDate(endsOn);
  return endsOn == null || (end != null && !occurrence.isAfter(end));
}

/// Mirrors the kernel's `md5('taskocc:farm:template:date:slot')` UUID
/// formatting, including the fixed version-5 and RFC variant nibbles used by
/// the SQL kernel. Server-returned occurrence slots are passed through
/// unchanged after surrounding whitespace is removed, matching PostgreSQL
/// `btrim`.
String farmlyTaskOccurrenceResourceId({
  required String farmId,
  required String templateId,
  required String occurrenceDate,
  required String slot,
}) {
  final farm = _canonicalUuid('farmId', farmId);
  final template = _canonicalUuid('templateId', templateId);
  final date = _parseFarmlyDate(occurrenceDate);
  if (date == null ||
      _formatFarmlyDate(date.year, date.month, date.day) != occurrenceDate) {
    throw ArgumentError.value(
      occurrenceDate,
      'occurrenceDate',
      'must be YYYY-MM-DD',
    );
  }
  final canonicalSlot = slot.trim();
  if (canonicalSlot.isEmpty || canonicalSlot.length > 40) {
    throw ArgumentError.value(slot, 'slot', 'must contain 1 to 40 characters');
  }

  final hash = md5
      .convert(
        utf8.encode('taskocc:$farm:$template:$occurrenceDate:$canonicalSlot'),
      )
      .toString();
  return '${hash.substring(0, 8)}-${hash.substring(8, 12)}-'
      '5${hash.substring(13, 16)}-8${hash.substring(17, 20)}-'
      '${hash.substring(20, 32)}';
}

String _canonicalUuid(String field, String value) {
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value)) {
    throw ArgumentError.value(value, field, 'must be a UUID');
  }
  return value.toLowerCase();
}

DateTime? _parseFarmlyDate(String? value) {
  if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return null;
  }
  try {
    final date = DateTime.parse('${value}T00:00:00Z');
    if (_formatFarmlyDate(date.year, date.month, date.day) != value) {
      return null;
    }
    return date;
  } on FormatException {
    return null;
  }
}

String _formatFarmlyDate(int year, int month, int day) =>
    '${year.toString().padLeft(4, '0')}-'
    '${month.toString().padLeft(2, '0')}-'
    '${day.toString().padLeft(2, '0')}';
