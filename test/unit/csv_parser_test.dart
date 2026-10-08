import 'package:flutter_test/flutter_test.dart';
import 'package:alibaba/features/transactions/data/csv_parser.dart';
import 'package:alibaba/features/transactions/data/demo_csv_data.dart';
import 'package:alibaba/features/transactions/domain/transaction.dart';

void main() {
  group('CsvParser — RFC 4180 CSV String Tokenizer', () {
    test('parses simple unquoted CSV lines', () {
      const csv =
          'Date,Amount,Description\n2026-08-01,100.50,Sales\n2026-08-02,50.00,Office Supplies';
      final rows = CsvParser.parseCsvString(csv);

      expect(rows.length, 3);
      expect(rows[0], ['Date', 'Amount', 'Description']);
      expect(rows[1], ['2026-08-01', '100.50', 'Sales']);
      expect(rows[2], ['2026-08-02', '50.00', 'Office Supplies']);
    });

    test('parses CSV with quoted fields and embedded commas', () {
      const csv =
          'Date,Amount,Description\n2026-08-01,1500.00,"Acme Corp, LLC"\n2026-08-02,25.00,"Coffee, Snacks and Drinks"';
      final rows = CsvParser.parseCsvString(csv);

      expect(rows.length, 3);
      expect(rows[1][2], 'Acme Corp, LLC');
      expect(rows[2][2], 'Coffee, Snacks and Drinks');
    });

    test('parses CSV with escaped quotes', () {
      const csv =
          'Date,Amount,Description\n2026-08-01,200.00,"Item with ""quotes"""';
      final rows = CsvParser.parseCsvString(csv);

      expect(rows[1][2], 'Item with "quotes"');
    });
  });

  group('CsvParser — Money Normalization', () {
    test('parses plain numeric strings', () {
      expect(CsvParser.parseMoney('1250.50'), 1250.50);
      expect(CsvParser.parseMoney('45'), 45.0);
    });

    test('parses currency symbols and commas', () {
      expect(CsvParser.parseMoney('\$1,250.00'), 1250.00);
      expect(CsvParser.parseMoney('€ 2,450.75'), 2450.75);
      expect(CsvParser.parseMoney('₹15,000.00'), 15000.00);
      expect(CsvParser.parseMoney('£850.50'), 850.50);
    });

    test('parses negative amounts and parenthesis notation', () {
      expect(CsvParser.parseMoney('-450.00'), -450.00);
      expect(CsvParser.parseMoney('(450.00)'), -450.00);
      expect(CsvParser.parseMoney('(\$1,250.00)'), -1250.00);
    });

    test('returns null for empty or non-numeric strings', () {
      expect(CsvParser.parseMoney(''), null);
      expect(CsvParser.parseMoney('N/A'), null);
      expect(CsvParser.parseMoney('abc'), null);
    });
  });

  group('CsvParser — Date Parsing', () {
    test('parses YYYY-MM-DD and ISO 8601', () {
      final d1 = CsvParser.parseDate('2026-08-31');
      expect(d1, DateTime.utc(2026, 8, 31));

      final d2 = CsvParser.parseDate('2026-09-04T12:00:00Z');
      expect(d2?.year, 2026);
      expect(d2?.month, 9);
      expect(d2?.day, 4);
    });

    test('parses DD/MM/YYYY and MM/DD/YYYY formats', () {
      // Unambiguous DD/MM/YYYY
      final d1 = CsvParser.parseDate('31/08/2026');
      expect(d1, DateTime.utc(2026, 8, 31));

      // Unambiguous MM/DD/YYYY
      final d2 = CsvParser.parseDate('08/25/2026');
      expect(d2, DateTime.utc(2026, 8, 25));

      // Explicit format override
      final d3 = CsvParser.parseDate(
        '05/08/2026',
        format: CsvDateFormat.ddMmYyyy,
      );
      expect(d3, DateTime.utc(2026, 8, 5));

      final d4 = CsvParser.parseDate(
        '05/08/2026',
        format: CsvDateFormat.mmDdYyyy,
      );
      expect(d4, DateTime.utc(2026, 5, 8));
    });

    test('returns null for invalid dates', () {
      expect(CsvParser.parseDate('invalid-date'), null);
      expect(CsvParser.parseDate(''), null);
    });
  });

  group('CsvParser — Auto Header Detection', () {
    test('detects standard bank export headers with Debit/Credit columns', () {
      final headers = [
        'Date',
        'Narration',
        'Withdrawal (Dr)',
        'Deposit (Cr)',
        'Balance',
        'Reference No',
      ];
      final mapping = CsvParser.autoDetectMapping(headers);

      expect(mapping.dateColumn, 'Date');
      expect(mapping.debitColumn, 'Withdrawal (Dr)');
      expect(mapping.creditColumn, 'Deposit (Cr)');
      expect(
        mapping.amountStrategy,
        CsvAmountStrategy.separateDebitCreditColumns,
      );
      expect(mapping.descriptionColumn, 'Narration');
      expect(mapping.referenceColumn, 'Reference No');
    });

    test('detects single signed amount schema', () {
      final headers = [
        'Transaction Date',
        'Transaction Details',
        'Amount',
        'Category',
      ];
      final mapping = CsvParser.autoDetectMapping(headers);

      expect(mapping.dateColumn, 'Transaction Date');
      expect(mapping.amountColumn, 'Amount');
      expect(mapping.descriptionColumn, 'Transaction Details');
      expect(mapping.categoryColumn, 'Category');
      expect(mapping.amountStrategy, CsvAmountStrategy.singleSignedAmount);
    });
  });

  group('CsvParser — Row Processing and Validation', () {
    test('processes mixed valid and invalid rows correctly', () {
      final headers = ['Date', 'Amount', 'Description', 'Category'];
      final rawRows = [
        [
          '2026-08-01',
          '4250.00',
          'Client Retainer',
          'Sales Revenue',
        ], // Valid Income
        ['2026-08-02', '-780.00', 'Office Rent', 'Rent'], // Valid Expense
        ['invalid-date', '100.00', 'Bad Date Test', 'Supplies'], // Invalid Date
        [
          '2026-08-03',
          '0.00',
          'Zero Amount Test',
          'Other Expense',
        ], // Invalid Amount
        [
          '2026-08-04',
          '-350.00',
          'Software Subscription',
          'Software',
        ], // Valid Expense
      ];

      final mapping = CsvColumnMapping(
        dateColumn: 'Date',
        amountColumn: 'Amount',
        descriptionColumn: 'Description',
        categoryColumn: 'Category',
        amountStrategy: CsvAmountStrategy.singleSignedAmount,
      );

      final result = CsvParser.processRows(
        headers: headers,
        rawRows: rawRows,
        mapping: mapping,
        businessId: 'biz-123',
        currency: 'USD',
      );

      expect(result.totalCount, 5);
      expect(result.validCount, 3);
      expect(result.invalidCount, 2);
      expect(result.totalIncome, 4250.00);
      expect(result.totalExpenses, 1130.00); // 780 + 350

      final valid1 = result.validRows[0].transaction!;
      expect(valid1.transactionType, TransactionType.income);
      expect(valid1.amount, 4250.00);
      expect(valid1.category, 'Sales Revenue');

      final valid2 = result.validRows[1].transaction!;
      expect(valid2.transactionType, TransactionType.expense);
      expect(valid2.amount, 780.00);
      expect(valid2.category, 'Rent');
    });

    test('detects probable duplicate transactions', () {
      final existing = [
        Transaction(
          id: 't-1',
          businessId: 'biz-123',
          transactionDate: DateTime.utc(2026, 8, 1),
          transactionType: TransactionType.income,
          category: 'Sales Revenue',
          amount: 4250.00,
          description: 'Client Retainer',
          createdAt: DateTime.utc(2026, 8, 1),
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      ];

      final headers = ['Date', 'Amount', 'Description'];
      final rawRows = [
        ['2026-08-01', '4250.00', 'Client Retainer'], // Duplicate
        ['2026-08-05', '1200.00', 'New Project Payment'], // New
      ];

      final mapping = CsvColumnMapping(
        dateColumn: 'Date',
        amountColumn: 'Amount',
        descriptionColumn: 'Description',
        amountStrategy: CsvAmountStrategy.singleSignedAmount,
      );

      final result = CsvParser.processRows(
        headers: headers,
        rawRows: rawRows,
        mapping: mapping,
        businessId: 'biz-123',
        existingTransactions: existing,
      );

      expect(result.validCount, 2);
      expect(result.duplicateCount, 1);
      expect(result.validRows[0].isDuplicate, true);
      expect(result.validRows[1].isDuplicate, false);
    });
  });

  group('DemoCsvData — Hackathon Sample Integrity & Pipeline Compatibility', () {
    test('parses DemoCsvData accurately and auto-detects all column mappings', () {
      final parsed = CsvParser.parseCsvString(DemoCsvData.sampleCsv);
      expect(parsed.length, 21); // 1 header row + 20 data rows

      final headers = parsed.first;
      expect(headers, ['Date', 'Description', 'Category', 'Amount', 'Type', 'PaymentStatus']);

      final mapping = CsvParser.autoDetectMapping(headers);
      expect(mapping.dateColumn, 'Date');
      expect(mapping.amountColumn, 'Amount');
      expect(mapping.typeColumn, 'Type');
      expect(mapping.descriptionColumn, 'Description');
      expect(mapping.categoryColumn, 'Category');
      expect(mapping.paymentStatusColumn, 'PaymentStatus');
      expect(mapping.amountStrategy, CsvAmountStrategy.singleAmountWithTypeColumn);

      final rows = parsed.skip(1).toList();
      expect(rows.length, 20); // within 15-25 requirement

      final result = CsvParser.processRows(
        headers: headers,
        rawRows: rows,
        mapping: mapping,
        businessId: 'biz-demo-100',
      );

      expect(result.totalCount, 20);
      expect(result.validCount, 20);
      expect(result.invalidCount, 0);

      // Verify income and expenses both exist
      expect(result.totalIncome, greaterThan(0));
      expect(result.totalExpenses, greaterThan(0));

      final incomeRows = result.validRows
          .where((r) => r.transaction!.transactionType == TransactionType.income)
          .toList();
      final expenseRows = result.validRows
          .where((r) => r.transaction!.transactionType == TransactionType.expense)
          .toList();

      expect(incomeRows.isNotEmpty, true);
      expect(expenseRows.isNotEmpty, true);

      // Verify multiple categories exist
      final categories = result.validRows.map((r) => r.transaction!.category).toSet();
      expect(categories.length, greaterThanOrEqualTo(8));

      // Verify data spans multiple dates
      final dates = result.validRows.map((r) => r.transaction!.transactionDate).toSet();
      expect(dates.length, greaterThanOrEqualTo(10));
    });
  });
}
