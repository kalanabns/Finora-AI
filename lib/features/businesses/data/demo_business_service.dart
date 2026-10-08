import '../../ai_cfo/domain/cfo_action_item.dart';
import '../../alerts/domain/alert.dart';
import '../../alerts/domain/priority_ranking_engine.dart';
import '../../businesses/domain/business.dart';
import '../../financial_health/domain/financial_engine.dart';
import '../../financial_health/domain/financial_goal.dart';
import '../../financial_health/domain/financial_metric.dart';
import '../../financial_health/domain/health_score_breakdown.dart';
import '../../forecasts/domain/forecast.dart';
import '../../transactions/domain/transaction.dart';

class DemoDataset {
  const DemoDataset({
    required this.business,
    required this.transactions,
    required this.currentMetric,
    required this.previousMetric,
    required this.breakdown,
    required this.buckets,
    required this.alerts,
    required this.forecasts,
    required this.goals,
    required this.actionPlan,
  });

  final Business business;
  final List<Transaction> transactions;
  final FinancialMetric currentMetric;
  final FinancialMetric previousMetric;
  final HealthScoreBreakdown breakdown;
  final List<MonthlyFinancialBucket> buckets;
  final List<Alert> alerts;
  final List<Forecast> forecasts;
  final List<FinancialGoal> goals;
  final List<CfoActionItem> actionPlan;
}

class DemoBusinessService {
  const DemoBusinessService._();

  static const String demoBusinessId = 'demo-pacific-coast-roasters';

