import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light / dark / follow-system, persisted. Default: follow the system setting.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _k = 'jolay.themeMode';
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_k);
      final m = ThemeMode.values.where((e) => e.name == v);
      if (m.isNotEmpty) state = m.first;
    } catch (_) {
      /* storage unavailable: keep default */
    }
  }

  Future<void> set(ThemeMode m) async {
    state = m;
    try {
      await (await SharedPreferences.getInstance()).setString(_k, m.name);
    } catch (_) {}
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
