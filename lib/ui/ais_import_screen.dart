import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../data/providers.dart';
import '../logic/ais_parser.dart';
import '../logic/ais_pdf.dart';
import '../models/ais.dart';
import '../models/member.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

/// Import a member's AIS PDF: pick the file, unlock it, check what was read,
/// save. The PDF and its password never leave the phone; only the extracted
/// numbers are saved.
class AisImportScreen extends ConsumerStatefulWidget {
  const AisImportScreen({super.key, this.memberId, this.pickFile});

  final String? memberId;

  /// Tests replace the system file picker.
  final Future<(String, Uint8List)?> Function()? pickFile;

  @override
  ConsumerState<AisImportScreen> createState() => _AisImportScreenState();
}

class _AisImportScreenState extends ConsumerState<AisImportScreen> {
  String? _memberId;
  String? _fileName;
  Uint8List? _bytes;
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  AisParseResult? _result;

  @override
  void initState() {
    super.initState();
    _memberId = widget.memberId;
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Member? _member(List<Member> members) =>
      members.where((m) => m.id == _memberId).firstOrNull;

  String? _prefilledFor;

  /// Fills the password from the member's PAN + date of birth, once per member.
  void _prefillPassword(List<Member> members) {
    if (_prefilledFor == _memberId) return;
    final m = _member(members);
    if (m == null) return;
    _prefilledFor = _memberId;
    final p = aisPasswordFor(m);
    if (p != null) _password.text = p;
  }

  Future<void> _pick() async {
    setState(() => _error = null);
    final picked = widget.pickFile != null
        ? await widget.pickFile!()
        : await _systemPick();
    if (picked == null) return;
    setState(() {
      _fileName = picked.$1;
      _bytes = picked.$2;
      _result = null;
    });
  }

  Future<(String, Uint8List)?> _systemPick() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (f == null) return null;
    return (f.name, await f.readAsBytes());
  }

  Future<void> _read() async {
    final bytes = _bytes;
    if (bytes == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    // Let the spinner paint before the (synchronous) PDF work.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      final r = readAisPdf(bytes, password: _password.text.trim());
      setState(() => _result = r);
      if (!r.looksLikeAis) {
        setState(() => _error = 'This doesn\'t look like an AIS PDF.');
      }
    } on AisPdfException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Couldn\'t read the PDF: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final r = _result;
    final memberId = _memberId;
    if (r == null || memberId == null) return;
    final statement = r.toStatement(memberId);
    await ref.read(repositoryProvider)?.saveAisStatement(statement);
    if (!mounted) return;
    showSnack(context, 'AIS for ${statement.year.label} saved');
    Navigator.of(context).pop(statement);
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    _memberId ??=
        members.where((m) => m.isSelf).firstOrNull?.id ??
        members.firstOrNull?.id;
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('Import AIS')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'On the income tax portal, open AIS → Annual Information Statement '
            '→ Download → PDF. Then pick that file here.',
            style: t.bodyMedium?.copyWith(color: c.muted),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: members.any((m) => m.id == _memberId)
                ? _memberId
                : null,
            decoration: const InputDecoration(labelText: 'Whose AIS'),
            items: [
              for (final m in members)
                DropdownMenuItem(value: m.id, child: Text(m.name)),
            ],
            onChanged: (v) => setState(() {
              _memberId = v;
              _password.clear();
              _prefillPassword(members);
              _result = null;
            }),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_fileName ?? 'Choose AIS PDF'),
          ),
          const SizedBox(height: 14),
          Builder(
            builder: (context) {
              if (_prefilledFor != _memberId) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _prefillPassword(members));
                });
              }
              final hasAuto =
                  _member(members) != null &&
                  aisPasswordFor(_member(members)!) != null;
              return TextField(
                controller: _password,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'PDF password',
                  helperText: hasAuto
                      ? 'Filled in from their PAN and date of birth'
                      : 'PAN in small letters + date of birth DDMMYYYY',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _bytes == null || _busy ? null : _read,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Read AIS'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: t.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          if (result != null && result.looksLikeAis) ...[
            const SizedBox(height: 20),
            _Preview(result: result),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text('Save AIS for ${result.year?.label ?? 'this year'}'),
            ),
          ],
          if (result != null &&
              (result.records.isEmpty || !result.looksLikeAis)) ...[
            const SizedBox(height: 16),
            SectionCard(
              title: 'Nothing found?',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'If your AIS has entries but none were read, copy the text the '
                    'app found and share it (hide PAN and names) so the reader can be fixed.',
                    style: t.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: result.lines.join('\n')),
                      );
                      showSnack(context, 'Copied ${result.lines.length} lines');
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy text read from PDF'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'The PDF and password stay on this phone. Only the amounts are saved.',
            style: t.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.result});

  final AisParseResult result;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = result.toStatement('');
    final tds = s.tdsRecords.toList();
    final others = result.records.where((r) => !r.isTds && !r.isTcs).toList();
    return SectionCard(
      title: 'Found in AIS · ${result.year?.label ?? 'year not found'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatGrid([
            Stat('TDS / TCS deducted', formatInr(s.totalTds)),
            Stat('Sources', '${result.records.length}'),
            if (result.payments.isNotEmpty)
              Stat(
                'Tax paid',
                formatInr(result.payments.fold(0.0, (a, p) => a + p.amount)),
              ),
            if (result.refunds.isNotEmpty)
              Stat(
                'Refunds',
                formatInr(result.refunds.fold(0.0, (a, r) => a + r.amount)),
              ),
          ]),
          if (result.records.isEmpty) ...[
            const SizedBox(height: 12),
            Text('No entries found in this AIS.', style: t.bodyMedium),
          ],
          for (final r in [...tds, ...others]) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 10),
            AisRecordTile(record: r),
          ],
        ],
      ),
    );
  }
}

/// One AIS information row: source, what it is, amount and TDS.
class AisRecordTile extends StatelessWidget {
  const AisRecordTile({super.key, required this.record});

  final AisRecord record;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = record;
    final last = r.lastDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                r.source.isEmpty ? r.code : r.source,
                style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Text(formatInr(r.total), style: t.titleSmall),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                [
                  r.description.isEmpty ? r.code : r.description,
                  if (last != null) 'up to ${formatDate(last)}',
                ].join(' · '),
                style: t.bodySmall,
              ),
            ),
            if (r.isTds || r.isTcs)
              Text(
                '${r.isTcs ? 'TCS' : 'TDS'} ${formatInr(r.tdsDeducted)}',
                style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ],
    );
  }
}
