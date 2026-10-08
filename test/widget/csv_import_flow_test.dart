import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alibaba/features/transactions/data/demo_csv_data.dart';
import 'package:alibaba/features/transactions/domain/transaction.dart';
import 'package:alibaba/features/transactions/presentation/csv_import_flow.dart';

void main() {
  testWidgets('CSV Import Flow — Full Demo CSV Journey (Select -> Map -> Validate -> Done)',
      (tester) async {
    // Set a tablet/desktop sized test surface
    tester.view.physicalSize = const Size(1024, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    List<Transaction> importedTransactions = [];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CsvImportFlow(
            businessId: 'biz-test-1',
            currency: 'USD',
            onImportComplete: (transactions) async {
              importedTransactions = transactions;
              return transactions.length;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Initial State: Step 1 (Select)
    expect(find.text('Choose CSV from Device'), findsOneWidget);
    expect(find.text('OR PASTE CSV TEXT'), findsOneWidget);
    expect(find.text('Browse File'), findsOneWidget);
    expect(find.text('Use Demo CSV'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    // 2. Click "Use Demo CSV"
    await tester.tap(find.text('Use Demo CSV'));
    await tester.pumpAndSettle();

    // Verify sample file name and CSV text populated
    expect(find.text(DemoCsvData.sampleFileName), findsOneWidget);
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller?.text, DemoCsvData.sampleCsv);

    // 3. Click "Continue" -> Advances to Step 2 (Map)
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm Column Mappings'), findsOneWidget);
    expect(find.text('Validate & Preview'), findsOneWidget);

    // 4. Click "Validate & Preview" -> Advances to Step 3 (Validate)
    await tester.ensureVisible(find.text('Validate & Preview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Validate & Preview'));
    await tester.pumpAndSettle();

    expect(find.text('Valid Rows'), findsOneWidget);
    expect(find.text('Import (20)'), findsOneWidget);

    // Verify transactions haven't been committed to callback yet
    expect(importedTransactions.isEmpty, true);

    // 5. Click "Import (20)" -> Completes import
    await tester.ensureVisible(find.text('Import (20)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import (20)'));
    await tester.pumpAndSettle();

    expect(importedTransactions.length, 20);
    expect(find.text('Import Complete!'), findsOneWidget);
    expect(find.text('View in Transactions'), findsOneWidget);
  });

  testWidgets('CSV Import Flow — Manual Paste Flow Works Independently',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CsvImportFlow(
            businessId: 'biz-test-2',
            currency: 'USD',
            onImportComplete: (transactions) async => transactions.length,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Enter manual text
    const manualCsv =
        'Date,Description,Category,Amount,Type\n2026-08-01,Manual Sales,Sales Revenue,150.00,income';
    await tester.enterText(find.byType(TextField), manualCsv);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm Column Mappings'), findsOneWidget);
  });

  testWidgets('CSV Import Flow — Responsive Layout on Mobile Screen',
      (tester) async {
    // Narrow mobile width (360px)
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CsvImportFlow(
            businessId: 'biz-test-3',
            currency: 'USD',
            onImportComplete: (transactions) async => transactions.length,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // All buttons still present and no layout overflow
    expect(find.text('Browse File'), findsOneWidget);
    expect(find.text('Use Demo CSV'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
