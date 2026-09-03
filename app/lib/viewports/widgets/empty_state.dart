import 'package:flutter/material.dart';

import '../../core/theme/theme_scope.dart';
import '../../core/theme/typography.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.action});

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = ThemeInjector.tokensOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: t.iron),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: HubbleType.display(size: 20, color: t.onCanvas),
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: HubbleType.body(size: 14, color: t.iron),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorCard extends StatelessWidget {
  const ErrorCard({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = ThemeInjector.tokensOf(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: t.alert),
          borderRadius: BorderRadius.circular(6),
          color: t.surface,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: t.alert),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: HubbleType.mono(size: 12, color: t.onCanvas),
            ),
            if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('RETRY')),
          ],
        ),
      ),
    );
  }
}
