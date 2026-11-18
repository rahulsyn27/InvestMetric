import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/dates.dart';
import '../data/providers.dart';
import '../logic/valuation.dart';
import '../models/investment.dart';
import '../models/member.dart';
import '../core/money.dart';
import '../theme/app_theme.dart';

/// Family profiles and app settings.
class FamilyScreen extends ConsumerWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    final investments =
        ref.watch(investmentsProvider).value ?? const <Investment>[];
    final today = ref.watch(todayProvider);
    final user = ref.watch(currentUserProvider);
    final mode = ref.watch(themeModeProvider);
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Family')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(
            'Add a profile for everyone whose investments you look after. '
            'They don\'t need the app or a login: you manage it all from here.',
            style: t.bodyMedium?.copyWith(color: context.colors.muted),
          ),
          const SizedBox(height: 14),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final m in members) ...[
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                      foregroundColor: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer,
                      child: Text(m.initials),
                    ),
                    title: Text(m.name),
                    subtitle: Text(
                      [
                        if (m.relation.isNotEmpty) m.relation,
                        formatInrCompact(
                          totalValuation(
                            investments.where((i) => i.memberId == m.id),
                            today,
                          ).current,
                        ),
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MemberFormScreen(existing: m),
                      ),
                    ),
                  ),
                  const Divider(),
                ],
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_add_alt_1_outlined),
                  ),
                  title: const Text('Add family member'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MemberFormScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text('APPEARANCE', style: t.labelSmall),
          ),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode_outlined),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode_outlined),
              ),
              ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
            ],
            selected: {mode},
            onSelectionChanged: (s) =>
                ref.read(themeModeProvider.notifier).set(s.first),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text('ACCOUNT', style: t.labelSmall),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(user?.displayName ?? 'Signed in'),
                  subtitle: Text(user?.email ?? ''),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign out'),
                  onTap: () => ref.read(authServiceProvider).signOut(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MemberFormScreen extends ConsumerStatefulWidget {
  const MemberFormScreen({super.key, this.existing});

  final Member? existing;

  @override
  ConsumerState<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends ConsumerState<MemberFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _relation = TextEditingController(
    text: widget.existing?.relation ?? '',
  );
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  late final _pan = TextEditingController(text: widget.existing?.pan ?? '');
  late DateTime? _dob = widget.existing?.dateOfBirth;

  @override
  void dispose() {
    for (final c in [_name, _relation, _email, _pan]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final m = Member(
      id: widget.existing?.id ?? '',
      name: _name.text.trim(),
      relation: _relation.text.trim(),
      email: _email.text.trim(),
      pan: _pan.text.trim().toUpperCase(),
      dateOfBirth: _dob,
      isSelf: widget.existing?.isSelf ?? false,
    );
    await ref.read(repositoryProvider)?.saveMember(m);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final m = widget.existing!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${m.name}?'),
        content: const Text(
          'Their profile and all their investments will be deleted.',
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
    if (ok != true || !mounted) return;
    if (ref.read(selectedMemberProvider) == m.id) {
      ref.read(selectedMemberProvider.notifier).select(null);
    }
    await ref.read(repositoryProvider)?.deleteMember(m.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final age = _dob == null
        ? null
        : Member(id: '', name: '', dateOfBirth: _dob).ageOn(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: Text(existing == null ? 'Add member' : 'Edit member'),
        actions: [
          if (existing != null && !existing.isSelf)
            IconButton(
              tooltip: 'Delete',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _relation,
              decoration: const InputDecoration(
                labelText: 'Relation',
                hintText: 'Mother, Sister, Self…',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(
                labelText: 'Email on their investments (optional)',
                helperText:
                    'Where their CAS and bank statements arrive. Not a login.',
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _pan,
              decoration: const InputDecoration(
                labelText: 'PAN (optional)',
                helperText: 'Used later to match AIS and CAS statements',
              ),
              textCapitalization: TextCapitalization.characters,
              validator: (v) {
                final s = (v ?? '').trim().toUpperCase();
                if (s.isEmpty) return null;
                return RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(s)
                    ? null
                    : 'PAN looks like ABCDE1234F';
              },
            ),
            const SizedBox(height: 14),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _dob ?? DateTime(1970),
                  firstDate: DateTime(1920),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _dob = d);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date of birth (optional)',
                  helperText: age != null && age >= 60
                      ? 'Senior citizen: higher TDS limit (₹1 lakh) and Form 15H'
                      : 'Needed for senior citizen TDS limits',
                  suffixIcon: const Icon(
                    Icons.calendar_today_outlined,
                    size: 20,
                  ),
                ),
                isEmpty: _dob == null,
                child: Text(_dob == null ? '' : formatDate(_dob!)),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: Text(existing == null ? 'Add member' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
