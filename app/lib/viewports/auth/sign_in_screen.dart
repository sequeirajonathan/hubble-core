import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_service.dart';
import '../../core/network/supabase_client.dart';
import '../../core/theme/theme_scope.dart';
import '../../core/theme/typography.dart';

enum _Method { email, phone }

/// Single sign-on entry: email magic link / code, or phone verification code.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _auth = AuthService(HubbleBackend.auth);
  final _identity = TextEditingController();
  final _code = TextEditingController();
  _Method _method = _Method.email;
  bool _sent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _identity.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (err) {
      if (mounted) setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() => _run(() async {
    final id = _identity.text.trim();
    if (_method == _Method.email) {
      await _auth.sendMagicLink(id);
    } else {
      await _auth.sendPhoneCode(id);
    }
    setState(() => _sent = true);
  });

  Future<void> _verify() => _run(() async {
    final id = _identity.text.trim();
    if (_method == _Method.email) {
      await _auth.verifyEmailCode(email: id, code: _code.text);
    } else {
      await _auth.verifyPhoneCode(phoneE164: id, code: _code.text);
    }
    if (mounted) context.go('/');
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeInjector.tokensOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('SIGN IN')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('ONE ACCOUNT', style: HubbleType.display(size: 32, color: t.accent)),
          Text(
            'Shop every local store, or run your own, with the same sign-in.',
            style: HubbleType.body(color: t.onCanvas),
          ),
          const SizedBox(height: 24),
          SegmentedButton<_Method>(
            segments: const [
              ButtonSegment(value: _Method.email, icon: Icon(Icons.alternate_email), label: Text('EMAIL')),
              ButtonSegment(value: _Method.phone, icon: Icon(Icons.sms_outlined), label: Text('PHONE')),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() {
              _method = s.first;
              _sent = false;
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _identity,
            enabled: !_sent,
            keyboardType: _method == _Method.email ? TextInputType.emailAddress : TextInputType.phone,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: _method == _Method.email ? 'EMAIL' : 'PHONE (+1 555 010 0000)',
              prefixIcon: Icon(_method == _Method.email ? Icons.mail_outline : Icons.phone_outlined),
            ),
          ),
          if (_sent) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              style: HubbleType.mono(size: 22, color: t.onCanvas),
              decoration: const InputDecoration(labelText: 'CODE', prefixIcon: Icon(Icons.pin_outlined)),
            ),
            const SizedBox(height: 8),
            Text(
              _method == _Method.email
                  ? 'Tap the magic link in the email, or enter the code it contains.'
                  : 'Enter the code we texted you.',
              style: HubbleType.mono(size: 12, color: t.iron),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: HubbleType.mono(size: 12, color: t.alert)),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : (_sent ? _verify : _send),
            child: Text(_sent ? 'VERIFY' : 'SEND CODE'),
          ),
          if (_sent)
            TextButton(
              onPressed: _busy ? null : () => setState(() => _sent = false),
              child: const Text('USE A DIFFERENT ADDRESS'),
            ),
        ],
      ),
    );
  }
}