  /// Generates the realistic, self-contained hackathon SMB demo dataset.
  static DemoDataset getDemoData() {
    final now = DateTime.now();

    final business = Business(
      id: demoBusinessId,
      ownerId: 'demo-user',
      name: 'Pacific Coast Roasters',
      industry: 'Food & Beverage',
      country: 'Sri Lanka',
      currency: 'LKR',
      fiscalYearStartMonth: 1,
      startingCash: 28500.0,
      createdAt: now.subtract(const Duration(days: 180)),
      updatedAt: now,
    );

    // 6-Month Monthly Buckets showing revenue growth accompanied by sharp expense surge
    final buckets = [
      MonthlyFinancialBucket(
        year: now.year,
        month: ((now.month - 6) % 12) + 1,
        label: 'Month -5',
        revenue: 52000.0,
        expenses: 39000.0,
        profit: 13000.0,
        netCashFlow: 13000.0,
      ),
      MonthlyFinancialBucket(
        year: now.year,
        month: ((now.month - 5) % 12) + 1,
        label: 'Month -4',
        revenue: 55000.0,
        expenses: 41000.0,
        profit: 14000.0,
        netCashFlow: 14000.0,
      ),
      MonthlyFinancialBucket(
        year: now.year,
        month: ((now.month - 4) % 12) + 1,
        label: 'Month -3',
        revenue: 59000.0,
        expenses: 43500.0,
        profit: 15500.0,
        netCashFlow: 15500.0,
      ),
      MonthlyFinancialBucket(
        year: now.year,
        month: ((now.month - 3) % 12) + 1,
        label: 'Month -2',
        revenue: 63000.0,
        expenses: 48000.0,
        profit: 15000.0,
        netCashFlow: 12000.0,
      ),
      MonthlyFinancialBucket(
        year: now.year,
        month: ((now.month - 2) % 12) + 1,
        label: 'Prior Month',
        revenue: 68000.0,
        expenses: 56000.0,
        profit: 12000.0,
        netCashFlow: 3500.0,
      ),
      MonthlyFinancialBucket(
        year: now.year,
        month: ((now.month - 1) % 12) + 1,
        label: 'Current Month',
        revenue: 72500.0,
        expenses: 64800.0,
        profit: 7700.0,
        netCashFlow: -4200.0,
      ),
    ];

    // Previous Period Metric
    final previousMetric = FinancialMetric(
      id: 'metric_demo_prev',
      businessId: demoBusinessId,
      periodStart: DateTime(now.year, now.month - 1, 1),
      periodEnd: DateTime(now.year, now.month, 0),
      revenue: 68000.0,
      expenses: 56000.0,
      profit: 12000.0,
      profitMargin: 17.6,
      cashInflow: 65000.0,
      cashOutflow: 56000.0,
      netCashFlow: 3500.0,
      receivables: 9500.0,
      payables: 4000.0,
      revenueGrowth: 7.9,
      expenseGrowth: 16.7,
      healthScore: 68.0,
      createdAt: now.subtract(const Duration(days: 30)),
      updatedAt: now.subtract(const Duration(days: 30)),
    );

    // Current Period Metric (Distress: Margin tightening, Negative Cash, High Receivables)
    final currentMetric = FinancialMetric(
      id: 'metric_demo_curr',
      businessId: demoBusinessId,
      periodStart: DateTime(now.year, now.month, 1),
      periodEnd: now,
      revenue: 72500.0,
      expenses: 64800.0,
      profit: 7700.0,
      profitMargin: 10.6,
      cashInflow: 60600.0,
      cashOutflow: 64800.0,
      netCashFlow: -4200.0,
      receivables: 18500.0,
      payables: 8200.0,
      revenueGrowth: 6.6,
      expenseGrowth: 15.7,
      healthScore: 57.0,
      createdAt: now,
      updatedAt: now,
    );

    // 5-Point Health Score Breakdown (Score: 57 / 100 — WATCH)
    const breakdown = HealthScoreBreakdown(
      totalScore: 57.0,
      band: HealthScoreBand.watch,
      bandLabel: 'Watch',
      summary: 'Profitability is positive (10.6% margin), but accelerating expense growth and \$18,500 in overdue receivables are creating a negative cash flow drag.',
      profitability: HealthScoreComponent(
        name: 'Profitability & Margin',
        score: 18.0,
        maxScore: 30.0,
        description: 'Evaluates net operating profit and profit margin.',
        insight: 'Net margin compressed to 10.6% (down from 17.6% last month).',
      ),
      cashFlow: HealthScoreComponent(
        name: 'Operating Cash Flow',
        score: 9.0,
        maxScore: 25.0,
        description: 'Measures cash generation vs operational outflows.',
        insight: 'Operating cash flow is negative (-\$4,200/mo) due to delayed customer invoice payments.',
      ),
      revenueTrend: HealthScoreComponent(
        name: 'Revenue Expansion',
        score: 12.0,
        maxScore: 15.0,
        description: 'Analyzes top-line growth consistency.',
        insight: 'Top-line sales expanded steadily (+6.6% month-over-month).',
      ),
      expenseControl: HealthScoreComponent(
        name: 'Expense Discipline',
        score: 7.0,
        maxScore: 15.0,
        description: 'Monitors expense growth relative to revenue.',
        insight: 'Operating expenses grew by 15.7%, outpacing revenue growth by 9.1 percentage points.',
      ),
      workingCapital: HealthScoreComponent(
        name: 'Working Capital & Liquidity',
        score: 11.0,
        maxScore: 15.0,
        description: 'Measures receivables and short-term liabilities.',
        insight: '\$18,500 in outstanding receivables is locking up 25.5% of monthly revenue.',
      ),
    );

    // Active Alerts matching the scenario
    final alerts = [
      Alert(
        id: 'alert_demo_1',
        businessId: demoBusinessId,
        alertType: AlertType.risk,
        severity: AlertSeverity.critical,
        title: 'Operating Cash Flow Deficit (-\$4,200)',
        description: 'Monthly cash outflows exceeded collections by \$4,200. Continued burn will deplete reserve cash within 4.2 months.',
        recommendation: 'Test an expense reduction scenario in the What-If Simulator and collect overdue client invoices.',
        metricName: 'Net Cash Flow',
        metricValue: 4200.0,
        thresholdValue: 0.0,
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      Alert(
        id: 'alert_demo_2',
        businessId: demoBusinessId,
        alertType: AlertType.risk,
        severity: AlertSeverity.high,
        title: 'Expense Growth Outpacing Revenue (+15.7% vs +6.6%)',
        description: 'Discretionary software subscriptions, supplier price increases, and marketing overhead grew by 15.7%.',
        recommendation: 'Audit top 3 supplier contracts and pause unused SaaS subscriptions.',
        metricName: 'Expense Growth',
        metricValue: 15.7,
        thresholdValue: 10.0,
        createdAt: now.subtract(const Duration(days: 4)),
      ),
      Alert(
        id: 'alert_demo_3',
        businessId: demoBusinessId,
        alertType: AlertType.opportunity,
        severity: AlertSeverity.low,
        title: 'Accelerate \$18,500 Overdue Receivables',
        description: '14 customer invoices totaling \$18,500 are past their 30-day terms.',
        recommendation: 'Send automated invoice reminder notices and offer 2% Net-10 early payment discounts.',
        metricName: 'Accounts Receivable',
        metricValue: 18500.0,
        createdAt: now.subtract(const Duration(days: 6)),
      ),
    ];

    // Forecasts for next 3 months
    final forecasts = [
      Forecast(
        id: 'f_demo_rev_1',
        businessId: demoBusinessId,
        forecastDate: DateTime(now.year, now.month + 1, 1),
        forecastType: ForecastType.revenue,
        predictedValue: 76000.0,
        lowerBound: 71000.0,
        upperBound: 81000.0,
        confidence: 0.85,
        modelVersion: 'LinearTrend_EWMA',
        createdAt: now,
      ),
      Forecast(
        id: 'f_demo_exp_1',
        businessId: demoBusinessId,
        forecastDate: DateTime(now.year, now.month + 1, 1),
        forecastType: ForecastType.expenses,
        predictedValue: 68500.0,
        lowerBound: 64000.0,
        upperBound: 73000.0,
        confidence: 0.82,
        modelVersion: 'LinearTrend_EWMA',
        createdAt: now,
      ),
      Forecast(
        id: 'f_demo_cash_1',
        businessId: demoBusinessId,
        forecastDate: DateTime(now.year, now.month + 1, 1),
        forecastType: ForecastType.cashFlow,
        predictedValue: -2500.0,
        lowerBound: -6000.0,
        upperBound: 1000.0,
        confidence: 0.78,
        modelVersion: 'CashRunwayModel',
        createdAt: now,
      ),
    ];

    // Realistic Recent Transactions
    final transactions = [
      Transaction(
        id: 'tx_demo_1',
        businessId: demoBusinessId,
        transactionDate: now.subtract(const Duration(hours: 4)),
        transactionType: TransactionType.income,
        category: 'Sales',
        amount: 3450.0,
        currency: 'LKR',
        description: 'Wholesale Coffee Beans Order #1042',
        merchantName: 'Blue Harbor Cafe',
        paymentStatus: PaymentStatus.paid,
        source: TransactionSource.csv,
        createdAt: now,
        updatedAt: now,
      ),
      Transaction(
        id: 'tx_demo_2',
        businessId: demoBusinessId,
        transactionDate: now.subtract(const Duration(days: 1)),
        transactionType: TransactionType.expense,
        category: 'Software',
        amount: 890.0,
        currency: 'LKR',
        description: 'Cloud Inventory & Roasting Platform',
        merchantName: 'RoastLog SaaS Inc',
        paymentStatus: PaymentStatus.paid,
        source: TransactionSource.sms,
        createdAt: now,
        updatedAt: now,
      ),
      Transaction(
        id: 'tx_demo_3',
        businessId: demoBusinessId,
        transactionDate: now.subtract(const Duration(days: 2)),
        transactionType: TransactionType.expense,
        category: 'Supplies',
        amount: 4200.0,
        currency: 'LKR',
        description: 'Green Coffee Import Batch #308',
        merchantName: 'Antioquia Bean Importers',
        paymentStatus: PaymentStatus.paid,
        source: TransactionSource.csv,
        createdAt: now,
        updatedAt: now,
      ),
      Transaction(
        id: 'tx_demo_4',
        businessId: demoBusinessId,
        transactionDate: now.subtract(const Duration(days: 3)),
        transactionType: TransactionType.income,
        category: 'Accounts Receivable',
        amount: 5200.0,
        currency: 'LKR',
        description: 'Invoice #892 - Pending Net 30',
        merchantName: 'Seaside Hospitality Group',
        paymentStatus: PaymentStatus.pending,
        source: TransactionSource.manual,
        createdAt: now,
        updatedAt: now,
      ),
      Transaction(
        id: 'tx_demo_5',
        businessId: demoBusinessId,
        transactionDate: now.subtract(const Duration(days: 5)),
        transactionType: TransactionType.expense,
        category: 'Marketing',
        amount: 1450.0,
        currency: 'LKR',
        description: 'Digital Ads & Local Promo Campaign',
        merchantName: 'Meta Ads Manager',
        paymentStatus: PaymentStatus.paid,
        source: TransactionSource.sms,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    // Realistic Financial Goals
    final goals = [
      FinancialGoal(
        id: 'goal_demo_1',
        businessId: demoBusinessId,
        title: 'Build Operating Cash Reserve (\$35,000)',
        goalType: GoalType.targetCashReserve,
        targetValue: 35000.0,
        currentValue: 28500.0,
        unit: '\$',
        targetDate: now.add(const Duration(days: 90)),
        status: GoalStatus.onTrack,
        createdAt: now.subtract(const Duration(days: 20)),
        updatedAt: now,
      ),
      FinancialGoal(
        id: 'goal_demo_2',
        businessId: demoBusinessId,
        title: 'Cap Monthly Operating Expenses (\$58,000)',
        goalType: GoalType.expenseLimit,
        targetValue: 58000.0,
        currentValue: 64800.0,
        unit: '\$',
        targetDate: now.add(const Duration(days: 60)),
        status: GoalStatus.behindTarget,
        createdAt: now.subtract(const Duration(days: 15)),
        updatedAt: now,
      ),
      FinancialGoal(
        id: 'goal_demo_3',
        businessId: demoBusinessId,
        title: 'Restore Net Profit Margin to 18%',
        goalType: GoalType.targetProfitMargin,
        targetValue: 18.0,
        currentValue: 10.6,
        unit: '%',
        targetDate: now.add(const Duration(days: 120)),
        status: GoalStatus.behindTarget,
        createdAt: now.subtract(const Duration(days: 10)),
        updatedAt: now,
      ),
    ];

    // Realistic CFO Action Plan Items
    final actionPlan = [
      CfoActionItem(
        id: 'action_demo_1',
        businessId: demoBusinessId,
        title: 'Collect Overdue Accounts Receivable (\$18,500)',
        reason: 'Delayed collections have driven operating cash flow into a -\$4,200 deficit.',
        priority: PriorityLevel.critical,
        urgency: 'Immediate (Next 7 Days)',
        relatedMetric: 'Accounts Receivable',
        recommendedNextStep: 'Issue 2% Net-10 payment terms and follow up with top 3 pending accounts.',
        actionType: ActionLinkType.collectReceivables,
        status: CfoActionStatus.todo,
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      CfoActionItem(
        id: 'action_demo_2',
        businessId: demoBusinessId,
        title: 'Renegotiate Coffee Bean Import Contract',
        reason: 'Green bean supplies rose 18% MoM, compressing gross margin from 42% to 34%.',
        priority: PriorityLevel.high,
        urgency: 'Within 14 Days',
        relatedMetric: 'Cost of Goods Sold',
        recommendedNextStep: 'Consolidate orders with Antioquia Bean Importers to secure 8% bulk discount.',
        actionType: ActionLinkType.runScenario,
        status: CfoActionStatus.inProgress,
        createdAt: now.subtract(const Duration(days: 3)),
      ),
      CfoActionItem(
        id: 'action_demo_3',
        businessId: demoBusinessId,
        title: 'Audit & Trim Unused SaaS Subscriptions',
        reason: 'Software expenses reached \$890/mo across overlapping operational tools.',
        priority: PriorityLevel.medium,
        urgency: 'Within 30 Days',
        relatedMetric: 'Software Expenses',
        recommendedNextStep: 'Cancel redundant analytics licenses and downgrade unused seat tiers.',
        actionType: ActionLinkType.reviewExpenses,
        status: CfoActionStatus.todo,
        createdAt: now.subtract(const Duration(days: 5)),
      ),
      CfoActionItem(
        id: 'action_demo_4',
        businessId: demoBusinessId,
        title: 'Establish 90-Day Cash Flow Runway Buffer',
        reason: 'Current cash reserve covers ~4.2 months of burn at existing negative net cash rates.',
        priority: PriorityLevel.medium,
        urgency: 'Within 60 Days',
        relatedMetric: 'Cash Runway',
        recommendedNextStep: 'Automate weekly liquidity review and simulate hiring freeze scenarios.',
        actionType: ActionLinkType.runScenario,
        status: CfoActionStatus.todo,
        createdAt: now.subtract(const Duration(days: 7)),
      ),
    ];

    return DemoDataset(
      business: business,
      transactions: transactions,
      currentMetric: currentMetric,
      previousMetric: previousMetric,
      breakdown: breakdown,
      buckets: buckets,
      alerts: alerts,
      forecasts: forecasts,
      goals: goals,
      actionPlan: actionPlan,
    );
  }
}
