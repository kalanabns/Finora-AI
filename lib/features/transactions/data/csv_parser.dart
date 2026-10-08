import '../domain/transaction.dart';

class TransactionCategories {
  const TransactionCategories._();

  static const List<String> incomeCategories = [
    'Sales Revenue',
    'Service Revenue',
    'Other Income',
  ];

  static const List<String> expenseCategories = [
    'Payroll',
    'Rent',
    'Utilities',
    'Marketing',
    'Inventory',
    'Supplies',
    'Software',
    'Transportation',
    'Insurance',
    'Taxes',
    'Loan Payment',
    'Professional Services',
    'Other Expense',
  ];

  static const List<String> transferCategories = [
    'Internal Transfer',
    'Owner Draw / Capital',
  ];

  static List<String> getCategoriesForType(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return incomeCategories;
      case TransactionType.expense:
        return expenseCategories;
      case TransactionType.transfer:
        return transferCategories;
    }
  }

  static String normalizeCategory(String? rawCategory, TransactionType type) {
    if (rawCategory == null || rawCategory.trim().isEmpty) {
      return type == TransactionType.income ? 'Other Income' : 'Other Expense';
    }
    final rawLower = rawCategory.trim().toLowerCase();

    // Check exact or partial match in existing lists
    final candidates = getCategoriesForType(type);
    for (final cat in candidates) {
      if (cat.toLowerCase() == rawLower) return cat;
    }

    for (final cat in candidates) {
      if (rawLower.contains(cat.toLowerCase()) ||
          cat.toLowerCase().contains(rawLower)) {
        return cat;
      }
    }

    // Default if no standard match found
    return rawCategory.trim();
  }
}

enum CsvAmountStrategy {
  singleSignedAmount,
  singleAmountWithTypeColumn,
  separateDebitCreditColumns,
}

enum CsvDateFormat {
  auto,
  yyyyMmDd, // 2026-08-31
  ddMmYyyy, // 31/08/2026 or 31-08-2026
  mmDdYyyy, // 08/31/2026 or 08-31-2026
  iso8601,
}

class CsvColumnMapping {
  CsvColumnMapping({
    this.dateColumn = '',
    this.amountColumn = '',
    this.debitColumn = '',
    this.creditColumn = '',
    this.typeColumn = '',
    this.descriptionColumn = '',
    this.categoryColumn = '',
    this.referenceColumn = '',
    this.merchantColumn = '',
    this.paymentStatusColumn = '',
    this.amountStrategy = CsvAmountStrategy.singleSignedAmount,
    this.dateFormat = CsvDateFormat.auto,
  });

  String dateColumn;
  String amountColumn;
  String debitColumn;
  String creditColumn;
  String typeColumn;
  String descriptionColumn;
  String categoryColumn;
  String referenceColumn;
  String merchantColumn;
  String paymentStatusColumn;
  CsvAmountStrategy amountStrategy;
  CsvDateFormat dateFormat;

  bool isValid() {
    if (dateColumn.isEmpty) return false;
    switch (amountStrategy) {
      case CsvAmountStrategy.singleSignedAmount:
      case CsvAmountStrategy.singleAmountWithTypeColumn:
        return amountColumn.isNotEmpty;
      case CsvAmountStrategy.separateDebitCreditColumns:
        return debitColumn.isNotEmpty && creditColumn.isNotEmpty;
    }
  }
}

class ParsedCsvRow {
  ParsedCsvRow({
    required this.rowIndex,
    required this.rawRow,
    this.transaction,
    this.errorMessage,
    this.isDuplicate = false,
  });

  final int rowIndex;
  final Map<String, String> rawRow;
  final Transaction? transaction;
  final String? errorMessage;
  bool isDuplicate;

  bool get isValid => errorMessage == null && transaction != null;
}

class CsvParseResult {
  CsvParseResult({
    required this.headers,
    required this.rows,
    required this.validRows,
    required this.invalidRows,
    required this.mapping,
    required this.totalIncome,
    required this.totalExpenses,
  });

