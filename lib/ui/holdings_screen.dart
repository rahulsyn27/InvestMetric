import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/money.dart';
import '../data/providers.dart';
import '../logic/valuation.dart';
import '../models/investment.dart';
import '../models/member.dart';
import '../theme/app_theme.dart';
import 'investment_detail_screen.dart';
import 'investment_form_screen.dart';
import 'price_refresh.dart';
import 'widgets/common.dart';

class HoldingsScreen extends ConsumerStatefulWidget {
  const HoldingsScreen({super.key});

  @override
  ConsumerState<HoldingsScreen> createState() => _HoldingsScreenState();
}

class _HoldingsScreenState extends ConsumerState<HoldingsScreen> {
  bool _showClosed = false;

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final all = ref.watch(visibleInvestmentsProvider);
    final members = {
      for (final m in ref.watch(membersProvider).value ?? const <Member>[])
        m.id: m,
    };
    final showOwner =
        ref.watch(selectedMemberProvider) == null && members.length > 1;
    final items = all.where((i) => _showClosed || !i.isClosed).toList();
    final groups = <AssetType, List<Investment>>{};
    for (final i in items) {
      groups.putIfAbsent(i.type, () => []).add(i);
    }
    final ordered = groups.entries.toList()
      ..sort(
        (a, b) => totalValuation(
          b.value,
          today,
        ).current.compareTo(totalValuation(a.value, today).current),
      );
    final closedCount = all.where((i) => i.isClosed).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Holdings'),
        actions: [
          IconButton(
            tooltip: 'Refresh mutual fund prices',
            onPressed: () => refreshMutualFundPrices(context, ref),
            icon: const Icon(Icons.refresh),
          ),
          if (closedCount > 0)
            IconButton(
              tooltip: _showClosed
                  ? 'Hide closed'
                  : 'Show closed ($closedCount)',
              onPressed: () => setState(() => _showClosed = !_showClosed),
              icon: Icon(
                _showClosed ? Icons.visibility_off_outlined : Icons.history,
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'holdings-add',
        tooltip: 'Add investment',
        onPressed: () => startAddInvestment(context, ref),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          const MemberFilterBar(),
          Expanded(
            child: items.isEmpty
                ? EmptyState(
                    icon: Icons.pie_chart_outline,
                    title: 'Nothing here yet',
                    message:
                        'Investments you add show up here, grouped by type.',
                    action: FilledButton.icon(
                      onPressed: () => startAddInvestment(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Add investment'),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: ordered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, i) => _GroupCard(
                      type: ordered[i].key,
                      items: ordered[i].value,
                      today: today,
                      members: showOwner ? members : null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.type,
    required this.items,
    required this.today,
    this.members,
  });

  final AssetType type;
  final List<Investment> items;
  final DateTime today;

  /// Set to show whose investment each row is.
  final Map<String, Member>? members;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final total = totalValuation(items, today);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                AssetBadge(type),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(type.label, style: t.titleMedium),
                      Text(
                        '${items.length} holding${items.length == 1 ? '' : 's'}',
                        style: t.bodySmall,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatInr(total.current), style: t.titleMedium),
                    GainText(total, showAmount: false),
                  ],
                ),
              ],
            ),
          ),
          for (final inv in items) ...[
            const Divider(),
            _HoldingRow(inv: inv, today: today, owner: members?[inv.memberId]),
          ],
        ],
      ),
    );
  }
}

class _HoldingRow extends StatelessWidget {
  const _HoldingRow({required this.inv, required this.today, this.owner});

  final Investment inv;
  final DateTime today;
  final Member? owner;

  String _subtitle() {
    final parts = <String>[];
    if (owner != null) parts.add(owner!.name.split(' ').first);
    if (inv.institution.isNotEmpty && inv.institution != inv.name) {
      parts.add(inv.institution);
    }
    if (inv.type.kind == ValuationKind.deposit && inv.ratePct != null) {
      parts.add('${inv.ratePct!.toStringAsFixed(2)}%');
    }
    if (inv.isClosed) parts.add('Closed');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final v = valuationOf(inv, today);
    final sub = _subtitle();
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InvestmentDetailScreen(investmentId: inv.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    inv.name,
                    style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      style: t.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatInr(v.current), style: t.titleSmall),
                GainText(v, showAmount: false),
              ],
            ),
            Icon(Icons.chevron_right, color: context.colors.muted),
          ],
        ),
      ),
    );
  }
}
