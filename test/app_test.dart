import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/app.dart';
import 'package:invest_tracker/data/providers.dart';
import 'package:invest_tracker/data/repository.dart';
import 'package:invest_tracker/models/investment.dart';
import 'package:invest_tracker/models/member.dart';
import 'package:invest_tracker/models/snapshot.dart';
import 'package:invest_tracker/ui/home_shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:invest_tracker/ui/ais_import_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invest_tracker/logic/ais_parser.dart';
import 'package:invest_tracker/logic/ais_pdf.dart';

import 'support/ais_fixture.dart';

AisParseResult readAisForTest() =>
    readAisPdf(buildAisFixturePdf(), password: fixturePassword);

InMemoryRepository sampleRepo() => InMemoryRepository(
  members: [
    const Member(
      id: 'self',
      name: 'Ravi Kumar',
      relation: 'Self',
      isSelf: true,
    ),
    Member(
      id: 'mom',
      name: 'Asha Kumar',
      relation: 'Mother',
      dateOfBirth: DateTime(1962, 5, 1),
    ),
  ],
  investments: [
    Investment(
      id: 'fd1',
      memberId: 'mom',
      type: AssetType.fixedDeposit,
      name: 'SBI FD',
      institution: 'SBI',
      principal: 500000,
      ratePct: 7.1,
      startDate: DateTime(2025, 11, 28),
      maturityDate: DateTime(2026, 11, 28),
      tdsApplicable: true,
    ),
    const Investment(
      id: 'mf1',
      memberId: 'self',
      type: AssetType.mutualFund,
      name: 'Nifty 50 Index Fund',
      units: 4512.318,
      avgCost: 209.2,
      currentPrice: 274.91,
      sipAmount: 10000,
      sipDay: 20,
    ),
    const Investment(
      id: 'ppf1',
      memberId: 'self',
      type: AssetType.ppf,
      name: 'PPF – SBI',
      investedAmount: 840000,
      currentValue: 1126310,
      ratePct: 7.1,
    ),
  ],
);