  final List<String> headers;
  final List<ParsedCsvRow> rows;
  final List<ParsedCsvRow> validRows;
  final List<ParsedCsvRow> invalidRows;
  final CsvColumnMapping mapping;
  final double totalIncome;
  final double totalExpenses;

  int get totalCount => rows.length;
  int get validCount => validRows.length;
  int get invalidCount => invalidRows.length;
  int get duplicateCount => validRows.where((r) => r.isDuplicate).length;
}

class CsvParser {
  const CsvParser._();

  /// Robust RFC-4180 CSV String tokenizer supporting quoted fields, multiline cells, and escapes.
  static List<List<String>> parseCsvString(String csvContent) {
    final results = <List<String>>[];
    if (csvContent.trim().isEmpty) return results;

    final currentRow = <String>[];
    final currentField = StringBuffer();
    bool insideQuotes = false;
    int i = 0;
    final length = csvContent.length;

    while (i < length) {
      final char = csvContent[i];

      if (char == '"') {
        if (insideQuotes && i + 1 < length && csvContent[i + 1] == '"') {
          // Escaped double quote ("")
          currentField.write('"');
          i += 2;
          continue;
        } else {
          insideQuotes = !insideQuotes;
          i++;
          continue;
        }
      }

      if (!insideQuotes && char == ',') {
        currentRow.add(currentField.toString().trim());
        currentField.clear();
        i++;
        continue;
      }

      if (!insideQuotes && (char == '\n' || char == '\r')) {
        // Handle \r\n or \n
        if (char == '\r' && i + 1 < length && csvContent[i + 1] == '\n') {
          i++;
        }
        currentRow.add(currentField.toString().trim());
        currentField.clear();

        // Only add non-empty rows
        if (currentRow.any((field) => field.isNotEmpty)) {
          results.add(List.from(currentRow));
        }
        currentRow.clear();
        i++;
        continue;
      }

      currentField.write(char);
      i++;
    }

    if (currentField.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(currentField.toString().trim());
      if (currentRow.any((field) => field.isNotEmpty)) {
        results.add(currentRow);
      }
    }

    return results;
  }

