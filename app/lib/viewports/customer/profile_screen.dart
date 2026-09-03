import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_controller.dart';
import '../../core/theme/theme_scope.dart';
import '../../core/theme/typography.dart';
import '../widgets/app_scope.dart';

/// Identity + viewport switch. One JWT serves both sides: switching to the
/// vendor hub never re-authenticates.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = ThemeInjector.tokensOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('PROFILE')),
      body: ListenableBuilder(
        listenable: scope.session,
        builder: (context, _) {
          final s = scope.session;
          if (!s.isSignedIn) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ONE ACCOUNT. EVERY LOCAL STORE.',
                    style: HubbleType.display(size: 26, color: t.onCanvas),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in once with a magic link or a text message.',
                    style: HubbleType.body(color: t.onCanvas),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: () => context.push('/sign-in'), child: const Text('SIGN IN')),
                ],
              ),
            );
          }
          final profile = s.profile;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                (profile?.displayName ?? 'YOU').toUpperCase(),
                style: HubbleType.display(size: 28, color: t.onCanvas),
              ),
              Text(profile?.email ?? profile?.phone ?? '', style: HubbleType.mono(size: 12, color: t.iron)),
              const SizedBox(height: 24),
              Text(
                'VENDOR HUB',
                style: HubbleType.mono(size: 12, color: t.iron, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (s.hasVendorRole)
                Card(
                  child: Column(
                    children: [
                      for (final m in s.memberships)
                        ListTile(
                          leading: const Icon(Icons.storefront),
                          title: Text(
                            m.vendor.name.toUpperCase(),
                            style: HubbleType.display(size: 16, color: t.onCanvas),
                          ),
                          subtitle: Text(
                            m.role.toUpperCase(),
                            style: HubbleType.mono(size: 11, color: t.iron),
                          ),
                          trailing: Icon(Icons.chevron_right, color: t.iron),
                          onTap: () async {
                            await s.setMode(ViewportMode.vendor);
                            if (context.mounted) context.go('/vendor/${m.vendor.id}');
                          },
                        ),
                    ],
                  ),
                )
              else
                Text('You do not run a storefront yet.', style: HubbleType.body(color: t.onCanvas)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => context.push('/vendor/new'),
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('CREATE A STOREFRONT'),
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: () async {
                  await s.signOut();
                  if (context.mounted) context.go('/');
                },
                child: Text('SIGN OUT', style: HubbleType.mono(size: 13, color: t.alert)),
              ),
            ],
          );
        },
      ),
    );
  }
}
