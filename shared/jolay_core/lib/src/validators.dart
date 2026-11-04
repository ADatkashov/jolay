/// Client-side validators. The backend validates everything again; these only give instant feedback.
class Validators {
  /// Returns an error key (see strings) or null.
  static String? name(String? v) => (v == null || v.trim().length < 2) ? 'val.name' : null;

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return null; // optional
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()) ? null : 'val.email';
  }

  static String? password(String? v) {
    if (v == null || v.length < 8 || !RegExp(r'\p{L}', unicode: true).hasMatch(v) || !RegExp(r'\d').hasMatch(v)) return 'val.password';
    return null;
  }

  static String? confirm(String? v, String other) => v == other ? null : 'val.confirm';

  /// Kazakhstan/international phone: accepts +7XXXXXXXXXX, 8XXXXXXXXXX, 7XXXXXXXXXX with spaces/dashes.
  static String? phone(String? v) {
    try { normalizePhone(v ?? ''); return null; } catch (_) { return 'val.phone'; }
  }

  static String normalizePhone(String raw) {
    var p = raw.replaceAll(RegExp(r'[\s()\-]'), '');
    if (RegExp(r'^8\d{10}$').hasMatch(p)) {
      p = '+7${p.substring(1)}';
    } else if (RegExp(r'^7\d{10}$').hasMatch(p)) {
      p = '+$p';
    }
    if (!RegExp(r'^\+[1-9]\d{9,14}$').hasMatch(p)) throw const FormatException('phone');
    return p;
  }
}