  /// Automatically infers headers and best column mapping from CSV raw data.
  static CsvColumnMapping autoDetectMapping(List<String> headers) {
    final mapping = CsvColumnMapping();
    final lowerHeaders = headers.map((h) => h.trim().toLowerCase()).toList();

    // 1. Date Detection
    final dateKeywords = [
      'date',
      'transaction_date',
      'transaction date',
      'posted date',
      'posting date',
      'txn_date',
      'time',
    ];
    for (final kw in dateKeywords) {
      final index = lowerHeaders.indexOf(kw);
      if (index != -1) {
        mapping.dateColumn = headers[index];
        break;
      }
    }
    if (mapping.dateColumn.isEmpty) {
      for (int i = 0; i < lowerHeaders.length; i++) {
        if (lowerHeaders[i].contains('date') ||
            lowerHeaders[i].contains('time')) {
          mapping.dateColumn = headers[i];
          break;
        }
      }
    }

    // 2. Separate Debit / Credit Detection
    final debitKeywords = ['debit', 'withdrawal', 'money out', 'outflow', 'dr'];
    final creditKeywords = ['credit', 'deposit', 'money in', 'inflow', 'cr'];
    String? foundDebit;
    String? foundCredit;

    // Check exact matches or substring matches
    for (final kw in debitKeywords) {
      for (int i = 0; i < lowerHeaders.length; i++) {
        if (lowerHeaders[i] == kw || lowerHeaders[i].contains(kw)) {
          foundDebit = headers[i];
          break;
        }
      }
      if (foundDebit != null) break;
    }

    for (final kw in creditKeywords) {
      for (int i = 0; i < lowerHeaders.length; i++) {
        if (lowerHeaders[i] == kw || lowerHeaders[i].contains(kw)) {
          foundCredit = headers[i];
          break;
        }
      }
      if (foundCredit != null) break;
    }

    if (foundDebit != null &&
        foundCredit != null &&
        foundDebit != foundCredit) {
      mapping.debitColumn = foundDebit;
      mapping.creditColumn = foundCredit;
      mapping.amountStrategy = CsvAmountStrategy.separateDebitCreditColumns;
    } else {
      // 3. Amount Column Detection
      final amountKeywords = [
        'amount',
        'value',
        'transaction amount',
        'total',
        'net amount',
      ];
      for (final kw in amountKeywords) {
        final index = lowerHeaders.indexOf(kw);
        if (index != -1) {
          mapping.amountColumn = headers[index];
          break;
        }
      }
      if (mapping.amountColumn.isEmpty) {
        for (int i = 0; i < lowerHeaders.length; i++) {
          if (lowerHeaders[i].contains('amount') ||
              lowerHeaders[i].contains('value')) {
            mapping.amountColumn = headers[i];
            break;
          }
        }
      }

      // Check if there is an explicit type column
      final typeKeywords = [
        'transaction type',
        'type',
        'trans_type',
        'txn_type',
        'direction',
      ];
      for (final kw in typeKeywords) {
        for (int i = 0; i < lowerHeaders.length; i++) {
          if (lowerHeaders[i] == kw || lowerHeaders[i].contains(kw)) {
            mapping.typeColumn = headers[i];
            mapping.amountStrategy =
                CsvAmountStrategy.singleAmountWithTypeColumn;
            break;
          }
        }
        if (mapping.typeColumn.isNotEmpty) break;
      }
    }

    // 4. Description Detection
    final descKeywords = [
      'description',
      'details',
      'memo',
      'narration',
      'transaction details',
      'particulars',
      'notes',
      'payee',
    ];
    for (final kw in descKeywords) {
      for (int i = 0; i < lowerHeaders.length; i++) {
        if (lowerHeaders[i] == kw || lowerHeaders[i].contains(kw)) {
          mapping.descriptionColumn = headers[i];
          break;
        }
      }
      if (mapping.descriptionColumn.isNotEmpty) break;
    }

    // 5. Category Detection
    final catKeywords = [
      'category',
      'expense category',
      'category name',
      'tag',
    ];
    for (final kw in catKeywords) {
      for (int i = 0; i < lowerHeaders.length; i++) {
        if (lowerHeaders[i] == kw || lowerHeaders[i].contains(kw)) {
          mapping.categoryColumn = headers[i];
          break;
        }
      }
      if (mapping.categoryColumn.isNotEmpty) break;
    }

    // 6. Reference / External ID Detection
    final refKeywords = [
      'reference',
      'reference number',
      'ref',
      'transaction id',
      'txn id',
      'cheque no',
      'external_reference',
      'id',
    ];
    for (final kw in refKeywords) {
      for (int i = 0; i < lowerHeaders.length; i++) {
        if (lowerHeaders[i] == kw || lowerHeaders[i].contains(kw)) {
          mapping.referenceColumn = headers[i];
          break;
        }
      }
      if (mapping.referenceColumn.isNotEmpty) break;
    }

    // 7. Merchant / Counterparty Detection
    final merchantKeywords = [
      'merchant',
      'merchant name',
      'vendor',
      'supplier',
      'customer',
    ];
    for (final kw in merchantKeywords) {
      for (int i = 0; i < lowerHeaders.length; i++) {
        if (lowerHeaders[i] == kw || lowerHeaders[i].contains(kw)) {
          mapping.merchantColumn = headers[i];
          break;
        }
      }
      if (mapping.merchantColumn.isNotEmpty) break;
    }

    // 8. Payment Status Detection
    final statusKeywords = [
      'payment status',
      'paymentstatus',
      'payment_status',
      'status',
    ];
    for (final kw in statusKeywords) {
      for (int i = 0; i < lowerHeaders.length; i++) {
        if (lowerHeaders[i] == kw || lowerHeaders[i].contains(kw)) {
          mapping.paymentStatusColumn = headers[i];
          break;
        }
      }
      if (mapping.paymentStatusColumn.isNotEmpty) break;
    }

    return mapping;
  }

