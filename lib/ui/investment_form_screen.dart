import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../data/providers.dart';
import '../logic/deposit_math.dart';
import '../models/investment.dart';
import '../models/member.dart';
import 'scheme_search_sheet.dart';
import 'widgets/common.dart';

/// Asks what kind of investment to add, then opens the form.
Future<void> startAddInvestment(BuildContext context, WidgetRef ref) async {
  final type = await showModalBottomSheet<AssetType>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final t = Theme.of(ctx).textTheme;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('What are you adding?', style: t.titleLarge),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.05,
              children: [
                for (final type in AssetType.values)
                  Material(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.pop(ctx, type),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AssetBadge(type, size: 38),
                            const SizedBox(height: 8),
                            Text(
                              type.label,
                              textAlign: TextAlign.center,
                              style: t.bodySmall?.copyWith(
                                color: Theme.of(ctx).colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
  if (type == null || !context.mounted) return;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => InvestmentFormScreen(type: type)));
}

class InvestmentFormScreen extends ConsumerStatefulWidget {
  const InvestmentFormScreen({super.key, required this.type, this.existing});

  final AssetType type;
  final Investment? existing;

  @override
  ConsumerState<InvestmentFormScreen> createState() =>
      _InvestmentFormScreenState();
}

class _InvestmentFormScreenState extends ConsumerState<InvestmentFormScreen> {
  final _form = GlobalKey<FormState>();

  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _institution = TextEditingController(
    text: widget.existing?.institution ?? '',
  );
  late final _reference = TextEditingController(
    text: widget.existing?.reference ?? '',
  );
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late final _principal = TextEditingController(
    text: _num(widget.existing?.principal),
  );
  late final _instalment = TextEditingController(
    text: _num(widget.existing?.monthlyInstalment),
  );
  late final _rate = TextEditingController(
    text: _num(widget.existing?.ratePct),
  );
  late final _units = TextEditingController(text: _num(widget.existing?.units));
  late final _amountInvested = TextEditingController(
    text: _num(
      widget.existing == null
          ? null
          : (widget.existing!.units ?? 0) * (widget.existing!.avgCost ?? 0),
    ),
  );
  late final _price = TextEditingController(
    text: _num(widget.existing?.currentPrice),
  );
  late final _sipAmount = TextEditingController(
    text: _num(widget.existing?.sipAmount),
  );
  late final _sipDay = TextEditingController(
    text: widget.existing?.sipDay?.toString() ?? '',
  );
  late final _investedTotal = TextEditingController(
    text: _num(widget.existing?.investedAmount),
  );
  late final _balance = TextEditingController(
    text: _num(widget.existing?.currentValue),
  );

  String? _memberId;
  DateTime? _startDate;
  DateTime? _maturityDate;
  DateTime? _priceDate;
  String? _schemeCode;
  late Compounding _compounding;
  late Payout _payout;
  late bool _tds;
  late bool _form15;

  AssetType get type => widget.type;
  bool get _isEdit => widget.existing != null;

  static String _num(double? v) {
    if (v == null || v == 0) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _memberId = e?.memberId;
    _startDate = e?.startDate;
    _maturityDate = e?.maturityDate;
    _priceDate = e?.priceDate;
    _schemeCode = e?.schemeCode;
    _compounding =
        e?.compounding ??
        (type == AssetType.bond ? Compounding.yearly : Compounding.quarterly);
    _payout = e?.payout ?? Payout.cumulative;
    _tds = e?.tdsApplicable ?? type.tdsByDefault;
    _form15 = e?.form15Submitted ?? false;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _institution,
      _reference,
      _notes,
      _principal,
      _instalment,
      _rate,
      _units,
      _amountInvested,
      _price,
      _sipAmount,
      _sipDay,
      _investedTotal,
      _balance,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _amount(String? v, {bool required = true}) {
    if (v == null || v.trim().isEmpty) return required ? 'Required' : null;
    final n = parseAmount(v);
    if (n == null) return 'Enter a number';
    if (n < 0) return 'Can\'t be negative';
    return null;
  }

  Future<void> _pickDate({
    required DateTime? initial,
    required ValueChanged<DateTime> onPicked,
    DateTime? first,
  }) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: first ?? DateTime(1980),
      lastDate: DateTime(now.year + 40),
    );
    if (d != null) setState(() => onPicked(d));
  }

  Future<void> _findFund() async {
    final s = await pickScheme(context);
    if (s == null) return;
    setState(() {
      _name.text = s.name;
      if (_institution.text.trim().isEmpty) _institution.text = s.fundHouse;
      _schemeCode = s.code;
      _price.text = s.nav.toString();
      _priceDate = s.date;
    });
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final members = ref.read(membersProvider).value ?? const <Member>[];
    final memberId = _memberId ?? _defaultMember(members)?.id;
    if (memberId == null) {
      showSnack(context, 'Add a family member first (Family tab).');
      return;
    }
    final units = parseAmount(_units.text);
    final invested = parseAmount(_amountInvested.text);
    final price = parseAmount(_price.text);
    final priceChanged = price != widget.existing?.currentPrice;
    final balance = parseAmount(_balance.text);
    final balanceChanged = balance != widget.existing?.currentValue;

    final inv = Investment(
      id: widget.existing?.id ?? '',
      memberId: memberId,
      type: type,
      name: _name.text.trim(),
      institution: _institution.text.trim(),
      reference: _reference.text.trim(),
      notes: _notes.text.trim(),
      startDate: _startDate,
      isClosed: widget.existing?.isClosed ?? false,
      principal: type.kind == ValuationKind.deposit && !type.isRecurringType
          ? parseAmount(_principal.text)
          : null,
      monthlyInstalment: type.isRecurringType
          ? parseAmount(_instalment.text)
          : null,
      ratePct: parseAmount(_rate.text),
      maturityDate: _maturityDate,
      compounding: _compounding,
      payout: type.isRecurringType ? Payout.cumulative : _payout,
      tdsApplicable: type.kind == ValuationKind.deposit && _tds,
      form15Submitted: type.kind == ValuationKind.deposit && _tds && _form15,
      units: type.kind == ValuationKind.market ? units : null,
      avgCost:
          type.kind == ValuationKind.market &&
              units != null &&
              units > 0 &&
              invested != null
          ? invested / units
          : null,
      currentPrice: type.kind == ValuationKind.market ? price : null,
      priceDate: type.kind == ValuationKind.market
          ? (priceChanged && _schemeCode == widget.existing?.schemeCode
                ? dateOnly(DateTime.now())
                : _priceDate)
          : (balanceChanged ? dateOnly(DateTime.now()) : _priceDate),
      schemeCode: type == AssetType.mutualFund ? _schemeCode : null,
      sipAmount: type == AssetType.mutualFund
          ? parseAmount(_sipAmount.text)
          : null,
      sipDay: type == AssetType.mutualFund
          ? int.tryParse(_sipDay.text.trim())
          : null,
      investedAmount: type.kind == ValuationKind.balance
          ? parseAmount(_investedTotal.text)
          : null,
      currentValue: type.kind == ValuationKind.balance ? balance : null,
    );
    await ref.read(repositoryProvider)?.saveInvestment(inv);
    if (mounted) Navigator.of(context).pop();
  }

  Member? _defaultMember(List<Member> members) {
    final selected = ref.read(selectedMemberProvider);
    return members.where((m) => m.id == selected).firstOrNull ??
        members.where((m) => m.isSelf).firstOrNull ??
        members.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    _memberId ??= _defaultMember(members)?.id;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit ${type.label}' : 'Add ${type.label}'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (members.length > 1) ...[
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: members.any((m) => m.id == _memberId)
                    ? _memberId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Whose investment',
                ),
                items: [
                  for (final m in members)
                    DropdownMenuItem(
                      value: m.id,
                      child: Text(
                        m.relation.isEmpty
                            ? m.name
                            : '${m.name} (${m.relation})',
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _memberId = v),
                validator: (v) => v == null ? 'Choose a member' : null,
              ),
              const _Gap(),
            ],
            if (type == AssetType.mutualFund) ...[
              OutlinedButton.icon(
                onPressed: _findFund,
                icon: const Icon(Icons.search),
                label: Text(
                  _schemeCode == null
                      ? 'Find fund in AMFI list'
                      : 'Change fund',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _schemeCode == null
                    ? 'Picking the fund lets the app refresh its NAV for free.'
                    : 'Linked to AMFI code $_schemeCode. Prices refresh from the Holdings tab.',
                style: t.bodySmall,
              ),
              const _Gap(),
            ],
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: _nameLabel,
                hintText: _nameHint,
              ),
              textCapitalization: TextCapitalization.words,
              validator: _required,
            ),
            const _Gap(),
            TextFormField(
              controller: _institution,
              decoration: InputDecoration(labelText: _institutionLabel),
              textCapitalization: TextCapitalization.words,
            ),
            const _Gap(),
            ...switch (type.kind) {
              ValuationKind.market => _marketFields(),
              ValuationKind.deposit => _depositFields(),
              ValuationKind.balance => _balanceFields(),
            },
            TextFormField(
              controller: _reference,
              decoration: const InputDecoration(
                labelText: 'Reference (optional)',
                hintText: 'Last 4 digits of FD no. / folio',
              ),
            ),
            const _Gap(),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 3,
              minLines: 1,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: Text(_isEdit ? 'Save changes' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  String get _nameLabel => switch (type) {
    AssetType.mutualFund => 'Fund name',
    AssetType.stock => 'Company',
    AssetType.fixedDeposit || AssetType.recurringDeposit => 'Name',
    AssetType.postOffice => 'Scheme',
    _ => 'Name',
  };

  String? get _nameHint => switch (type) {
    AssetType.fixedDeposit => 'e.g. SBI FD 2 years',
    AssetType.recurringDeposit => 'e.g. HDFC RD',
    AssetType.postOffice => 'e.g. SCSS, MIS, NSC, KVP, Time Deposit',
    AssetType.stock => 'e.g. Infosys',
    AssetType.gold => 'e.g. SGB 2020-21 Series V',
    AssetType.ppf => 'e.g. PPF – SBI',
    _ => null,
  };

  String get _institutionLabel => switch (type.kind) {
    ValuationKind.deposit => 'Bank / post office',
    ValuationKind.market =>
      type == AssetType.mutualFund
          ? 'Fund house (optional)'
          : 'Broker (optional)',
    ValuationKind.balance => 'Held with (optional)',
  };

  List<Widget> _marketFields() {
    final unitWord = type == AssetType.gold ? 'Units / grams' : 'Units';
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: _units,
              decoration: InputDecoration(
                labelText: type == AssetType.stock ? 'Shares' : unitWord,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: _amount,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _amountInvested,
              decoration: const InputDecoration(
                labelText: 'Amount invested',
                prefixText: '₹ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: _amount,
            ),
          ),
        ],
      ),
      const _Gap(),
      TextFormField(
        controller: _price,
        decoration: InputDecoration(
          labelText: 'Current price per unit (optional)',
          prefixText: '₹ ',
          helperText: _priceDate == null
              ? null
              : 'Price of ${formatDate(_priceDate!)}',
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (v) => _amount(v, required: false),
      ),
      const _Gap(),
      _DateField(
        label: 'Bought on (first purchase)',
        value: _startDate,
        onTap: () =>
            _pickDate(initial: _startDate, onPicked: (d) => _startDate = d),
      ),
      const _Gap(),
      if (type == AssetType.mutualFund) ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _sipAmount,
                decoration: const InputDecoration(
                  labelText: 'SIP amount (optional)',
                  prefixText: '₹ ',
                ),
                keyboardType: TextInputType.number,
                validator: (v) => _amount(v, required: false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _sipDay,
                decoration: const InputDecoration(labelText: 'SIP day (1–28)'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final d = int.tryParse(v.trim());
                  return (d == null || d < 1 || d > 31) ? '1 to 31' : null;
                },
              ),
            ),
          ],
        ),
        const _Gap(),
      ],
    ];
  }

  List<Widget> _depositFields() {
    final recurring = type.isRecurringType;
    final preview = _previewDeposit();
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: recurring ? _instalment : _principal,
              decoration: InputDecoration(
                labelText: recurring
                    ? 'Monthly instalment'
                    : 'Amount deposited',
                prefixText: '₹ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: _amount,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: TextFormField(
              controller: _rate,
              decoration: const InputDecoration(
                labelText: 'Interest rate',
                suffixText: '%',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: _amount,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
      const _Gap(),
      _DateField(
        label: 'Start date',
        value: _startDate,
        required: true,
        onTap: () =>
            _pickDate(initial: _startDate, onPicked: (d) => _startDate = d),
      ),
      const _Gap(),
      _DateField(
        label: 'Maturity date',
        value: _maturityDate,
        required: true,
        onTap: () => _pickDate(
          initial:
              _maturityDate ??
              (_startDate == null ? null : addMonths(_startDate!, 12)),
          first: _startDate,
          onPicked: (d) => _maturityDate = d,
        ),
      ),
      if (_startDate != null) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final (label, months) in const [
              ('1 yr', 12),
              ('2 yr', 24),
              ('3 yr', 36),
              ('5 yr', 60),
              ('10 yr', 120),
            ])
              ActionChip(
                label: Text(label),
                onPressed: () => setState(
                  () => _maturityDate = addMonths(_startDate!, months),
                ),
              ),
          ],
        ),
      ],
      const _Gap(),
      DropdownButtonFormField<Compounding>(
        isExpanded: true,
        initialValue: _compounding,
        decoration: const InputDecoration(labelText: 'Interest compounded'),
        items: [
          for (final c in Compounding.values)
            DropdownMenuItem(value: c, child: Text(c.label)),
        ],
        onChanged: (v) => setState(() => _compounding = v ?? _compounding),
      ),
      if (!recurring) ...[
        const _Gap(),
        DropdownButtonFormField<Payout>(
          isExpanded: true,
          initialValue: _payout,
          decoration: const InputDecoration(labelText: 'Interest'),
          items: [
            for (final p in Payout.values)
              DropdownMenuItem(value: p, child: Text(p.label)),
          ],
          onChanged: (v) => setState(() => _payout = v ?? _payout),
        ),
      ],
      const _Gap(),
      Card(
        child: Column(
          children: [
            SwitchListTile(
              value: _tds,
              onChanged: (v) => setState(() => _tds = v),
              title: const Text('Bank deducts TDS on this'),
              subtitle: const Text(
                'Usually yes for bank FDs, RDs and post office deposits',
              ),
            ),
            if (_tds)
              SwitchListTile(
                value: _form15,
                onChanged: (v) => setState(() => _form15 = v),
                title: const Text('Form 15G / 15H submitted this year'),
              ),
          ],
        ),
      ),
      if (preview != null) ...[
        const _Gap(),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            preview,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      ],
      const _Gap(),
    ];
  }

  /// Live "you'll get ₹X at maturity" line while filling the form.
  String? _previewDeposit() {
    final rate = parseAmount(_rate.text);
    final amount = parseAmount(
      type.isRecurringType ? _instalment.text : _principal.text,
    );
    if (rate == null ||
        amount == null ||
        _startDate == null ||
        _maturityDate == null) {
      return null;
    }
    final draft = Investment(
      id: '',
      memberId: '',
      type: type,
      name: '',
      startDate: _startDate,
      maturityDate: _maturityDate,
      ratePct: rate,
      principal: type.isRecurringType ? null : amount,
      monthlyInstalment: type.isRecurringType ? amount : null,
      compounding: _compounding,
      payout: type.isRecurringType ? Payout.cumulative : _payout,
    );
    final value = DepositMath.maturityValue(draft) ?? 0;
    final invested = DepositMath.investedOn(draft, _maturityDate!);
    final interest = DepositMath.interestEarnedUntil(draft, _maturityDate!);
    if (!type.isRecurringType && _payout != Payout.cumulative) {
      return 'About ${formatInr(interest)} interest in total, paid out '
          '${_payout.label.replaceFirst('Paid out ', '')}. ${formatInr(value)} back at maturity.';
    }
    return 'About ${formatInr(value)} at maturity: ${formatInr(invested)} put in + '
        '${formatInr(interest)} interest.';
  }

  List<Widget> _balanceFields() {
    final showRate =
        type == AssetType.ppf || type == AssetType.epf || type == AssetType.nps;
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: _investedTotal,
              decoration: InputDecoration(
                labelText: type == AssetType.insurance
                    ? 'Premiums paid'
                    : 'Total put in',
                prefixText: '₹ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: _amount,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _balance,
              decoration: InputDecoration(
                labelText: type == AssetType.insurance
                    ? 'Value today'
                    : 'Balance today',
                prefixText: '₹ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) => _amount(v, required: false),
            ),
          ),
        ],
      ),
      if (showRate) ...[
        const _Gap(),
        TextFormField(
          controller: _rate,
          decoration: InputDecoration(
            labelText: type == AssetType.nps
                ? 'Expected growth (optional)'
                : 'Interest rate',
            suffixText: '%',
            helperText: type == AssetType.ppf
                ? 'PPF rate is set by the government each quarter'
                : null,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) => _amount(v, required: false),
        ),
      ],
      const _Gap(),
      _DateField(
        label: 'Opened on (optional)',
        value: _startDate,
        onTap: () =>
            _pickDate(initial: _startDate, onPicked: (d) => _startDate = d),
      ),
      if (type == AssetType.ppf || type == AssetType.insurance) ...[
        const _Gap(),
        _DateField(
          label: 'Matures on (optional)',
          value: _maturityDate,
          onTap: () => _pickDate(
            initial: _maturityDate,
            onPicked: (d) => _maturityDate = d,
          ),
        ),
      ],
      const _Gap(),
    ];
  }
}

extension on AssetType {
  bool get isRecurringType => this == AssetType.recurringDeposit;
}

class _Gap extends StatelessWidget {
  const _Gap();

  @override
  Widget build(BuildContext context) => const SizedBox(height: 14);
}

/// A tappable read-only field that opens a date picker.
class _DateField extends FormField<DateTime> {
  _DateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    bool required = false,
  }) : super(
         initialValue: value,
         validator: (_) => required && value == null ? 'Required' : null,
         builder: (state) {
           final context = state.context;
           return InkWell(
             onTap: onTap,
             borderRadius: BorderRadius.circular(14),
             child: InputDecorator(
               decoration: InputDecoration(
                 labelText: label,
                 errorText: state.errorText,
                 suffixIcon: const Icon(
                   Icons.calendar_today_outlined,
                   size: 20,
                 ),
               ),
               isEmpty: value == null,
               child: Text(
                 value == null ? '' : formatDate(value),
                 style: Theme.of(context).textTheme.bodyLarge
                     ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
               ),
             ),
           );
         },
       );
}
