import 'package:intl/intl.dart' show NumberFormat;

/// Money arrives from the backend as decimal strings; it is only formatted here, never computed on the client.
String formatKzt(Object? v) {
  if (v == null) return '—';
  final d = double.tryParse(v.toString());
  if (d == null) return '—';
  return '${NumberFormat.decimalPattern('ru').format(d.round())} ₸';
}

/// Converts a UTC ISO timestamp to Asia/Almaty (UTC+5, no DST) for display.
DateTime toAlmaty(String iso) =>
    DateTime.parse(iso).toUtc().add(const Duration(hours: 5));

String formatDateTime(String? iso) {
  if (iso == null) return '—';
  final t = toAlmaty(iso);
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(t.day)}.${p(t.month)}.${t.year} ${p(t.hour)}:${p(t.minute)}';
}

String formatDuration(int seconds) {
  final m = (seconds / 60).round();
  return m < 1 ? '<1' : '$m';
}

String formatKm(int meters) => (meters / 1000).toStringAsFixed(1);
