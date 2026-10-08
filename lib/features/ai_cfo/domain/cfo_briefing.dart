import '../../../core/utilities/money_formatter.dart';
import '../../businesses/domain/business.dart';
import '../../financial_health/domain/financial_metric.dart';
import '../../forecasts/domain/forecast.dart';
import '../../alerts/domain/alert.dart';
import '../../alerts/domain/priority_ranking_engine.dart';

class CfoBriefing {
  const CfoBriefing({
    required this.todayStatus,
    required this.mostImportantChange,
    required this.biggestRisk,
    required this.bestOpportunity,
    required this.recommendedAction,
    required this.forecastOutlook,
    required this.prioritizedIssues,
    required this.generatedAt,
  });

  final String todayStatus;
  final String mostImportantChange;
  final String biggestRisk;
  final String bestOpportunity;
  final String recommendedAction;
  final String forecastOutlook;
  final List<PrioritizedFinancialIssue> prioritizedIssues;
  final DateTime generatedAt;

  static CfoBriefing generate({
    required Business business,
    required FinancialMetric? metric,
    required List<Alert> activeAlerts,
    List<Forecast>? forecasts,
  }) {
    final currency = business.currency;
    final symbol = MoneyFormatter.getCurrencySymbol(currency);
    final issues = PriorityRankingEngine.rankFinancialIssues(
      business: business,
      metric: metric,
      activeAlerts: activeAlerts,
      forecasts: forecasts,
    );

    if (metric == null || (metric.revenue == 0 && metric.expenses == 0)) {
      return CfoBriefing(
        todayStatus: '${business.name} has initialized its financial workspace. Waiting for baseline transaction data.',
        mostImportantChange: 'No transaction statement loaded yet.',
        biggestRisk: 'Absence of recorded transactions prevents cash visibility.',
        bestOpportunity: 'Import bank CSV or connect SMS ingestion to unlock automated AI diagnostics.',
        recommendedAction: 'Import your recent bank statement to generate a deterministic health score.',
        forecastOutlook: 'Forecasts will generate automatically once 2+ monthly transaction periods are loaded.',
        prioritizedIssues: [],
        generatedAt: DateTime.now(),
      );
    }

    final health = metric.healthScore?.toStringAsFixed(0) ?? '—';
    final profit = metric.profit;
    final margin = metric.profitMargin.toStringAsFixed(1);
    final cashFlow = metric.netCashFlow;
    final revGrowth = metric.revenueGrowth;
    final expGrowth = metric.expenseGrowth;

    // 1. Today Status
    String status;
    if (profit >= 0 && cashFlow >= 0) {
      status = '${business.name} is in solid financial standing (Score: $health/100). Both net profit ($symbol${profit.toStringAsFixed(2)}, $margin%) and operating cash flow are positive.';
    } else if (profit >= 0 && cashFlow < 0) {
      status = '${business.name} is profitable on paper ($symbol${profit.toStringAsFixed(2)}), but operating cash flow is tightening (-$symbol${(-cashFlow).toStringAsFixed(2)}).';
    } else {
      status = '${business.name} is currently operating at a net deficit of -$symbol${(-profit).toStringAsFixed(2)} with a Health Score of $health/100.';
    }

    // 2. Most Important Change
    String change;
    if (expGrowth != 0.0 || revGrowth != 0.0) {
      if (expGrowth > revGrowth && expGrowth > 10.0) {
        change = 'Expenses increased by ${expGrowth.toStringAsFixed(1)}%, outpacing revenue growth (${revGrowth.toStringAsFixed(1)}%) by ${(expGrowth - revGrowth).toStringAsFixed(1)} points.';
      } else if (revGrowth > 15.0) {
        change = 'Revenue expanded by ${revGrowth.toStringAsFixed(1)}% compared to the preceding period.';
      } else if (revGrowth < -10.0) {
        change = 'Revenue contracted by ${(-revGrowth).toStringAsFixed(1)}% vs the prior period.';
      } else {
        change = 'Operating margins shifted to $margin% on $symbol${metric.revenue.toStringAsFixed(2)} revenue.';
      }
    } else {
      change = 'Baseline financial metrics established for the current period.';
    }

    // 3. Biggest Risk
    final topRiskAlert = activeAlerts.where((a) => a.isRisk && !a.isRead).toList();
    String risk;
    if (topRiskAlert.isNotEmpty) {
      risk = topRiskAlert.first.title;
    } else if (cashFlow < 0) {
      risk = 'Negative cash burn of -$symbol${(-cashFlow).toStringAsFixed(2)} drawing down liquidity reserves.';
    } else if (metric.receivables > 0) {
      risk = '$symbol${metric.receivables.toStringAsFixed(2)} uncollected in customer accounts receivable.';
    } else {
      risk = 'No severe risks detected. Operating risk profile remains low.';
    }

    // 4. Best Opportunity
    final topOppAlert = activeAlerts.where((a) => a.isOpportunity && !a.isRead).toList();
    String opp;
    if (topOppAlert.isNotEmpty) {
      opp = topOppAlert.first.title;
    } else if (metric.receivables > 0) {
      opp = 'Accelerate invoice recovery to inject up to $symbol${metric.receivables.toStringAsFixed(2)} in direct cash.';
    } else {
      opp = 'Optimize operating vendor contracts to expand gross margins.';
    }

    // 5. Recommended Action
    String action;
    if (issues.isNotEmpty) {
      action = issues.first.recommendedAction;
    } else if (cashFlow < 0) {
      action = 'Run a 10% expense reduction simulation in the What-If tool to map a path to cash neutrality.';
    } else {
      action = 'Continue reviewing weekly transaction reconciliations to maintain score integrity.';
    }

    // 6. Forecast Outlook
    String forecastText;
    if (forecasts != null && forecasts.isNotEmpty) {
      final revForecasts = forecasts.where((f) => f.forecastType == ForecastType.revenue).toList();
      if (revForecasts.isNotEmpty) {
        final nextRev = revForecasts.first.predictedValue;
        forecastText = 'Projecting next month revenue of ~$symbol${nextRev.toStringAsFixed(0)} based on historical weighted trend.';
      } else {
        forecastText = 'Forecast model updated with current trajectory assumptions.';
      }
    } else {
      forecastText = 'Forecast projections require at least 2 historical monthly buckets.';
    }

    return CfoBriefing(
      todayStatus: status,
      mostImportantChange: change,
      biggestRisk: risk,
      bestOpportunity: opp,
      recommendedAction: action,
      forecastOutlook: forecastText,
      prioritizedIssues: issues,
      generatedAt: DateTime.now(),
    );
  }
}
