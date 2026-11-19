import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'data/providers.dart';
import 'models/member.dart';
import 'theme/app_theme.dart';
import 'ui/home_shell.dart';
import 'ui/sign_in_screen.dart';

class InvestTrackerApp extends ConsumerWidget {
  const InvestTrackerApp({super.key, this.home});

  /// Tests pass a screen here to skip sign-in.
  final Widget? home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'InvestMetric',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      home: home ?? const AuthGate(),
    );
  }
}

/// Shows sign-in, or the app once signed in.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(userIdProvider);
    return uid.when(
      loading: () => const _Splash(),
      error: (e, _) => SignInScreen(error: e.toString()),
      data: (id) =>
          id == null ? const SignInScreen() : const _SelfProfileBootstrap(),
    );
  }
}

/// Creates the "Self" profile the first time someone signs in.
class _SelfProfileBootstrap extends ConsumerStatefulWidget {
  const _SelfProfileBootstrap();

  @override
  ConsumerState<_SelfProfileBootstrap> createState() =>
      _SelfProfileBootstrapState();
}

class _SelfProfileBootstrapState extends ConsumerState<_SelfProfileBootstrap> {
  bool _created = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(membersProvider, (_, next) {
      final members = next.value;
      if (members == null || members.isNotEmpty || _created) return;
      _created = true;
      final user = ref.read(currentUserProvider);
      ref
          .read(repositoryProvider)
          ?.saveMember(
            Member(
              id: '',
              name: (user?.displayName?.isNotEmpty ?? false)
                  ? user!.displayName!
                  : 'Me',
              relation: 'Self',
              email: user?.email ?? '',
              isSelf: true,
            ),
          );
    });
    return const HomeShell();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
