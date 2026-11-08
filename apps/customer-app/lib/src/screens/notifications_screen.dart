import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jolay_core/jolay_core.dart';

/// The user's persisted notifications (`GET /notifications`). Failures simply leave the list empty for the badge.
final notificationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final j =
          await ref
                  .read(apiProvider)
                  .get('/notifications', query: {'limit': 50})
              as List;
      return j.cast<Map<String, dynamic>>();
    });

int unreadCount(List<Map<String, dynamic>>? l) =>
    l == null ? 0 : l.where((n) => n['read_at'] == null).length;

/// The backend sends typed events with structured payloads, not prose. Each known type maps to a localized line;
/// unknown types fall back to a neutral "Update" so nothing is invented.
IconData _iconFor(String type) {
  if (type.startsWith('RIDE') || type.startsWith('DRIVER')) {
    return AppIcons.ride;
  }
  if (type.startsWith('STORE')) return AppIcons.store;
  if (type.startsWith('DELIVERY')) return AppIcons.send;
  if (type.startsWith('PAYMENT')) return AppIcons.wallet;
  if (type.startsWith('SUPPORT')) return AppIcons.support;
  if (type.startsWith('REFERRAL')) return AppIcons.gift;
  return AppIcons.info;
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(notificationsProvider);
    final p = context.palette;
    return Scaffold(
      appBar: AppHeader(
        title: ref.t('notif.title'),
        backLabel: ref.t('common.back'),
      ),
      body: data.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: SkeletonList(count: 5),
        ),
        error: (_, _) => ErrorState(
          message: ref.t('common.offline'),
          retryLabel: ref.t('btn.retry'),
          onRetry: () => ref.invalidate(notificationsProvider),
        ),
        data: (items) => items.isEmpty
            ? EmptyState(
                icon: AppIcons.history,
                title: ref.t('notif.empty'),
                message: ref.t('notif.emptyBody'),
              )
            : RefreshIndicator(
                onRefresh: () async =>
                    ref.refresh(notificationsProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final n = items[i];
                    final type = n['type'].toString();
                    final unread = n['read_at'] == null;
                    final key = 'notif.$type';
                    final text = tr(ref.read(localeProvider), key) == key
                        ? tr(ref.read(localeProvider), 'notif.generic')
                        : tr(ref.read(localeProvider), key);
                    return AppCard(
                      selected: false,
                      padding: const EdgeInsets.all(14),
                      onTap: () async {
                        if (unread) {
                          try {
                            await ref
                                .read(apiProvider)
                                .post('/notifications/${n['id']}/read');
                            ref.invalidate(notificationsProvider);
                          } catch (_) {}
                        }
                        final payload = n['payload'];
                        final rideId = payload is Map
                            ? payload['rideId']
                            : null;
                        if (rideId != null && context.mounted) {
                          context.push('/ride/$rideId');
                        }
                      },
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: unread ? p.accent : p.divider,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _iconFor(type),
                              size: AppIconSize.md,
                              color: unread ? p.onAccent : p.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  text,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        fontWeight: unread
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                ),
                                Text(
                                  formatDateTime(n['created_at']?.toString()),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (unread)
                            Semantics(
                              label: '•',
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: p.accent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.midnight,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
