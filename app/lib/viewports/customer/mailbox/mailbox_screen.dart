import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/mailbox_message.dart';
import '../../../core/theme/theme_scope.dart';
import '../../../core/theme/typography.dart';
import '../../widgets/app_scope.dart';
import '../../widgets/empty_state.dart';

/// Anti-spam communication box. Offers and notices only ever arrive here;
/// nothing is emailed.
class MailboxScreen extends StatefulWidget {
  const MailboxScreen({super.key});

  @override
  State<MailboxScreen> createState() => _MailboxScreenState();
}

class _MailboxScreenState extends State<MailboxScreen> {
  Future<List<MailboxMessage>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<MailboxMessage>> _load() async {
    final scope = AppScope.of(context);
    if (!scope.session.isSignedIn) return const [];
    final rows = await scope.db
        .from('user_inapp_mailbox')
        .select('id, kind, title, body, vendor_id, payload, read_at, created_at, expires_at, vendors(name)')
        .or('expires_at.is.null,expires_at.gt.${DateTime.now().toUtc().toIso8601String()}')
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(MailboxMessage.fromJson).toList(growable: false);
  }

  Future<void> _markRead(MailboxMessage m) async {
    if (m.isRead) return;
    await AppScope.of(context).db
        .from('user_inapp_mailbox')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', m.id);
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('MAILBOX'),
        actions: [
          IconButton(
            tooltip: 'Preferences',
            onPressed: () => context.push('/mailbox/preferences'),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: scope.session,
        builder: (context, _) {
          if (!scope.session.isSignedIn) {
            return EmptyState(
              icon: Icons.mail_lock_outlined,
              title: 'SIGN IN TO GET LOCAL OFFERS',
              body: 'Deals and notices from nearby vendors land here, never in your email.',
              action: FilledButton(onPressed: () => context.push('/sign-in'), child: const Text('SIGN IN')),
            );
          }
          return FutureBuilder<List<MailboxMessage>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) return ErrorCard(message: snap.error.toString(), onRetry: _refresh);
              final messages = snap.data ?? const [];
              if (messages.isEmpty) {
                return const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'ALL QUIET',
                  body: 'Vendors near you have not posted anything yet.',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _MessageCard(
                    message: messages[i],
                    onOpen: () async {
                      await _markRead(messages[i]);
                      _refresh();
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.onOpen});

  final MailboxMessage message;
  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context) {
    final t = ThemeInjector.tokensOf(context);
    final icon = switch (message.kind) {
      MailboxKind.offer => Icons.local_offer_outlined,
      MailboxKind.discountCode => Icons.confirmation_number_outlined,
      MailboxKind.notice => Icons.campaign_outlined,
      MailboxKind.orderUpdate => Icons.receipt_long_outlined,
      MailboxKind.system => Icons.info_outline,
    };
    final code = message.payload['code'];
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: message.isRead ? t.iron : t.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (message.vendorName ?? 'HUBBLE').toUpperCase(),
                      style: HubbleType.mono(size: 11, color: t.iron, weight: FontWeight.w700),
                    ),
                    Text(message.title, style: HubbleType.display(size: 17, color: t.onCanvas)),
                    const SizedBox(height: 4),
                    Text(message.body, style: HubbleType.body(size: 14, color: t.onCanvas)),
                    if (code is String)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'CODE: $code',
                          style: HubbleType.mono(size: 13, color: t.accent, weight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ),
              if (!message.isRead)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
