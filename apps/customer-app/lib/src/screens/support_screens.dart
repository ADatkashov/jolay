import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jolay_core/jolay_core.dart';

import '../data/providers.dart';
import 'common.dart';

class SupportListScreen extends ConsumerWidget {
  const SupportListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(ticketsProvider);
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    ref.listen(realtimeEventsProvider, (_, ev) {
      if (ev.value?.type == 'SUPPORT_MESSAGE') ref.invalidate(ticketsProvider);
    });
    return Scaffold(
      appBar: AppHeader(
        title: ref.t('profile.support'),
        backLabel: ref.t('common.back'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonR),
        icon: const Icon(AppIcons.add),
        label: Text(ref.t('support.new'), style: tt.labelLarge),
      ),
      body: t.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: SkeletonList(count: 4),
        ),
        error: (e, _) => ErrorState(
          message: ref.t('common.offline'),
          retryLabel: ref.t('btn.retry'),
          onRetry: () => ref.invalidate(ticketsProvider),
        ),
        data: (l) => l.isEmpty
            ? EmptyState(icon: AppIcons.support, title: ref.t('support.empty'))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                itemCount: l.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => AppCard(
                  onTap: () => context.push(
                    '/support/${l[i]['id']}',
                    extra: l[i]['subject'],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: p.divider,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(AppIcons.message, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l[i]['subject'].toString(),
                              style: tt.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              (l[i]['last_message'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if ((l[i]['unread'] as num) > 0)
                        Semantics(
                          label: '${l[i]['unread']}',
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 24),
                            height: 24,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: p.accent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${l[i]['unread']}',
                              style: tt.labelMedium?.copyWith(
                                color: p.onAccent,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final subject = TextEditingController(), msg = TextEditingController();
    String category = 'RIDE';
    final ok = await showAppBottomSheet<bool>(
      context,
      title: ref.t('support.new'),
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: category,
              items: [
                for (final k in ['RIDE', 'PAYMENT', 'SAFETY', 'OTHER'])
                  DropdownMenuItem(value: k, child: Text(k)),
              ],
              onChanged: (x) => set(() => category = x ?? 'RIDE'),
            ),
            const SizedBox(height: 12),
            AppTextField(controller: subject, label: ref.t('support.subject')),
            const SizedBox(height: 12),
            AppTextField(
              controller: msg,
              maxLines: 4,
              label: ref.t('support.message'),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: ref.t('btn.send'),
              onPressed: () => Navigator.pop(c, true),
            ),
          ],
        ),
      ),
    );
    if (ok != true || subject.text.trim().isEmpty || msg.text.trim().isEmpty) {
      return;
    }
    try {
      await ref
          .read(apiProvider)
          .post(
            '/support/tickets',
            body: {
              'category': category,
              'subject': subject.text.trim(),
              'message': msg.text.trim(),
            },
          );
      ref.invalidate(ticketsProvider);
    } catch (e) {
      if (context.mounted) showError(context, ref, e);
    }
  }
}

class SupportChatScreen extends ConsumerStatefulWidget {
  final String ticketId, subject;
  const SupportChatScreen({
    super.key,
    required this.ticketId,
    required this.subject,
  });
  @override
  ConsumerState<SupportChatScreen> createState() => _ChatState();
}

class _ChatState extends ConsumerState<SupportChatScreen> {
  List<Map<String, dynamic>> _msgs = [];
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j =
          await ref
                  .read(apiProvider)
                  .get('/support/tickets/${widget.ticketId}/messages')
              as List;
      if (mounted) setState(() => _msgs = j.cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(apiProvider)
          .post(
            '/support/tickets/${widget.ticketId}/messages',
            body: {'body': body},
          );
      _text.clear();
      await _load();
    } catch (e) {
      if (mounted) showError(context, ref, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeEventsProvider, (_, ev) {
      if (ev.value?.type == 'SUPPORT_MESSAGE' ||
          ev.value?.type == 'CONNECTED') {
        _load();
      }
    });
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppHeader(title: widget.subject, backLabel: ref.t('common.back')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final m in _msgs)
                  Align(
                    alignment: m['from_agent'] == true
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      constraints: const BoxConstraints(maxWidth: 300),
                      decoration: BoxDecoration(
                        color: m['from_agent'] == true ? p.surface : p.accent,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: m['from_agent'] == true
                              ? p.border
                              : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            m['body'].toString(),
                            style: t.bodyMedium?.copyWith(
                              color: m['from_agent'] == true
                                  ? p.textPrimary
                                  : p.onAccent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatDateTime(m['created_at']?.toString()) +
                                (m['from_agent'] != true && m['read_at'] != null
                                    ? ' ✓✓'
                                    : ''),
                            style: t.bodySmall?.copyWith(
                              fontSize: 10,
                              color: m['from_agent'] == true
                                  ? p.textSecondary
                                  : p.onAccent.withValues(alpha: .7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              border: Border(top: BorderSide(color: p.border)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _text,
                      hint: ref.t('support.write'),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AppIconButton(
                    icon: Icons.send_rounded,
                    tooltip: ref.t('btn.send'),
                    style: AppIconButtonStyle.filled,
                    onPressed: _sending ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Trusted contacts who get an SMS with a live trip link when the customer presses SOS (up to 3).
class EmergencyContactsScreen extends ConsumerWidget {
  const EmergencyContactsScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController(),
        phone = TextEditingController(text: '+7 ');
    final form = GlobalKey<FormState>();
    final ok = await showAppBottomSheet<bool>(
      context,
      title: ref.t('profile.contacts'),
      builder: (c) => Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              key: const Key('contact-name'),
              controller: name,
              label: ref.t('contacts.name'),
              prefixIcon: AppIcons.person,
              validator: v(ref, Validators.name),
            ),
            const SizedBox(height: 12),
            PhoneField(fieldKey: const Key('contact-phone'), controller: phone),
            const SizedBox(height: 20),
            PrimaryButton(
              key: const Key('contact-save'),
              label: ref.t('btn.save'),
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(c, true);
              },
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(apiProvider)
          .post(
            '/customers/me/emergency-contacts',
            body: {
              'name': name.text.trim(),
              'phone': Validators.normalizePhone(phone.text),
            },
          );
      ref.invalidate(emergencyContactsProvider);
    } catch (e) {
      if (context.mounted) showError(context, ref, e);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, String id) async {
    try {
      await ref
          .read(apiProvider)
          .delete('/customers/me/emergency-contacts/$id');
      ref.invalidate(emergencyContactsProvider);
    } catch (e) {
      if (context.mounted) showError(context, ref, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(emergencyContactsProvider);
    final p = context.palette;
    return Scaffold(
      appBar: AppHeader(
        title: ref.t('profile.contacts'),
        backLabel: ref.t('common.back'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('contact-add'),
        onPressed: () => _add(context, ref),
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonR),
        icon: const Icon(AppIcons.add),
        label: Text(
          ref.t('contacts.add'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
      body: c.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: SkeletonList(count: 3),
        ),
        error: (e, _) => ErrorState(
          message: ref.t('common.offline'),
          retryLabel: ref.t('btn.retry'),
          onRetry: () => ref.invalidate(emergencyContactsProvider),
        ),
        data: (l) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.shield, size: 18, color: p.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ref.t('contacts.hint'),
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: p.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (l.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: EmptyState(
                  icon: AppIcons.shield,
                  title: ref.t('contacts.empty'),
                ),
              ),
            for (final x in l)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AddressCard(
                  key: Key('contact-${x['id']}'),
                  title: x['name'].toString(),
                  subtitle: x['phone'].toString(),
                  icon: AppIcons.shield,
                  trailing: IconButton(
                    tooltip: ref.t('btn.delete'),
                    icon: const Icon(AppIcons.delete),
                    onPressed: () => _remove(context, ref, x['id'].toString()),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Personal invite code and referral statistics. The bonus is paid by the backend only when the programme is switched on.
class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(referralProvider);
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppHeader(
        title: ref.t('profile.invite'),
        backLabel: ref.t('common.back'),
      ),
      body: r.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: SkeletonLoader(height: 120, radius: 18),
        ),
        error: (e, _) => ErrorState(
          message: ref.t('common.offline'),
          retryLabel: ref.t('btn.retry'),
          onRetry: () => ref.invalidate(referralProvider),
        ),
        data: (d) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: p.accent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(AppIcons.gift, size: 32, color: p.onAccent),
            ),
            const SizedBox(height: 16),
            Text(ref.t('referral.title'), style: t.headlineMedium),
            const SizedBox(height: 8),
            Text(
              ref.t('referral.body'),
              style: t.bodyLarge?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 24),
            AppCard(
              variant: AppCardVariant.inverse,
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ref.t('referral.yourCode'),
                          style: t.bodySmall?.copyWith(color: Colors.white70),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          d['code'].toString(),
                          key: const Key('referral-code'),
                          style: t.headlineSmall?.copyWith(
                            color: AppColors.yellow,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppButton(
                    key: const Key('referral-copy'),
                    label: ref.t('referral.copy'),
                    icon: Icons.copy_rounded,
                    expand: false,
                    size: AppButtonSize.medium,
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: d['code'].toString()),
                      );
                      if (context.mounted) {
                        showAppToast(
                          context,
                          ref.t('referral.copied'),
                          type: AppToastType.success,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppCard(
                    child: Column(
                      children: [
                        Text('${d['invited']}', style: t.headlineMedium),
                        Text(ref.t('referral.invited'), style: t.bodySmall),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppCard(
                    child: Column(
                      children: [
                        Text('${d['rewarded']}', style: t.headlineMedium),
                        Text(ref.t('referral.rewarded'), style: t.bodySmall),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (d['enabled'] != true)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(AppIcons.info, size: 16, color: p.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ref.t('referral.off'),
                        key: const Key('referral-off'),
                        style: t.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