  /// Parses money string into a double, handling currency symbols, negative parentheses, commas, etc.
  static double? parseMoney(String? raw) {
    if (raw == null) return null;
    var cleaned = raw.trim();
    if (cleaned.isEmpty) return null;

    bool isNegative = false;

    // Handle parentheses: (450.00) -> -450.00
    if (cleaned.startsWith('(') && cleaned.endsWith(')')) {
      isNegative = true;
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    } else if (cleaned.startsWith('-')) {
      isNegative = true;
      cleaned = cleaned.substring(1).trim();
    } else if (cleaned.startsWith('+')) {
      cleaned = cleaned.substring(1).trim();
    }

    // Remove currency symbols and whitespace
    cleaned = cleaned.replaceAll(RegExp(r'[\$\€\£\¥\₹\sA-Za-z]'), '');

    // Handle comma as decimal or thousand separator
    if (cleaned.contains(',') && cleaned.contains('.')) {
      // e.g. 1,250.50 -> remove commas
      cleaned = cleaned.replaceAll(',', '');
    } else if (cleaned.contains(',') && !cleaned.contains('.')) {
      final parts = cleaned.split(',');
      if (parts.length == 2 && parts[1].length <= 2) {
        // European style decimal separator: 1250,50 -> 1250.50
        cleaned = '${parts[0]}.${parts[1]}';
      } else {
        // Thousand separator: 1,250 -> 1250
        cleaned = cleaned.replaceAll(',', '');
      }
    }

    final parsed = double.tryParse(cleaned);
    if (parsed == null) return null;
    return isNegative ? -parsed : parsed;
  }

  /// Parses date string into DateTime, supporting multiple common formats.
  static DateTime? parseDate(
    String? raw, {
    CsvDateFormat format = CsvDateFormat.auto,
  }) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;

