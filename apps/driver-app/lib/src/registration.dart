import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jolay_core/jolay_core.dart';

import 'auth.dart';
import 'data.dart';

class VehicleRegistration extends ConsumerStatefulWidget {
  const VehicleRegistration({super.key});
  @override
  ConsumerState<VehicleRegistration> createState() => _RegState();
}

class _RegState extends ConsumerState<VehicleRegistration> {
  final _form = GlobalKey<FormState>();
  final _brand = TextEditingController(),
      _model = TextEditingController(),
      _year = TextEditingController(),
      _color = TextEditingController(),
      _plate = TextEditingController();
  String _cat = 'ECONOMY';
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(apiProvider)
          .post(
            '/drivers/register',
            body: {
              'vehicle': {
                'brand': _brand.text.trim(),
                'model': _model.text.trim(),
                'year': int.parse(_year.text),
                'color': _color.text.trim(),
                'plate': _plate.text.trim(),
                'category': _cat,
              },
            },
          );
      ref.invalidate(driverMeProvider);
    } catch (e) {
      if (mounted) toast(context, ref, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _req(String? s) => (s == null || s.trim().isEmpty)
      ? ref.read(localeProvider).languageCode == 'en'
            ? 'Required'
            : tr(ref.read(localeProvider), 'val.name')
      : null;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppHeader(
        title: ref.t('driver.regTitle'),
        subtitle: ref.t('driver.regSubtitle'),
        showBack: false,
        actions: const [LanguageSelector(), SizedBox(width: 12)],
      ),
      body: Column(
        children: [
          Expanded(
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  const _Steps(current: 0),
                  const SizedBox(height: 24),
                  AppTextField(
                    key: const Key('v-brand'),
                    controller: _brand,
                    label: ref.t('driver.brand'),
                    textCapitalization: TextCapitalization.words,
                    validator: _req,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _model,
                    label: ref.t('driver.model'),
                    textCapitalization: TextCapitalization.words,
                    validator: _req,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _year,
                          keyboardType: TextInputType.number,
                          label: ref.t('driver.year'),
                          validator: (s) {
                            final y = int.tryParse(s ?? '');
                            return (y == null ||
                                    y < 1990 ||
                                    y > DateTime.now().year + 1)
                                ? ref.t('val.name')
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppTextField(
                          controller: _color,
                          label: ref.t('driver.color'),
                          validator: _req,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _plate,
                    textCapitalization: TextCapitalization.characters,
                    label: ref.t('driver.plate'),
                    validator: (s) =>
                        RegExp(r'^[A-Za-z0-9 -]{4,15}$').hasMatch(s ?? '')
                        ? null
                        : ref.t('val.name'),
                  ),
                  const SizedBox(height: 20),
                  Text(ref.t('driver.category'), style: t.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in const [
                        'ECONOMY',
                        'COMFORT',
                        'BUSINESS',
                        'XL',
                      ])
                        ChoiceChip(
                          key: Key('cat-$c'),
                          label: Text(c),
                          selected: _cat == c,
                          onSelected: (_) => setState(() => _cat = c),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: context.palette.surface,
              border: Border(top: BorderSide(color: context.palette.border)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: SafeArea(
              top: false,
              child: PrimaryButton(
                label: ref.t('btn.continue'),
                loading: _busy,
                onPressed: _submit,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Four-step onboarding progress: details → documents → review → ready.
class _Steps extends ConsumerWidget {
  final int current;
  const _Steps({required this.current});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final labels = [
      ref.t('driver.verifSubmitted'),
      ref.t('driver.verifDocs'),
      ref.t('driver.verifReview'),
      ref.t('driver.verifDone'),
    ];
    return Row(
      children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i <= current
                        ? (p.isDark ? p.accent : AppColors.midnight)
                        : p.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  labels[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    fontWeight: i == current
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: i == current ? p.textPrimary : p.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

const _docTypes = [
  'ID_CARD',
  'DRIVER_LICENSE',
  'VEHICLE_REGISTRATION',
  'INSURANCE',
  'PHOTO',
];

/// Checklist of required documents with upload. Used while under review and from Profile → Documents.
class DocumentsChecklist extends ConsumerStatefulWidget {
  const DocumentsChecklist({super.key});
  @override
  ConsumerState<DocumentsChecklist> createState() => _DocsState();
}

class _DocsState extends ConsumerState<DocumentsChecklist> {
  List<Map<String, dynamic>> _docs = [];
  bool _busy = false, _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await ref.read(apiProvider).get('/drivers/documents') as List;
      if (mounted) {
        setState(() {
          _docs = j.cast<Map<String, dynamic>>();
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _upload(String type) async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (f == null) return;
    setState(() => _busy = true);
    try {
      final form = FormData.fromMap({
        'type': type,
        'file': await MultipartFile.fromFile(f.path, filename: f.name),
      });
      await ref.read(apiProvider).post('/drivers/documents', body: form);
      await _load();
    } catch (e) {
      if (mounted) toast(context, ref, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SkeletonList(count: 5);
    return SettingsGroup(
      children: [
        for (final t in _docTypes)
          Builder(
            builder: (_) {
              final mine = _docs.where((d) => d['type'] == t).toList();
              final status = mine.isEmpty
                  ? null
                  : mine.last['status']?.toString();
              final (tone, label) = switch (status) {
                'APPROVED' => (
                  StatusTone.success,
                  ref.t('driver.docStatus.APPROVED'),
                ),
                'REJECTED' => (
                  StatusTone.error,
                  ref.t('driver.docStatus.REJECTED'),
                ),
                null => (StatusTone.neutral, ref.t('driver.docMissing')),
                _ => (StatusTone.warning, ref.t('driver.docStatus.PENDING')),
              };
              return SettingsRow(
                key: Key('doc-$t'),
                icon: status == null ? AppIcons.upload : AppIcons.document,
                title: ref.t('driver.docType.$t'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusBadge(label: label, tone: tone),
                    const SizedBox(width: 8),
                    _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            AppIcons.upload,
                            size: 20,
                            color: context.palette.textSecondary,
                          ),
                  ],
                ),
                onTap: _busy ? null : () => _upload(t),
              );
            },
          ),
      ],
    );
  }
}

class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppHeader(
      title: ref.t('driver.docs'),
      backLabel: ref.t('common.back'),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          ref.t('driver.uploadHint'),
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: context.palette.textSecondary),
        ),
        const SizedBox(height: 16),
        const DocumentsChecklist(),
      ],
    ),
  );
}

class VerificationStatus extends ConsumerWidget {
  final Map<String, dynamic> me;
  const VerificationStatus({super.key, required this.me});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = me['verification'] as String;
    final pending = v == 'PENDING';
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppHeader(
        title: ref.t('driver.docs'),
        showBack: false,
        actions: [
          AppIconButton(
            icon: AppIcons.refresh,
            tooltip: ref.t('btn.retry'),
            style: AppIconButtonStyle.outlined,
            onPressed: () => ref.invalidate(driverMeProvider),
          ),
          const SizedBox(width: 8),
          AppIconButton(
            icon: AppIcons.logout,
            tooltip: ref.t('btn.logout'),
            style: AppIconButtonStyle.outlined,
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _Steps(current: pending ? 2 : 1),
          const SizedBox(height: 20),
          AppCard(
            variant: pending
                ? AppCardVariant.outlined
                : AppCardVariant.outlined,
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: pending ? p.warningSoft : p.errorSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    pending ? AppIcons.hourglass : AppIcons.block,
                    color: pending ? p.warning : p.error,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pending
                            ? ref.t('driver.pending')
                            : ref.t('driver.rejected'),
                        style: t.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pending
                            ? ref.t('driver.pendingBody')
                            : (me['rejection_reason'] ?? '').toString(),
                        style: t.bodyMedium?.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(ref.t('driver.verifDocs'), style: t.titleMedium),
          const SizedBox(height: 4),
          Text(ref.t('driver.uploadHint'), style: t.bodySmall),
          const SizedBox(height: 12),
          const DocumentsChecklist(),
        ],
      ),
    );
  }
}
