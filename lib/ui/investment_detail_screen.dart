import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../data/providers.dart';
import '../logic/deposit_math.dart';
import '../logic/valuation.dart';
import '../models/investment.dart';
import '../theme/app_theme.dart';
import 'investment_form_screen.dart';
import 'widgets/common.dart';

class InvestmentDetailScreen extends ConsumerWidget {
  const InvestmentDetailScreen({super.key, required this.investmentId});

  final String investmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(investmentsProvider).value ?? const <Investment>[];
    final inv = all.where((i) => i.id == investmentId).firstOrNull;
    if (inv == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This investment was deleted.')),
      );
    }
    final today = ref.watch(todayProvider);
    final members = ref.watch(membersProvider).value ?? const [];
    final owner = members.where((m) => m.id == inv.memberId).firstOrNull;
    final v = valuationOf(inv, today);
    final t = Theme.of(context).textTheme;
    final repo = ref.read(repositoryProvider);

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    InvestmentFormScreen(type: inv.type, existing: inv),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) async {
              if (v == 'close') {
                await repo?.saveInvestment(
                  inv.copyWith(isClosed: !inv.isClosed),
                );
              } else if (v == 'delete') {
                final ok = await _confirmDelete(context, inv);
                if (ok && context.mounted) {
                  Navigator.of(context).pop();
                  await repo?.deleteInvestment(inv.id);
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'close',
                child: Text(
                  inv.isClosed
                      ? 'Mark as active again'
                      : inv.type.kind == ValuationKind.market
                      ? 'Mark as sold'
                      : 'Mark as closed / withdrawn',
                ),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Row(
            children: [
              AssetBadge(inv.type, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(inv.name, style: t.headlineSmall),
                    const SizedBox(height: 2),
                    Text(
                      [
                        inv.type.label,
                        if (inv.institution.isNotEmpty) inv.institution,
                        if (owner != null) owner.name,
                      ].join(' · '),
                      style: t.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (inv.isClosed) ...[
            const SizedBox(height: 12),
            Text(
              'Closed: not counted in totals',
              style: t.bodyMedium?.copyWith(color: context.colors.warning),
            ),
          ],
          const SizedBox(height: 18),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current value', style: t.bodySmall),
                const SizedBox(height: 2),
                Text(formatInr(v.current), style: t.headlineMedium),
                const SizedBox(height: 4),
                GainText(v, style: t.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: 14),
          switch (inv.type.kind) {
            ValuationKind.market => _MarketDetails(
              inv: inv,
              v: v,
              today: today,
            ),
            ValuationKind.deposit => _DepositDetails(inv: inv, today: today),
            ValuationKind.balance => _BalanceDetails(
              inv: inv,
              v: v,
              today: today,
            ),
          },
          if (inv.reference.isNotEmpty || inv.notes.isNotEmpty) ...[
            const SizedBox(height: 14),
            SectionCard(
              title: 'Notes',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (inv.reference.isNotEmpty)
                    Text('Reference: ${inv.reference}', style: t.bodyMedium),
                  if (inv.notes.isNotEmpty) ...[
                    if (inv.reference.isNotEmpty) const SizedBox(height: 6),
                    Text(inv.notes, style: t.bodyMedium),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, Investment inv) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this investment?'),
        content: Text(
          '"${inv.name}" will be removed for good. To keep its history, mark it as closed instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return res ?? false;
  }
}

class _MarketDetails extends ConsumerWidget {
  const _MarketDetails({
    required this.inv,
    required this.v,
    required this.today,
  });

  final Investment inv;
  final Valuation v;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cagr = annualisedReturnPct(inv, today);
    final price = inv.currentPrice;
    return SectionCard(
      title: 'Details',
      trailing: TextButton.icon(
        onPressed: () => _updatePrice(context, ref),
        icon: const Icon(Icons.price_change_outlined, size: 18),
        label: const Text('Update price'),
      ),
      child: StatGrid([
        Stat('Units', _units(inv.units)),
        Stat('Invested', formatInr(v.invested)),
        Stat(
          'Average cost',
          inv.avgCost == null ? '–' : formatInr(inv.avgCost!, decimals: 2),
        ),
        Stat(
          inv.priceDate == null
              ? 'Current price'
              : 'Price on ${formatDayMonth(inv.priceDate!)}',
          price == null ? 'Not set' : formatInr(price, decimals: 2),
        ),
        if (inv.startDate != null)
          Stat('Bought on', formatDate(inv.startDate!)),
        if (cagr != null) Stat('Yearly growth (CAGR)', formatPct(cagr)),
        if (inv.sipAmount != null && inv.sipDay != null)
          Stat('SIP', '${formatInr(inv.sipAmount!)} on day ${inv.sipDay}'),
        if (inv.schemeCode?.isNotEmpty ?? false)
          Stat('AMFI code', inv.schemeCode!),
      ]),
    );
  }

  String _units(double? u) {
    if (u == null) return '–';
    final s = u.toStringAsFixed(3);
    final dot = s.indexOf('.');
    return '${formatInr(double.parse(s.substring(0, dot))).substring(1)}${s.substring(dot)}';
  }

  Future<void> _updatePrice(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(
      text: inv.currentPrice?.toString() ?? '',
    );
    final price = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Price per unit today'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '₹ '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, parseAmount(ctrl.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (price == null || price <= 0) return;
    await ref.read(repositoryProvider)?.updatePrices({
      inv.id: (price, dateOnly(DateTime.now())),
    });
  }
}

class _DepositDetails extends ConsumerWidget {
  const _DepositDetails({required this.inv, required this.today});

  final Investment inv;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final year = TaxYear.of(today);
    final maturity = inv.maturityDate;
    final maturityValue = DepositMath.maturityValue(inv);
    final earned = DepositMath.interestEarnedUntil(inv, today);
    final thisYear = DepositMath.interestBetween(inv, year.start, year.end);
    final daysLeft = maturity == null ? null : daysBetween(today, maturity);
    final payout = DepositMath.nextPayout(inv, today);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Deposit',
          child: StatGrid([
            if (inv.isRecurring)
              Stat('Monthly instalment', formatInr(inv.monthlyInstalment ?? 0))
            else
              Stat('Principal', formatInr(inv.principal ?? 0)),
            Stat(
              'Interest rate',
              inv.ratePct == null
                  ? '–'
                  : '${inv.ratePct!.toStringAsFixed(2)}% a year',
            ),
            if (inv.startDate != null)
              Stat('Started', formatDate(inv.startDate!)),
            if (maturity != null)
              Stat(
                'Matures',
                formatDate(maturity),
                valueColor: daysLeft != null && daysLeft <= 30
                    ? context.colors.warning
                    : null,
              ),
            Stat('Compounding', inv.compounding.label),
            if (!inv.isRecurring) Stat('Interest', inv.payout.label),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Interest',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StatGrid([
                Stat('Earned so far', formatInr(earned)),
                Stat('In tax year ${year.label}', formatInr(thisYear)),
                if (maturityValue != null)
                  Stat(
                    (inv.isRecurring || inv.payout == Payout.cumulative)
                        ? 'Maturity amount'
                        : 'Principal back at maturity',
                    formatInr(maturityValue),
                  ),
                if (daysLeft != null)
                  Stat(
                    'Time left',
                    daysLeft < 0 ? 'Matured' : _timeLeft(daysLeft),
                  ),
                if (payout != null)
                  Stat(
                    'Next payout',
                    '${formatInr(payout.$2)} on ${formatDayMonth(payout.$1)}',
                  ),
              ]),
              const SizedBox(height: 12),
              Text(
                'Estimated from the rate. Bank figures can differ by a few rupees.',
                style: t.bodySmall,
              ),
            ],
          ),
        ),
        if (inv.tdsApplicable) ...[
          const SizedBox(height: 14),
          Card(
            child: SwitchListTile(
              value: inv.form15Submitted,
              onChanged: (v) => ref
                  .read(repositoryProvider)
                  ?.saveInvestment(inv.copyWith(form15Submitted: v)),
              title: const Text('Form 15G / 15H submitted'),
              subtitle: Text(
                'For tax year ${year.label}. The bank then won\'t deduct TDS.',
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _timeLeft(int days) {
    if (days < 60) return '$days days';
    final months = (days / 30.44).round();
    if (months < 24) return '$months months';
    final years = months ~/ 12;
    final rem = months % 12;
    return rem == 0 ? '$years years' : '$years yr $rem mo';
  }
}

class _BalanceDetails extends StatelessWidget {
  const _BalanceDetails({
    required this.inv,
    required this.v,
    required this.today,
  });

  final Investment inv;
  final Valuation v;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final rate = inv.ratePct;
    final est = rate == null ? null : v.current * rate / 100;
    return SectionCard(
      title: 'Details',
      child: StatGrid([
        Stat('Total put in', formatInr(v.invested)),
        Stat(
          inv.priceDate == null
              ? 'Balance'
              : 'Balance on ${formatDayMonth(inv.priceDate!)}',
          formatInr(v.current),
        ),
        if (rate != null)
          Stat('Interest rate', '${rate.toStringAsFixed(2)}% a year'),
        if (est != null)
          Stat(
            inv.type.interestTaxFree
                ? 'Interest this year (tax-free, est.)'
                : 'Growth this year (est.)',
            formatInr(est),
          ),
        if (inv.startDate != null) Stat('Opened', formatDate(inv.startDate!)),
        if (inv.maturityDate != null)
          Stat('Matures', formatDate(inv.maturityDate!)),
      ]),
    );
  }
}
