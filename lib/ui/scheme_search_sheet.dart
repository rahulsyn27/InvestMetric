import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../data/providers.dart';
import '../logic/amfi.dart';
import '../theme/app_theme.dart';

/// Lets the user find a mutual fund in AMFI's list. Returns the chosen scheme.
Future<AmfiScheme?> pickScheme(BuildContext context) {
  return showModalBottomSheet<AmfiScheme>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        const FractionallySizedBox(heightFactor: 0.92, child: _SchemeSearch()),
  );
}

class _SchemeSearch extends ConsumerStatefulWidget {
  const _SchemeSearch();

  @override
  ConsumerState<_SchemeSearch> createState() => _SchemeSearchState();
}

class _SchemeSearchState extends ConsumerState<_SchemeSearch> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(amfiNavsProvider.notifier)
          .load()
          .catchError((_) => <AmfiScheme>[]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(amfiNavsProvider);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Find your fund', style: t.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g. parag flexi direct growth',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Tip: add "direct" or "regular" and "growth" or "idcw" to match your exact plan.',
              style: t.bodySmall,
            ),
          ),
          Expanded(
            child: switch (state) {
              null || AsyncLoading() => const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Downloading fund list from AMFI…'),
                  ],
                ),
              ),
              AsyncError() => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Couldn\'t download the fund list. Check the internet.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => ref
                            .read(amfiNavsProvider.notifier)
                            .load(force: true)
                            .catchError((_) => <AmfiScheme>[]),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
              AsyncData(:final value) => _Results(
                results: searchSchemes(value, _query, limit: 50),
                hasQuery: _query.trim().isNotEmpty,
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.results, required this.hasQuery});

  final List<AmfiScheme> results;
  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    if (!hasQuery) {
      return const Center(child: Text('Type a few words of the fund name.'));
    }
    if (results.isEmpty) {
      return const Center(child: Text('No matching fund.'));
    }
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, i) {
        final s = results[i];
        return ListTile(
          title: Text(s.name),
          subtitle: Text(
            '${s.fundHouse.isEmpty ? '' : '${s.fundHouse} · '}NAV ${formatInr(s.nav, decimals: 2)} on ${formatDayMonth(s.date)}',
            style: TextStyle(color: context.colors.muted),
          ),
          onTap: () => Navigator.of(context).pop(s),
        );
      },
    );
  }
}
