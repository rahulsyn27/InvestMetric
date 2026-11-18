import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/app.dart';
import 'package:invest_tracker/data/providers.dart';
import 'package:invest_tracker/data/repository.dart';
import 'package:invest_tracker/models/investment.dart';
import 'package:invest_tracker/models/member.dart';
import 'package:invest_tracker/ui/home_shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Widget testApp(InMemoryRepository repo) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    currentUserProvider.overrideWithValue(null),
    todayProvider.overrideWithValue(DateTime(2026, 11, 17)),
  ],
  child: const InvestTrackerApp(home: HomeShell()),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('home shows totals and upcoming dates', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
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

    await tester.tap(find.text('Interest').last);
    await tester.pumpAndSettle();
    expect(find.text('Interest & TDS'), findsOneWidget);
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
}
