import 'package:flutter/material.dart';
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
    ref.listen(realtimeEventsProvider, (_, ev) { if (ev.value?.type == 'SUPPORT_MESSAGE') ref.invalidate(ticketsProvider); });
    return Scaffold(
      appBar: AppBar(title: Text(ref.t('profile.support'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _create(context, ref), backgroundColor: JolayColors.yellow, foregroundColor: JolayColors.midnight, icon: const Icon(Icons.add), label: Text(ref.t('support.new'))),
      body: t.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(message: ref.t('common.offline'), retryLabel: ref.t('btn.retry'), onRetry: () => ref.invalidate(ticketsProvider)),
        data: (l) => l.isEmpty ? Center(child: Text(ref.t('support.empty'), style: const TextStyle(color: JolayColors.textSecondary))) : ListView.separated(
          padding: const EdgeInsets.all(16), itemCount: l.length, separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => JolayCard(onTap: () => context.push('/support/${l[i]['id']}', extra: l[i]['subject']), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l[i]['subject'].toString(), style: const TextStyle(fontWeight: FontWeight.w800)), Text((l[i]['last_message'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JolayColors.textSecondary))])),
            if ((l[i]['unread'] as num) > 0) CircleAvatar(radius: 11, backgroundColor: JolayColors.error, child: Text('${l[i]['unread']}', style: const TextStyle(color: Colors.white, fontSize: 12))),
          ])),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final subject = TextEditingController(), msg = TextEditingController();
    String category = 'RIDE';
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
      title: Text(ref.t('support.new')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: category, items: [for (final k in ['RIDE', 'PAYMENT', 'SAFETY', 'OTHER']) DropdownMenuItem(value: k, child: Text(k))], onChanged: (x) => set(() => category = x ?? 'RIDE')),
        const SizedBox(height: 10), TextField(controller: subject, decoration: InputDecoration(labelText: ref.t('support.subject'))),
        const SizedBox(height: 10), TextField(controller: msg, maxLines: 3, decoration: InputDecoration(labelText: ref.t('support.message'))),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(ref.t('btn.cancel'))), FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), child: Text(ref.t('btn.send')))],
    )));
    if (ok != true || subject.text.trim().isEmpty || msg.text.trim().isEmpty) return;
    try {
      await ref.read(apiProvider).post('/support/tickets', body: {'category': category, 'subject': subject.text.trim(), 'message': msg.text.trim()});
      ref.invalidate(ticketsProvider);
    } catch (e) { if (context.mounted) showError(context, ref, e); }
  }
}

class SupportChatScreen extends ConsumerStatefulWidget {
  final String ticketId, subject;
  const SupportChatScreen({super.key, required this.ticketId, required this.subject});
  @override
  ConsumerState<SupportChatScreen> createState() => _ChatState();
}

class _ChatState extends ConsumerState<SupportChatScreen> {
  List<Map<String, dynamic>> _msgs = [];
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try { final j = await ref.read(apiProvider).get('/support/tickets/${widget.ticketId}/messages') as List; if (mounted) setState(() => _msgs = j.cast<Map<String, dynamic>>()); } catch (_) {}
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try { await ref.read(apiProvider).post('/support/tickets/${widget.ticketId}/messages', body: {'body': body}); _text.clear(); await _load(); }
    catch (e) { if (mounted) showError(context, ref, e); } finally { if (mounted) setState(() => _sending = false); }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeEventsProvider, (_, ev) { if (ev.value?.type == 'SUPPORT_MESSAGE' || ev.value?.type == 'CONNECTED') _load(); });
    return Scaffold(
      appBar: AppBar(title: Text(widget.subject)),
      body: Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          for (final m in _msgs) Align(
            alignment: m['from_agent'] == true ? Alignment.centerLeft : Alignment.centerRight,
            child: Container(margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.all(12), constraints: const BoxConstraints(maxWidth: 280),
              decoration: BoxDecoration(color: m['from_agent'] == true ? Colors.white : JolayColors.yellow, borderRadius: BorderRadius.circular(14), border: Border.all(color: JolayColors.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(m['body'].toString()), const SizedBox(height: 4),
                Text(formatDateTime(m['created_at']?.toString()) + (m['from_agent'] != true && m['read_at'] != null ? ' ✓✓' : ''), style: const TextStyle(fontSize: 10, color: JolayColors.textSecondary))])),
          ),
        ])),
        SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          Expanded(child: TextField(controller: _text, decoration: InputDecoration(hintText: ref.t('support.write')))), const SizedBox(width: 8),
          IconButton.filled(onPressed: _sending ? null : _send, icon: const Icon(Icons.send), style: IconButton.styleFrom(backgroundColor: JolayColors.yellow, foregroundColor: JolayColors.midnight)),
        ]))),
      ]),
    );
  }
}
