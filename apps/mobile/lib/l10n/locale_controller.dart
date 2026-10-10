import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App locale: defaults to vi-VN (spec 01); the profile language switch sets
/// `en`. Tests may override the provider to pin a locale.
class FarmlyLocaleController extends Notifier<Locale> {
  FarmlyLocaleController([this._initial = const Locale('vi')]);

  final Locale _initial;

  @override
  Locale build() => _initial;

  void setLocale(Locale locale) => state = locale;
}

final farmlyLocaleProvider =
    NotifierProvider<FarmlyLocaleController, Locale>(FarmlyLocaleController.new);