    // Regex match for YYYY-MM-DD or YYYY/MM/DD
    final ymdRegex = RegExp(
      r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[T\s].*)?$',
    );
    final ymdMatch = ymdRegex.firstMatch(text);
    if (ymdMatch != null &&
        (format == CsvDateFormat.auto ||
            format == CsvDateFormat.yyyyMmDd ||
            format == CsvDateFormat.iso8601)) {
      final year = int.parse(ymdMatch.group(1)!);
      final month = int.parse(ymdMatch.group(2)!);
      final day = int.parse(ymdMatch.group(3)!);
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return DateTime.utc(year, month, day);
      }
    }

    // Direct ISO 8601 parsing fallback
    try {
      final iso = DateTime.tryParse(text);
      if (iso != null &&
          (format == CsvDateFormat.auto || format == CsvDateFormat.iso8601)) {
        return DateTime.utc(
          iso.year,
          iso.month,
          iso.day,
          iso.hour,
          iso.minute,
          iso.second,
        );
      }
    } catch (_) {}

    // Regex match for 2-digit / 4-digit separator formats (DD/MM/YYYY or MM/DD/YYYY)
    final dmyRegex = RegExp(
      r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})(?:[T\s].*)?$',
    );
    final dmyMatch = dmyRegex.firstMatch(text);
    if (dmyMatch != null) {
      final first = int.parse(dmyMatch.group(1)!);
      final second = int.parse(dmyMatch.group(2)!);
      var year = int.parse(dmyMatch.group(3)!);
      if (year < 100) year += 2000;

      if (format == CsvDateFormat.ddMmYyyy) {
        final day = first;
        final month = second;
        if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
          return DateTime.utc(year, month, day);
        }
      } else if (format == CsvDateFormat.mmDdYyyy) {
        final month = first;
        final day = second;
        if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
          return DateTime.utc(year, month, day);
        }
      } else {
        // Auto-detect DD/MM vs MM/DD
        if (first > 12 && second <= 12) {
          // Definitely DD/MM/YYYY
          return DateTime.utc(year, second, first);
        } else if (second > 12 && first <= 12) {
          // Definitely MM/DD/YYYY
          return DateTime.utc(year, first, second);
        } else {
          // Default ambiguous to DD/MM/YYYY
          return DateTime.utc(year, second, first);
        }
      }
    }

    return null;
  }

  /// Processes all rows of the parsed CSV with the given mapping, business ID, and currency.
  static CsvParseResult processRows({
    required List<String> headers,
    required List<List<String>> rawRows,
    required CsvColumnMapping mapping,
    required String businessId,
    String currency = 'USD',
    List<Transaction>? existingTransactions,
  }) {
    final rows = <ParsedCsvRow>[];
    final validRows = <ParsedCsvRow>[];
    final invalidRows = <ParsedCsvRow>[];
    double totalIncome = 0.0;
    double totalExpenses = 0.0;

    final now = DateTime.now().toUtc();

    for (int i = 0; i < rawRows.length; i++) {
      final rowList = rawRows[i];
      final rowMap = <String, String>{};
      for (int h = 0; h < headers.length; h++) {
        rowMap[headers[h]] = h < rowList.length ? rowList[h] : '';
      }

      // 1. Validate and Parse Date
      final rawDate = rowMap[mapping.dateColumn];
      final date = parseDate(rawDate, format: mapping.dateFormat);
      if (date == null) {
        final parsedRow = ParsedCsvRow(
          rowIndex: i + 1,
          rawRow: rowMap,
          errorMessage: 'Missing or unparseable date: "$rawDate"',
        );
        rows.add(parsedRow);
        invalidRows.add(parsedRow);
        continue;
      }

      // 2. Validate and Parse Amount & Direction
      double amount = 0.0;
      TransactionType transactionType = TransactionType.expense;

      if (mapping.amountStrategy ==
          CsvAmountStrategy.separateDebitCreditColumns) {
        final debitStr = rowMap[mapping.debitColumn];
        final creditStr = rowMap[mapping.creditColumn];
        final debit = parseMoney(debitStr);
        final credit = parseMoney(creditStr);

        if ((debit == null || debit == 0) && (credit == null || credit == 0)) {
          final parsedRow = ParsedCsvRow(
            rowIndex: i + 1,
            rawRow: rowMap,
            errorMessage: 'Both debit and credit amounts are empty or zero.',
          );
          rows.add(parsedRow);
          invalidRows.add(parsedRow);
          continue;
        }

        if (credit != null && credit.abs() > 0) {
          amount = credit.abs();
          transactionType = TransactionType.income;
        } else if (debit != null && debit.abs() > 0) {
          amount = debit.abs();
          transactionType = TransactionType.expense;
        }
      } else if (mapping.amountStrategy ==
          CsvAmountStrategy.singleAmountWithTypeColumn) {
        final amtStr = rowMap[mapping.amountColumn];
        final parsedAmt = parseMoney(amtStr);
        if (parsedAmt == null || parsedAmt.abs() == 0) {
          final parsedRow = ParsedCsvRow(
            rowIndex: i + 1,
            rawRow: rowMap,
            errorMessage: 'Invalid or zero amount: "$amtStr"',
          );
          rows.add(parsedRow);
          invalidRows.add(parsedRow);
          continue;
        }
        amount = parsedAmt.abs();

        final typeStr = (rowMap[mapping.typeColumn] ?? '').toLowerCase();
        if (typeStr.contains('income') ||
            typeStr.contains('credit') ||
            typeStr.contains('deposit') ||
            typeStr.contains('inflow') ||
            typeStr.contains('cr')) {
          transactionType = TransactionType.income;
        } else if (typeStr.contains('transfer')) {
          transactionType = TransactionType.transfer;
        } else {
          transactionType = TransactionType.expense;
        }
      } else {
        // Single Signed Amount Strategy
        final amtStr = rowMap[mapping.amountColumn];
        final parsedAmt = parseMoney(amtStr);
        if (parsedAmt == null || parsedAmt == 0) {
          final parsedRow = ParsedCsvRow(
            rowIndex: i + 1,
            rawRow: rowMap,
            errorMessage: 'Invalid or zero amount: "$amtStr"',
          );
          rows.add(parsedRow);
          invalidRows.add(parsedRow);
          continue;
        }

        amount = parsedAmt.abs();
        transactionType = parsedAmt > 0
            ? TransactionType.income
            : TransactionType.expense;
      }

      // 3. Metadata Extraction
      final description = rowMap[mapping.descriptionColumn]?.trim();
      final rawCategory = rowMap[mapping.categoryColumn]?.trim();
      final category = TransactionCategories.normalizeCategory(
        rawCategory,
        transactionType,
      );
      final ref = rowMap[mapping.referenceColumn]?.trim();
      final merchant = rowMap[mapping.merchantColumn]?.trim();

      // Create valid transaction
      final transaction = Transaction(
        id: '', // Will be assigned by backend or UUID
        businessId: businessId,
        transactionDate: date,
        transactionType: transactionType,
        category: category,
        amount: amount,
        currency: currency,
        description: (description != null && description.isNotEmpty)
            ? description
            : null,
        merchantName: (merchant != null && merchant.isNotEmpty)
            ? merchant
            : null,
        paymentStatus: _parsePaymentStatus(
          rowMap[mapping.paymentStatusColumn],
          defaultStatus: PaymentStatus.paid,
        ),
        source: TransactionSource.csv,
        externalReference: (ref != null && ref.isNotEmpty) ? ref : null,
        rawText: rowList.join(','),
        createdAt: now,
        updatedAt: now,
      );

      // Check duplicate against existing transactions & within batch
      bool isDuplicate = false;
      if (existingTransactions != null && existingTransactions.isNotEmpty) {
        for (final existing in existingTransactions) {
          if (_isProbableDuplicate(transaction, existing)) {
            isDuplicate = true;
            break;
          }
        }
      }

      final parsedRow = ParsedCsvRow(
        rowIndex: i + 1,
        rawRow: rowMap,
        transaction: transaction,
        isDuplicate: isDuplicate,
      );

      rows.add(parsedRow);
      validRows.add(parsedRow);

      if (transactionType == TransactionType.income) {
        totalIncome += amount;
      } else if (transactionType == TransactionType.expense) {
        totalExpenses += amount;
      }
    }

    return CsvParseResult(
      headers: headers,
      rows: rows,
      validRows: validRows,
      invalidRows: invalidRows,
      mapping: mapping,
      totalIncome: totalIncome,
      totalExpenses: totalExpenses,
    );
  }

  static bool _isProbableDuplicate(Transaction a, Transaction b) {
    // 1. Same reference if reference exists
    if (a.externalReference != null &&
        b.externalReference != null &&
        a.externalReference!.isNotEmpty &&
        a.externalReference == b.externalReference) {
      return true;
    }

    // 2. Same date (day), amount, type, and description
    final sameDate =
        a.transactionDate.year == b.transactionDate.year &&
        a.transactionDate.month == b.transactionDate.month &&
        a.transactionDate.day == b.transactionDate.day;
    final sameAmount = (a.amount - b.amount).abs() < 0.001;
    final sameType = a.transactionType == b.transactionType;

    if (sameDate && sameAmount && sameType) {
      if (a.description != null && b.description != null) {
        return a.description!.trim().toLowerCase() ==
            b.description!.trim().toLowerCase();
      }
      return true;
    }

    return false;
  }

  static PaymentStatus _parsePaymentStatus(
    String? raw, {
    PaymentStatus defaultStatus = PaymentStatus.paid,
  }) {
    if (raw == null || raw.trim().isEmpty) return defaultStatus;
    final lower = raw.trim().toLowerCase();
    if (lower == 'pending' || lower == 'unpaid') {
      return PaymentStatus.pending;
    }
    if (lower == 'overdue' || lower == 'late') {
      return PaymentStatus.overdue;
    }
    if (lower == 'paid' || lower == 'completed' || lower == 'cleared') {
      return PaymentStatus.paid;
    }
    return defaultStatus;
  }
}
