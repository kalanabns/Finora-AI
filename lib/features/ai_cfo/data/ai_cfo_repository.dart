import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utilities/money_formatter.dart';
import '../../../core/utilities/uuid_generator.dart';
import '../../alerts/domain/alert.dart';
import '../../businesses/domain/business.dart';
import '../../financial_health/domain/financial_metric.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/ai_conversation.dart';

class AICFORepository {
  AICFORepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;
  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  /// Retrieves past conversation turns for a given session.
  Future<List<AIConversation>> getConversationHistory({
    required String businessId,
    required String sessionId,
  }) async {
    if (!UuidUtils.isValidUuid(sessionId)) {
      return [];
    }

    final response = await _client
        .from('ai_conversations')
        .select()
        .eq('business_id', businessId)
        .eq('session_id', sessionId)
        .order('created_at', ascending: true);

    final list = response as List<dynamic>;
    return list
        .map((json) => AIConversation.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Sends a message to the AI CFO via Supabase Edge Function or live Gemini API,
  /// returning the grounded advisory reply.
  Future<String> sendMessage({
    required String businessId,
    required String sessionId,
    required String message,
    Alert? alertContext,
    FinancialMetric? currentMetrics,
    Business? business,
    List<Alert>? activeAlerts,
    List<Transaction>? recentTransactions,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('User not authenticated.');
    }

    final safeSessionId = UuidUtils.isValidUuid(sessionId)
        ? sessionId
        : UuidUtils.generate();

    // 1. Check if Gemini API key is supplied via --dart-define-from-file
    const geminiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (geminiKey.isNotEmpty) {
      try {
        final geminiReply = await _callGeminiApi(
          apiKey: geminiKey,
          message: message,
          business: business,
          currentMetrics: currentMetrics,
          alertContext: alertContext,
          activeAlerts: activeAlerts,
          recentTransactions: recentTransactions,
        );

        if (geminiReply != null && geminiReply.trim().isNotEmpty) {
          await _persistTurn(
            businessId: businessId,
            userId: user.id,
            sessionId: safeSessionId,
            userMessage: message,
            assistantMessage: geminiReply,
          );
          return geminiReply;
        }
      } catch (_) {
        // Fall through to Edge Function or grounded generator
      }
    }

    try {
      // 2. Try calling the Supabase Edge Function 'ai-cfo'
      final functionResponse = await _client.functions.invoke(
        'ai-cfo',
        body: {
          'business_id': businessId,
          'session_id': safeSessionId,
          'message': message,
          if (alertContext != null)
            'alert_context': {
              'title': alertContext.title,
              'description': alertContext.description,
              'recommendation': alertContext.recommendation,
              'severity': alertContext.severity.name,
            },
        },
      );

      if (functionResponse.status == 200 && functionResponse.data != null) {
        final data = functionResponse.data as Map<String, dynamic>;
        final reply = data['reply'] as String?;
        if (reply != null && reply.isNotEmpty) {
          return reply;
        }
      }
    } catch (_) {
      // Fall through to secure client-side grounded generator + DB persistence
    }

    // 3. Client-safe Grounded AI Advisor fallback
    final groundedReply = generateAdvisoryResponse(
      message: message,
      alert: alertContext,
      metric: currentMetrics,
      business: business,
    );

    // Persist conversation turns directly into Supabase ai_conversations table
    await _persistTurn(
      businessId: businessId,
      userId: user.id,
      sessionId: safeSessionId,
      userMessage: message,
      assistantMessage: groundedReply,
    );

    return groundedReply;
  }

  Future<void> _persistTurn({
    required String businessId,
    required String userId,
    required String sessionId,
    required String userMessage,
    required String assistantMessage,
  }) async {
    final validSessionId = UuidUtils.isValidUuid(sessionId)
        ? sessionId
        : UuidUtils.generate();

    await _client.from('ai_conversations').insert([
      {
        'business_id': businessId,
        'user_id': userId,
        'session_id': validSessionId,
        'role': 'user',
        'message': userMessage,
      },
      {
        'business_id': businessId,
        'user_id': userId,
        'session_id': validSessionId,
        'role': 'assistant',
        'message': assistantMessage,
      },
    ]);
  }

  Future<String?> _callGeminiApi({
    required String apiKey,
    required String message,
    Business? business,
    FinancialMetric? currentMetrics,
    Alert? alertContext,
    List<Alert>? activeAlerts,
    List<Transaction>? recentTransactions,
  }) async {
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-lite-latest:generateContent?key=$apiKey',
    );

    final client = HttpClient();
    try {
      final request = await client.postUrl(url);
      request.headers.set('Content-Type', 'application/json');

      final contextMap = {
        'business': {
          'name': business?.name ?? 'Business',
          'industry': business?.industry ?? 'General',
          'currency': business?.currency ?? 'USD',
        },
        'metrics': currentMetrics != null
            ? {
                'revenue': currentMetrics.revenue,
                'expenses': currentMetrics.expenses,
                'profit': currentMetrics.profit,
                'profit_margin': '${currentMetrics.profitMargin.toStringAsFixed(1)}%',
                'net_cash_flow': currentMetrics.netCashFlow,
                'receivables': currentMetrics.receivables,
                'payables': currentMetrics.payables,
                'health_score': currentMetrics.healthScore,
              }
            : 'No metrics yet',
        'focused_signal': alertContext != null
            ? {
                'title': alertContext.title,
                'description': alertContext.description,
                'recommendation': alertContext.recommendation,
              }
            : null,
      };

      const systemPrompt =
          'You are Finora AI CFO, an executive financial advisor for small businesses. '
          'Provide clear, factual, structured recommendations (What Happened, Why It Matters, What I Recommend) '
          'based on the real financial metrics provided without inventing fake numbers.';

      final payload = jsonEncode({
        'system_instruction': {
          'parts': [
            {'text': systemPrompt}
          ]
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {
                'text':
                    'Financial Context:\n${jsonEncode(contextMap)}\n\nQuestion:\n$message'
              }
            ]
          }
        ]
      });

      request.write(payload);
      final response = await request.close();
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final parsed = jsonDecode(responseBody) as Map<String, dynamic>;
        final candidates = parsed['candidates'] as List<dynamic>?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates[0]['content']['parts'] as List<dynamic>?;
          if (parts != null && parts.isNotEmpty) {
            return parts[0]['text'] as String?;
          }
        }
      }
      return null;
    } finally {
      client.close();
    }
  }

  /// Clears a conversation session.
  Future<void> clearSession({
    required String businessId,
    required String sessionId,
  }) async {
    if (!UuidUtils.isValidUuid(sessionId)) return;
    await _client
        .from('ai_conversations')
        .delete()
        .eq('business_id', businessId)
        .eq('session_id', sessionId);
  }

  static String generateAdvisoryResponse({
    required String message,
    Alert? alert,
    FinancialMetric? metric,
    Business? business,
  }) {
    final bName = business?.name ?? 'your business';
    final currency = business?.currency ?? 'LKR';
    final symbol = MoneyFormatter.getCurrencySymbol(currency);
    final lowerMsg = message.toLowerCase();

    // 0. Insufficient Data Check
    if (metric == null || (metric.revenue == 0 && metric.expenses == 0)) {
      return '''### What Happened
$bName workspace has insufficient financial history to compute accurate performance trends or forward forecasts.

### Why It Matters
Reliable financial decisions require actual transaction data to establish your baseline revenue, cost structure, and cash burn rate.

### What I Recommend
1. Import your recent bank or credit card CSV statements via the **Transactions** tab.
2. Ensure at least 30 to 60 days of inflows and outflows are recorded.
3. Review your starting cash balance in Business Settings.

**Priority**: HIGH''';
    }

    // 1. Alert Context Explanation
    if (alert != null) {
      return '''### What Happened
${alert.description}

### Why It Matters
This signal directly impacts operating liquidity and profit stability for $bName. When ${alert.title.toLowerCase()} persists, working capital becomes constrained.

### Top Risks
- Cash runway compression if collections lag behind disbursements.
- Unplanned debt reliance or emergency liquidity borrowing.

### Recommended Actions
1. ${alert.recommendation ?? "Review your highest operating costs and renegotiate key supplier agreements."}
2. Prioritize collecting overdue receivables before committing to new capital outlays.
3. Review your weekly cash outflow schedule against expected customer payments.

### Expected Impact & Urgency
- **Expected Impact**: Stabilizes monthly operating cash flow by reducing immediate burn.
- **Priority / Urgency**: ${alert.severityLabel.toUpperCase()}''';
    }

    // 2. Hiring & Headcount Affordability
    if (lowerMsg.contains('hire') ||
        lowerMsg.contains('staff') ||
        lowerMsg.contains('employee') ||
        lowerMsg.contains('headcount') ||
        lowerMsg.contains('payroll')) {
      final monthlyProfit = metric.profit;
      final monthlyCash = metric.netCashFlow;
      final canAfford = monthlyProfit > 3000 && monthlyCash > 2000;

      return '''### What Happened
$bName currently generates **$symbol${metric.profit.toStringAsFixed(2)}** in monthly profit and **$symbol${metric.netCashFlow.toStringAsFixed(2)}** in net cash flow, with a composite Health Score of **${metric.healthScore?.toStringAsFixed(0) ?? "0"}/100**.

### Why It Matters
Adding new fixed payroll increases your monthly break-even threshold regardless of revenue volatility. A safe hiring decision requires at least 3-6 months of payroll reserve plus consistent positive operating cash flow.

### Top Risks
- New staff fixed expense could flip monthly cash flow into a deficit if sales fluctuate.
- Slower onboarding velocity delaying revenue contribution.

### Recommended Actions
1. ${canAfford ? "Your current cash flow supports a cautious hire. Set a strict total compensation ceiling (salary + taxes + benefits)." : "Delay full-time hiring until operating profit and cash collections consistently exceed \$3,000/mo."}
2. Run a scenario in the **What-If Simulator** (+Hire Staff) to model the exact margin impact.
3. Consider contract or milestone-based talent first to protect baseline cash flow.

### Expected Impact & Urgency
- **Expected Impact**: Preserves liquidity while verifying revenue payback period.
- **Priority**: ${canAfford ? "MEDIUM" : "HIGH"}''';
    }

    // 3. Forward Cash & Forecast Questions
    if (lowerMsg.contains('next month') ||
        lowerMsg.contains('forecast') ||
        lowerMsg.contains('runway') ||
        lowerMsg.contains('future cash') ||
        lowerMsg.contains('how much cash')) {
      final cashFlow = metric.netCashFlow;
      final isPositive = cashFlow >= 0;

      return '''### What Happened
Historical net operating cash flow is running at **${isPositive ? "+" : ""}$symbol${cashFlow.toStringAsFixed(2)}** per month. Total receivables waiting to be collected stand at **$symbol${metric.receivables.toStringAsFixed(2)}**.

### Why It Matters
Forward cash stability depends on maintaining positive operating cash flow and accelerating the velocity of invoice collections.

### Top Risks
- Delayed customer payments postponing expected cash receipts into subsequent periods.
- Lump-sum annual software or insurance renewals creating short-term liquidity dips.

### Recommended Actions
1. Review your 3-Month Projection in the **Forecasts** tab to examine best/worst-case cash trajectory.
2. Follow up on the **$symbol${metric.receivables.toStringAsFixed(2)}** in pending invoices to secure immediate cash inflows.
3. Establish a rolling 13-week cash flow calendar to monitor weekly disbursement timing.

### Expected Impact & Urgency
- **Expected Impact**: Protects operating buffer and prevents unexpected working capital shortfalls.
- **Priority**: ${isPositive ? "MEDIUM" : "HIGH"}''';
    }

    // 4. Price Increase / What-If Scenario Questions
    if (lowerMsg.contains('increase price') ||
        lowerMsg.contains('pricing') ||
        lowerMsg.contains('what if') ||
        lowerMsg.contains('price increase') ||
        lowerMsg.contains('5%') ||
        lowerMsg.contains('10%')) {
      final rev = metric.revenue;
      final fivePercentGain = rev * 0.05;

      return '''### What Happened
$bName recorded **$symbol${rev.toStringAsFixed(2)}** in baseline revenue with a profit margin of **${metric.profitMargin.toStringAsFixed(1)}%**. A 5% price adjustment would generate approximately **+$symbol${fivePercentGain.toStringAsFixed(2)}** in direct gross profit.

### Why It Matters
Because fixed operating costs remain constant, pricing power flows directly to bottom-line net profit and cash flow expansion.

### Top Risks
- Potential client churn if price increases are not paired with clear value communication.
- Competitor undercutting on standard service tiers.

### Recommended Actions
1. Model this scenario in the **What-If Simulator** to project exact margin expansion.
2. Roll out price revisions selectively to new client proposals before adjusting existing contracts.
3. Grandfather top long-term accounts on 12-month retainers to lock in predictable baseline revenue.

### Expected Impact & Urgency
- **Expected Impact**: Expands net profit margin by ~${(fivePercentGain / (rev > 0 ? rev : 1) * 100).toStringAsFixed(1)}% with zero additional overhead.
- **Priority**: MEDIUM''';
    }

    // 5. Risks & Vulnerabilities
    if (lowerMsg.contains('risk') ||
        lowerMsg.contains('danger') ||
        lowerMsg.contains('concern') ||
        lowerMsg.contains('threat')) {
      final isLoss = metric.profit < 0;
      final isNegativeCash = metric.netCashFlow < 0;

      return '''### What Happened
$bName is operating with a Financial Health Score of **${metric.healthScore?.toStringAsFixed(0) ?? "0"}/100**. ${isLoss ? "Current net loss is -$symbol${(-metric.profit).toStringAsFixed(2)}." : "Net profit is $symbol${metric.profit.toStringAsFixed(2)}."} ${isNegativeCash ? "Net cash burn is -$symbol${(-metric.netCashFlow).toStringAsFixed(2)}." : "Operating cash flow is +$symbol${metric.netCashFlow.toStringAsFixed(2)}."}

### Why It Matters
${isNegativeCash ? "Cash disbursements are outpacing collections, which will erode your liquid cash buffer if unchecked." : "Operating margins require active defense against compounding overhead and delayed receivables."}

### Top Risks
- Cash runway contraction if revenue contracts while fixed costs remain elevated.
- Overdue customer invoices turning into bad debt write-offs.

### Recommended Actions
1. Accelerate collection of the **$symbol${metric.receivables.toStringAsFixed(2)}** in outstanding customer receivables.
2. Conduct an immediate audit of recurring vendor subscriptions and discretionary retainers.
3. Delay capital-intensive disbursements until monthly cash flow is solidly positive.

### Expected Impact & Urgency
- **Expected Impact**: Halts cash drainage and rebuilds working capital reserves.
- **Priority**: ${isLoss || isNegativeCash ? "CRITICAL" : "HIGH"}''';
    }

    // 6. Expense Optimization & Spending
    if (lowerMsg.contains('reduce') ||
        lowerMsg.contains('expense') ||
        lowerMsg.contains('spend') ||
        lowerMsg.contains('cost') ||
        lowerMsg.contains('overhead')) {
      return '''### What Happened
Total operating expenses for this period are **$symbol${metric.expenses.toStringAsFixed(2)}**, with an expense growth rate of **${metric.expenseGrowth.toStringAsFixed(1)}%** vs prior period.

### Why It Matters
Pruning discretionary overhead immediately widens your operating margin without demanding costly sales cycles.

### Top Risks
- Creeping subscription overhead compounding unnoticed month-over-month.
- Vendor price escalations going unreviewed.

### Recommended Actions
1. Audit your top 3 largest expense categories in the **Transactions** tab to renegotiate vendor rates.
2. Cancel inactive software licenses, duplicate tools, and unused recurring memberships.
3. Require pre-approval for discretionary purchases above \$250.

### Expected Impact & Urgency
- **Expected Impact**: Trims monthly operating overhead by 5-15%, directly boosting cash reserves.
- **Priority**: HIGH''';
    }

    // 7. Revenue Opportunities & Growth
    if (lowerMsg.contains('opportunity') ||
        lowerMsg.contains('grow') ||
        lowerMsg.contains('increase') ||
        lowerMsg.contains('margin') ||
        lowerMsg.contains('profit')) {
      return '''### What Happened
$bName generated **$symbol${metric.revenue.toStringAsFixed(2)}** in revenue with a profit margin of **${metric.profitMargin.toStringAsFixed(1)}%**.

### Why It Matters
Focusing on high-margin offerings while accelerating invoice payment terms compounds your cash conversion velocity.

### Top Risks
- Over-allocating time and resources to low-margin or slow-paying customer accounts.

### Recommended Actions
1. Re-engage past high-value clients with tailored expansion or retainer proposals.
2. Offer 2% early-payment discounts for invoices settled within 7 days.
3. Double down on your most profitable customer segment based on transaction history.

### Expected Impact & Urgency
- **Expected Impact**: Accelerates cash inflow timing and elevates composite health score.
- **Priority**: MEDIUM''';
    }

    // 8. General Performance & Default Executive Brief
    return '''### What Happened
$bName recorded **$symbol${metric.revenue.toStringAsFixed(2)}** in revenue and **$symbol${metric.expenses.toStringAsFixed(2)}** in expenses, delivering a net profit of **$symbol${metric.profit.toStringAsFixed(2)}** (Margin: **${metric.profitMargin.toStringAsFixed(1)}%**). Your composite Financial Health Score is **${metric.healthScore?.toStringAsFixed(0) ?? "0"}/100**.

### Why It Matters
${metric.profit >= 0 ? "Core operations are profitable, providing stability to support reinvestment." : "Operating expenses exceed current revenue, creating pressure on working capital."}

### Top Risks
- ${metric.receivables > 0 ? "Uncollected receivables (\$${metric.receivables.toStringAsFixed(2)}) delaying working capital availability." : "Managing monthly fixed overhead against seasonal revenue fluctuations."}

### Recommended Actions
1. ${metric.receivables > 0 ? "Follow up on outstanding customer payments to convert invoiced revenue to liquid cash." : "Maintain strict oversight on recurring monthly operating overhead."}
2. Maintain a 3-month operating cash cushion for unexpected contingencies.
3. Review active alerts in the **Action Center** to address identified bottlenecks.

### Expected Impact & Urgency
- **Expected Impact**: Protects core profitability and strengthens overall business financial resilience.
- **Priority**: ${metric.profit < 0 ? "HIGH" : "MEDIUM"}''';
  }
}
