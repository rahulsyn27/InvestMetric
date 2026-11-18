import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:material_ui/material_ui.dart';

import '../data/providers.dart';
import '../theme/app_theme.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.error});

  final String? error;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.error;
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        setState(
          () =>
              _error = 'Google sign-in failed: ${e.description ?? e.code.name}',
        );
      }
    } catch (e) {
      setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.5),
                  ),
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  color: scheme.primary,
                  size: 30,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'All your family\'s investments, in one place.',
                style: t.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Mutual funds, FDs, PPF, stocks and more. See what you own, '
                'the interest you earn, the TDS banks deduct and every '
                'maturity date, without the spreadsheet.',
                style: t.bodyLarge?.copyWith(
                  color: context.colors.muted,
                  height: 1.5,
                ),
              ),
              const Spacer(flex: 3),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: t.bodyMedium?.copyWith(color: scheme.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: _busy ? null : _signIn,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: const Text('Continue with Google'),
              ),
              const SizedBox(height: 14),
              Text(
                'Your data is stored in your own account and only you can see it.',
                style: t.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
