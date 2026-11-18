import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/dates.dart';
import '../data/providers.dart';
import '../models/investment.dart';
import 'widgets/common.dart';

/// Downloads today's NAVs from AMFI and updates every mutual fund that has a
/// scheme code. Runs only when the user taps refresh (free, no server needed).
Future<void> refreshMutualFundPrices(
  BuildContext context,
  WidgetRef ref,
) async {
  final repo = ref.read(repositoryProvider);
  if (repo == null) return;
  final funds = (ref.read(investmentsProvider).value ?? const <Investment>[])
      .where(
        (i) =>
            i.type == AssetType.mutualFund &&
            !i.isClosed &&
            (i.schemeCode?.isNotEmpty ?? false),
      )
      .toList();
  if (funds.isEmpty) {
    showSnack(
      context,
      'No mutual funds linked to AMFI yet. Pick the fund by name when adding it.',
    );
    return;
  }
  showSnack(context, 'Fetching latest NAVs…');
  try {
    final navs = await ref.read(amfiNavsProvider.notifier).load(force: true);
    final byCode = {for (final s in navs) s.code: s};
    final updates = <String, (double, DateTime)>{};
    DateTime? latest;
    for (final f in funds) {
      final s = byCode[f.schemeCode];
      if (s == null) continue;
      updates[f.id] = (s.nav, s.date);
      if (latest == null || s.date.isAfter(latest)) latest = s.date;
    }
    await repo.updatePrices(updates);
    if (!context.mounted) return;
    final missing = funds.length - updates.length;
    showSnack(
      context,
      'Updated ${updates.length} fund${updates.length == 1 ? '' : 's'}'
      '${latest != null ? ' · NAV of ${formatDate(latest)}' : ''}'
      '${missing > 0 ? ' · $missing not found' : ''}',
    );
  } catch (e) {
    if (context.mounted) {
      showSnack(
        context,
        'Couldn\'t reach AMFI. Check the internet and try again.',
      );
    }
  }
}
