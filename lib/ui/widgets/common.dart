import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../data/providers.dart';
import '../../logic/valuation.dart';
import '../../models/investment.dart';
import '../../theme/app_theme.dart';

/// A rounded card with an optional title row.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// "+₹18,27,310 · ▲ 26.8%" coloured by sign.
class GainText extends StatelessWidget {
  const GainText(
    this.valuation, {
    super.key,
    this.style,
    this.showAmount = true,
  });

  final Valuation valuation;
  final TextStyle? style;
  final bool showAmount;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gain = valuation.gain;
    final color = gain > 0.5 ? c.gain : (gain < -0.5 ? c.loss : c.muted);
    final pct = valuation.gainPct;
    final parts = [
      if (showAmount) formatInr(gain, showSign: true),
      if (pct != null) formatPct(pct, showSign: true),
    ];
    return Text(
      parts.join(' · '),
      style: (style ?? Theme.of(context).textTheme.bodySmall)?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Small coloured square with the asset code ("MF", "FD").
class AssetBadge extends StatelessWidget {
  const AssetBadge(this.type, {super.key, this.size = 40});

  final AssetType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: type.color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: type.color.withValues(alpha: 0.35)),
      ),
      child: Text(
        type.code,
        style: TextStyle(
          color: type.color,
          fontWeight: FontWeight.w800,
          fontSize: type.code.length > 2 ? size * 0.26 : size * 0.3,
        ),
      ),
    );
  }
}

/// Horizontal stacked bar of asset allocation.
class AllocationBar extends StatelessWidget {
  const AllocationBar(this.slices, {super.key, this.height = 12});

  final List<(AssetType, Valuation)> slices;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold(0.0, (s, e) => s + e.$2.current);
    if (total <= 0) return const SizedBox.shrink();
    return Semantics(
      label:
          'Allocation: ${slices.map((e) => '${e.$1.label} ${formatPct(e.$2.current / total * 100)}').join(', ')}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < slices.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  flex: (slices[i].$2.current / total * 1000).round().clamp(
                    1,
                    1000,
                  ),
                  child: ColoredBox(color: slices[i].$1.color),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "All family · Self · Mother · Sister" filter chips.
class MemberFilterBar extends ConsumerWidget {
  const MemberFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider).value ?? const [];
    final selected = ref.watch(selectedMemberProvider);
    if (members.length < 2) return const SizedBox.shrink();
    final notifier = ref.read(selectedMemberProvider.notifier);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All family'),
              selected: selected == null,
              onSelected: (_) => notifier.select(null),
            ),
          ),
          for (final m in members)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(m.name.split(' ').first),
                selected: selected == m.id,
                onSelected: (_) => notifier.select(m.id),
              ),
            ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: t.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            message,
            style: t.bodyMedium?.copyWith(color: context.colors.muted),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

/// A label/value pair in a two-column grid.
class Stat extends StatelessWidget {
  const Stat(this.label, this.value, {super.key, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: t.titleSmall?.copyWith(color: valueColor)),
      ],
    );
  }
}

/// Wraps [Stat]s two per row.
class StatGrid extends StatelessWidget {
  const StatGrid(this.stats, {super.key});

  final List<Widget> stats;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < stats.length; i += 2) {
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: stats[i]),
            const SizedBox(width: 16),
            Expanded(
              child: i + 1 < stats.length ? stats[i + 1] : const SizedBox(),
            ),
          ],
        ),
      );
      if (i + 2 < stats.length) rows.add(const SizedBox(height: 14));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