Widget testApp(
  InMemoryRepository repo, {
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    currentUserProvider.overrideWithValue(null),
    todayProvider.overrideWithValue(DateTime(2026, 11, 17)),
    ...overrides,
  ],
  child: const InvestTrackerApp(home: HomeShell()),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  returnsTests();

  testWidgets('home shows totals and upcoming dates', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1800));
    await tester.pumpWidget(testApp(sampleRepo()));
    await tester.pumpAndSettle();

    expect(find.text('Portfolio'), findsOneWidget);
    expect(find.text('Current value'), findsOneWidget);
    // ~5,35,000 FD + 12,40,481 MF + 11,26,310 PPF
    expect(find.textContaining('₹29,'), findsWidgets);
    expect(find.text('Coming up'), findsOneWidget);
    expect(find.textContaining('SBI FD matures'), findsOneWidget);
    expect(find.text('All family'), findsOneWidget);
  });

  testWidgets('every tab opens without errors', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    await tester.pumpWidget(testApp(sampleRepo()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Holdings').last);
    await tester.pumpAndSettle();
    expect(find.text('Nifty 50 Index Fund'), findsOneWidget);
    expect(find.text('Fixed deposit'), findsOneWidget);

    await tester.tap(find.text('Calendar').last);
    await tester.pumpAndSettle();
    expect(find.text('Show tax deadlines'), findsOneWidget);

    await tester.tap(find.text('Tax').last);
    await tester.pumpAndSettle();
    expect(find.text('Tax & TDS'), findsOneWidget);
    expect(find.text('SBI'), findsOneWidget);
    expect(find.textContaining('SENIOR CITIZEN'), findsOneWidget);

    await tester.tap(find.text('Family').last);
    await tester.pumpAndSettle();
    expect(find.text('Asha Kumar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filtering by member and adding an FD', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    final repo = sampleRepo();
    await tester.pumpWidget(testApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Asha'));
    await tester.pumpAndSettle();
    expect(find.text('Holdings').first, findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fixed deposit').last);
    await tester.pumpAndSettle();
    expect(find.text('Add Fixed deposit'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Canara FD',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount deposited'),
      '3,50,000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Interest rate'),
      '7',
    );

    // Saving without dates shows validation errors and keeps the form open.
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Add'),
      300,
      scrollable: find
          .descendant(of: find.byType(Form), matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsWidgets);
    expect(repo.investments, hasLength(3));
    await tester.pageBack();
    await tester.pumpAndSettle();

    // A PPF needs no dates: it saves, for the member picked in the filter.
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PPF').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'PPF – Post Office',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Total put in'),
      '200000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Balance today'),
      '260000',
    );
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Add'),
      300,
      scrollable: find
          .descendant(of: find.byType(Form), matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(repo.investments, hasLength(4));
    final added = repo.investments.firstWhere(
      (i) => i.name == 'PPF – Post Office',
    );
    expect(added.memberId, 'mom');
    expect(added.currentValue, 260000);
    expect(find.text('Portfolio'), findsOneWidget);
  });

  testWidgets('importing an AIS PDF', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    final repo = InMemoryRepository(
      members: [
        Member(
          id: 'mom',
          name: 'Asha Kumar',
          relation: 'Mother',
          pan: 'ABCDE1234F',
          dateOfBirth: DateTime(1960, 1, 1),
        ),
      ],
    );
    final pdf = buildAisFixturePdf();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          currentUserProvider.overrideWithValue(null),
          todayProvider.overrideWithValue(DateTime(2026, 11, 18)),
        ],
        child: InvestTrackerApp(
          home: AisImportScreen(pickFile: () async => ('AIS.pdf', pdf)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose AIS PDF'));
    await tester.pumpAndSettle();
    expect(find.text('AIS.pdf'), findsOneWidget);
    // Password was filled in from PAN + date of birth.
    expect(
      find.text('Filled in from their PAN and date of birth'),
      findsOneWidget,
    );

    await tester.tap(find.text('Read AIS'));
    await tester.pumpAndSettle();
    expect(find.text('Found in AIS · 2026-27'), findsOneWidget);
    expect(find.text('ACME STEEL LIMITED'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Save AIS for 2026-27'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save AIS for 2026-27'));
    await tester.pumpAndSettle();
    expect(repo.aisStatements, hasLength(1));
    expect(repo.aisStatements.single.memberId, 'mom');
    expect(repo.aisStatements.single.totalTds, 17483 + 16803 + 1775);
  });

  testWidgets('Tax tab shows the imported AIS', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    final repo = sampleRepo();
    await tester.pumpWidget(testApp(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tax').last);
    await tester.pumpAndSettle();
    expect(find.text('Check against AIS'), findsOneWidget);

    await repo.saveAisStatement(readAisForTest().toStatement('mom'));
    await tester.pumpAndSettle();
    expect(find.text('AIS · ASHA KUMAR'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Interest: app vs AIS'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Interest: app vs AIS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _mon = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// A one-line AMFI NAV history file: NAV 120 on whatever day is asked for.
String fakeNavDay(DateTime d) =>
    '119551;Index Fund - Direct - Growth;Direct Plan;Growth;INF1;;120.0;'
    '${d.day.toString().padLeft(2, '0')}-${_mon[d.month - 1]}-${d.year}\n';

Investment _fund() => Investment(
  id: 'mf',
  memberId: 'self',
  type: AssetType.mutualFund,
  name: 'Index Fund',
  units: 100,
  avgCost: 100,
  currentPrice: 150,
  schemeCode: '119551',
  startDate: DateTime(2025, 1, 1),
);

const _self = Member(id: 'self', name: 'Ravi', relation: 'Self', isSelf: true);

void returnsTests() {
  testWidgets('returns card: periods, past NAVs and snapshots', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    final repo = InMemoryRepository(
      members: const [_self],
      investments: [
        _fund(),
        const Investment(
          id: 'ppf',
          memberId: 'self',
          type: AssetType.ppf,
          name: 'PPF',
          investedAmount: 95000,
          currentValue: 106000,
        ),
      ],
      snapshots: [
        ValueSnapshot(
          date: DateTime(2026, 10, 1),
          items: {'ppf': const SnapshotItem(value: 100000, invested: 90000)},
        ),
      ],
    );
    final asked = <DateTime>[];
    await tester.pumpWidget(
      testApp(
        repo,
        overrides: [
          navDayFetcherProvider.overrideWithValue((day) async {
            asked.add(day);
            return fakeNavDay(day);
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Default 1Y: the fund moved 120 → 150 on 100 units. No PPF value was
    // saved that far back, so it is left out.
    expect(find.text('Returns'), findsOneWidget);
    expect(find.text('Gain since 17 Nov 2025'), findsOneWidget);
    expect(find.text('+₹3,000'), findsNWidgets(2)); // gain, market change
    expect(find.text('+25.0%'), findsOneWidget);
    expect(find.textContaining('Not counted: PPF'), findsOneWidget);
    expect(asked, [DateTime(2025, 11, 17)]);

    // Today's snapshot was saved for later.
    expect(repo.snapshots.map((s) => s.docId), contains('2026-11-17'));

    // 1M: the PPF has a snapshot from 1 Oct. ₹5,000 added, ₹1,000 interest.
    await tester.tap(find.widgetWithText(ChoiceChip, '1M'));
    await tester.pumpAndSettle();
    expect(find.text('Gain since 17 Oct 2026'), findsOneWidget);
    expect(find.textContaining('Not counted'), findsNothing);
    expect(find.text('+₹4,000'), findsOneWidget);
    expect(find.text('₹1,000'), findsOneWidget); // interest earned
    expect(asked.last, DateTime(2026, 10, 17));

    // All time needs no downloads.
    final calls = asked.length;
    await tester.tap(find.widgetWithText(ChoiceChip, 'All time'));
    await tester.pumpAndSettle();
    expect(find.text('Gain since you started'), findsOneWidget);
    expect(asked.length, calls);

    // The holding's own card.
    await tester.tap(find.widgetWithText(ChoiceChip, '1Y'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Holdings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Index Fund'));
    await tester.pumpAndSettle();
    expect(find.text('Returns'), findsOneWidget);
    expect(find.text('Market change'), findsOneWidget);
    expect(find.text('Interest earned'), findsNothing);
    expect(find.text('+25.0%'), findsOneWidget);
    // Already downloaded once: not fetched again.
    expect(asked.where((d) => d == DateTime(2025, 11, 17)), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('returns card offers a retry when AMFI fails', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    var fail = true;
    final repo = InMemoryRepository(
      members: const [_self],
      investments: [_fund()],
    );
    await tester.pumpWidget(
      testApp(
        repo,
        overrides: [
          navDayFetcherProvider.overrideWithValue((day) async {
            if (fail) throw Exception('offline');
            return fakeNavDay(day);
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Couldn\'t get past NAVs from AMFI.'), findsOneWidget);
    fail = false;
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Couldn\'t get past NAVs from AMFI.'), findsNothing);
    expect(find.text('+25.0%'), findsOneWidget);
  });
}
