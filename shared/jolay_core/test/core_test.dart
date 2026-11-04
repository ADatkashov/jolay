import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jolay_core/jolay_core.dart';

void main() {
  test('kk, ru and en define exactly the same keys (no untranslated strings)', () {
    final en = stringKeys('en');
    expect(stringKeys('kk').difference(en), isEmpty, reason: 'keys in kk missing from en');
    expect(en.difference(stringKeys('kk')), isEmpty, reason: 'keys in en missing from kk');
    expect(en.difference(stringKeys('ru')), isEmpty, reason: 'keys in en missing from ru');
    expect(stringKeys('ru').difference(en), isEmpty);
  });

  test('translations resolve per locale and fall back safely', () {
    expect(tr(const Locale('ru'), 'btn.login'), 'Войти');
    expect(tr(const Locale('kk'), 'btn.login'), 'Кіру');
    expect(tr(const Locale('en'), 'btn.login'), 'Log in');
    expect(tr(const Locale('de'), 'btn.login'), 'Log in'); // unsupported -> English
    expect(tr(const Locale('en'), 'no.such.key'), 'no.such.key');
  });

  test('backend error codes are localized, unknown codes get a generic message', () {
    expect(errorText(const Locale('ru'), 'insufficient_funds'), contains('кошельке'));
    expect(errorText(const Locale('en'), 'something_new'), 'Something went wrong');
  });

  group('validators', () {
    test('phone formats are normalised like the backend', () {
      expect(Validators.normalizePhone('8 (701) 222-33-44'), '+77012223344');
      expect(Validators.normalizePhone('77012223344'), '+77012223344');
      expect(Validators.phone('123'), 'val.phone');
      expect(Validators.phone('+77012223344'), isNull);
    });
    test('password policy', () {
      expect(Validators.password('short1'), 'val.password');
      expect(Validators.password('allletters'), 'val.password');
      expect(Validators.password('Secret123'), isNull);
    });
    test('name, email, confirm', () {
      expect(Validators.name('A'), 'val.name');
      expect(Validators.email('bad'), 'val.email');
      expect(Validators.email(''), isNull);
      expect(Validators.confirm('a', 'b'), 'val.confirm');
    });
  });

  group('formatting', () {
    test('tenge amounts', () {
      expect(formatKzt('1340.00'), contains('1'));
      expect(formatKzt('1340.00'), endsWith('₸'));
      expect(formatKzt(null), '—');
    });
    test('timestamps are shown in Asia/Almaty (UTC+5)', () {
      expect(formatDateTime('2026-11-04T10:30:00Z'), '04.11.2026 15:30');
    });
  });

  test('theme uses the JOLAY palette', () {
    final t = jolayTheme();
    expect(t.colorScheme.primary, JolayColors.yellow);
    expect(t.scaffoldBackgroundColor, JolayColors.cloud);
  });
}
