import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jolay_core/jolay_core.dart';

/// Shows a legal text (TERMS / PRIVACY / ABOUT) published by SUPER_ADMIN. The app contains no built-in legal text:
/// until counsel's version is published for the user's language it says so honestly.
class LegalScreen extends ConsumerStatefulWidget {
  final String type; // TERMS | PRIVACY | ABOUT
  const LegalScreen({super.key, required this.type});
  @override
  ConsumerState<LegalScreen> createState() => _LegalState();
}

class _LegalState extends ConsumerState<LegalScreen> {
  String? _body, _version;
  bool _loading = true, _missing = false, _failed = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _failed = false; _missing = false; });
    try {
      final j = await ref.read(apiProvider).get('/catalog/legal/${widget.type}', query: {'lang': ref.read(localeProvider).languageCode}, auth: false) as Map<String, dynamic>;
      if (mounted) setState(() { _body = j['body'] as String; _version = j['version'].toString(); _loading = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _loading = false; _missing = e.code == 'legal_not_published'; _failed = !_missing; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.type) { 'TERMS' => ref.t('legal.terms'), 'PRIVACY' => ref.t('legal.privacy'), _ => ref.t('legal.about') };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? ErrorView(message: ref.t('common.offline'), retryLabel: ref.t('btn.retry'), onRetry: _load)
              : _missing
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(ref.t('legal.notPublished'), key: const Key('legal-missing'), textAlign: TextAlign.center, style: const TextStyle(color: JolayColors.textSecondary))))
                  : ListView(padding: const EdgeInsets.all(20), children: [
                      Text('${ref.t('legal.version')} $_version', style: const TextStyle(color: JolayColors.textSecondary, fontSize: 12)),
                      const SizedBox(height: 12),
                      SelectableText(_body!, key: const Key('legal-body')),
                    ]),
    );
  }
}
