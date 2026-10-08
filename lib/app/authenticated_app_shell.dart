import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../features/ai_cfo/application/ai_cfo_controller.dart';
import '../features/ai_cfo/application/cfo_action_plan_controller.dart';
import '../features/ai_cfo/presentation/ai_cfo_screen.dart';
import '../features/ai_cfo/presentation/cfo_action_plan_screen.dart';
import '../features/alerts/application/alerts_controller.dart';
import '../features/alerts/domain/alert.dart';
import '../features/alerts/domain/priority_ranking_engine.dart';
import '../features/alerts/presentation/alerts_screen.dart';
import '../features/authentication/application/auth_controller.dart';
import '../features/businesses/application/business_controller.dart';
import '../features/businesses/data/demo_business_service.dart';
import '../features/businesses/domain/business.dart';
import '../features/financial_health/application/financial_goals_controller.dart';
import '../features/financial_health/application/financial_health_controller.dart';
import '../features/financial_health/presentation/analytics_screen.dart';
import '../features/financial_health/presentation/dashboard_screen.dart';
import '../features/financial_health/presentation/financial_goals_screen.dart';
import '../features/forecasts/application/forecast_controller.dart';
import '../features/forecasts/presentation/forecast_screen.dart';
import '../features/simulations/domain/simulation_engine.dart';
import '../features/simulations/presentation/simulations_screen.dart';
import '../features/transactions/application/sms_ingestion_controller.dart';
import '../features/transactions/application/transaction_controller.dart';
import '../features/transactions/presentation/sms_review_screen.dart';
import '../features/transactions/presentation/transactions_screen.dart';
import '../shared/widgets/onboarding_guide_dialog.dart';

class AuthenticatedAppShell extends StatefulWidget {
  const AuthenticatedAppShell({
    super.key,
    required this.authController,
    required this.businessController,
  });

  final AuthController authController;
  final BusinessController businessController;

  @override
  State<AuthenticatedAppShell> createState() => _AuthenticatedAppShellState();
}

class _AuthenticatedAppShellState extends State<AuthenticatedAppShell> {
  int _selectedIndex = 0;
  late final TransactionController _transactionController;
  late final FinancialHealthController _healthController;
  late final AlertsController _alertsController;
  late final AICFOController _aiCfoController;
  late final ForecastController _forecastController;
  late final SmsIngestionController _smsController;
  late final FinancialGoalsController _goalsController;
  late final CfoActionPlanController _actionPlanController;

  Alert? _alertToExplainInAi;

  @override
  void initState() {
    super.initState();
    _healthController = FinancialHealthController();
    _alertsController = AlertsController();
    _aiCfoController = AICFOController();
    _forecastController = ForecastController();
    _goalsController = FinancialGoalsController();
    _actionPlanController = CfoActionPlanController();

    _transactionController = TransactionController(
      onTransactionsChanged: () {
        _syncAllEngines(silent: true);
      },
    );

    _smsController = SmsIngestionController(
      onTransactionsChanged: () {
        final business = widget.businessController.currentBusiness;
        if (business != null) {
          _transactionController.loadTransactions(businessId: business.id).then((_) {
            _syncAllEngines(silent: true);
          });
        }
      },
    );

    var business = widget.businessController.currentBusiness;
    if (business == null) {
      final demo = DemoBusinessService.getDemoData();
      widget.businessController.loadDemoMode(demo.business);
      business = demo.business;
    }
    if (widget.businessController.isDemoMode) {
      _loadDemoState();
    } else {
        _transactionController.loadTransactions(businessId: business.id).then((
          _,
        ) {
          _syncAllEngines(silent: false);
        });
        _goalsController.loadGoals(business.id);
        _actionPlanController.loadActionItems(business.id);
        _aiCfoController.loadHistory(businessId: business.id);
      }

    final uri = Uri.base;
    if (uri.queryParameters['tab'] != null) {
      _selectedIndex = int.tryParse(uri.queryParameters['tab']!) ?? 0;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final screen = uri.queryParameters['screen'];
      if (screen == 'simulations') {
        _openSimulationsScreen(
          context,
          initialPercentageDelta: 5.0,
          initialScenarioName: '5% Price Increase',
        );
      } else if (screen == 'forecasts') {
        _openForecastsScreen(context);
      } else if (screen == 'analytics') {
        _openAnalyticsScreen(context);
      }
    });
  }

  void _loadDemoState() {
    final demo = DemoBusinessService.getDemoData();
    _transactionController.loadInMemoryTransactions(demo.transactions);
    _alertsController.loadInMemoryAlerts(demo.alerts);
    _goalsController.loadInMemoryGoals(demo.goals);
    _actionPlanController.loadInMemoryActionItems(demo.actionPlan);
    _healthController.recalculate(
      businessId: demo.business.id,
      allTransactions: demo.transactions,
      silent: true,
    );
    _forecastController.generateAndSyncForecasts(
      businessId: demo.business.id,
      buckets: demo.buckets,
      startingCash: demo.business.startingCash,
      currency: demo.business.currency,
      silent: true,
    );
    _actionPlanController.generateRoadmap(
      businessId: demo.business.id,
      metric: demo.currentMetric,
      alerts: demo.alerts,
      goals: demo.goals,
    );
  }

  void _syncAllEngines({bool silent = false}) {
    final business = widget.businessController.currentBusiness;
    if (business == null) return;

    _healthController.recalculate(
      businessId: business.id,
      allTransactions: _transactionController.transactions,
      silent: silent,
    );

    final metric = _healthController.currentMetric;
    if (metric != null) {
      _alertsController.evaluateAndSync(
        businessId: business.id,
        currentMetrics: metric,
        currentTransactions: _transactionController.transactions,
        startingCash: business.startingCash,
      );

      _aiCfoController.generateDashboardSummary(
        businessId: business.id,
        currentMetrics: metric,
        business: business,
        activeAlerts: _alertsController.allAlerts,
      );

      _forecastController.generateAndSyncForecasts(
        businessId: business.id,
        buckets: _healthController.monthlyBuckets,
        startingCash: business.startingCash,
        currency: business.currency,
        silent: silent,
      );

      _goalsController.syncGoalsWithMetrics(
        metric,
        startingCash: business.startingCash,
      );

      _actionPlanController.generateRoadmap(
        businessId: business.id,
        metric: metric,
        alerts: _alertsController.allAlerts,
        goals: _goalsController.goals,
      );
    }
  }

  @override
  void dispose() {
    _transactionController.dispose();
    _healthController.dispose();
    _alertsController.dispose();
    _aiCfoController.dispose();
    _forecastController.dispose();
    _smsController.dispose();
    _goalsController.dispose();
    _actionPlanController.dispose();
    super.dispose();
  }

  void _handleSignOut() {
    widget.businessController.reset();
    widget.authController.signOut();
  }

  void _openAnalyticsScreen(BuildContext context) {
    final business = widget.businessController.currentBusiness;
    if (business == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnalyticsScreen(
          business: business,
          currentTransactions: _transactionController.transactions,
          monthlyBuckets: _healthController.monthlyBuckets,
          currentMetric: _healthController.currentMetric,
          previousMetric: _healthController.previousMetric,
          onNavigateToSimulations: () => _openSimulationsScreen(context),
          onNavigateToForecasts: () => _openForecastsScreen(context),
          onNavigateToTransactions: () {
            Navigator.pop(context);
            setState(() => _selectedIndex = 1);
          },
        ),
      ),
    );
  }

  void _openGoalsScreen(BuildContext context) {
    final business = widget.businessController.currentBusiness;
    if (business == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FinancialGoalsScreen(
          controller: _goalsController,
          business: business,
          currentMetric: _healthController.currentMetric,
          onAskAiAboutGoal: (goal) {
            Navigator.pop(context);
            _selectedIndex = 2;
            setState(() {});
            _aiCfoController.sendMessage(
              message:
                  'What strategic recommendations do you have to help us achieve our goal: "${goal.title}"? Current value is ${goal.unit}${goal.currentValue} vs target ${goal.unit}${goal.targetValue}.',
              businessId: business.id,
              currentMetrics: _healthController.currentMetric,
              business: business,
              activeAlerts: _alertsController.allAlerts,
              recentTransactions: _transactionController.transactions,
            );
          },
          onNavigateToSimulations: () => _openSimulationsScreen(
            context,
            initialScenarioName: 'Goal Target Scenario',
          ),
        ),
      ),
    );
  }

  void _openActionPlanScreen(BuildContext context) {
    final business = widget.businessController.currentBusiness;
    if (business == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CfoActionPlanScreen(
          controller: _actionPlanController,
          business: business,
          onExecuteAction: (item) {
            switch (item.actionType) {
              case ActionLinkType.runScenario:
                _openSimulationsScreen(context, initialScenarioName: item.title);
                break;
              case ActionLinkType.reviewExpenses:
              case ActionLinkType.collectReceivables:
              case ActionLinkType.viewTransactions:
                Navigator.pop(context);
                setState(() => _selectedIndex = 1);
                break;
              case ActionLinkType.reviewForecast:
                _openForecastsScreen(context);
                break;
              case ActionLinkType.askAiCfo:
                Navigator.pop(context);
                _selectedIndex = 2;
                setState(() {});
                _aiCfoController.sendMessage(
                  message: 'Give me an execution plan for: ${item.title}',
                  businessId: business.id,
                  currentMetrics: _healthController.currentMetric,
                  business: business,
                  activeAlerts: _alertsController.allAlerts,
                  recentTransactions: _transactionController.transactions,
                );
                break;
            }
          },
        ),
      ),
    );
  }

  void _openForecastsScreen(BuildContext context) {
    final business = widget.businessController.currentBusiness;
    if (business == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForecastScreen(
          controller: _forecastController,
          business: business,
          historicalBuckets: _healthController.monthlyBuckets,
          onAskAiAboutForecast: (query) {
            _selectedIndex = 2;
            setState(() {});
            _aiCfoController.sendMessage(
              message: query,
              businessId: business.id,
              currentMetrics: _healthController.currentMetric,
              business: business,
              activeAlerts: _alertsController.allAlerts,
              recentTransactions: _transactionController.transactions,
            );
          },
        ),
      ),
    );
  }

  void _openSimulationsScreen(
    BuildContext context, {
    ScenarioType? initialScenarioType,
    double? initialPercentageDelta,
    String? initialTargetCategory,
    double? initialFixedAmountDelta,
    String? initialScenarioName,
  }) {
    final business = widget.businessController.currentBusiness;
    if (business == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SimulationsScreen(
          business: business,
          transactionsController: _transactionController,
          currentMetric: _healthController.currentMetric,
          initialScenarioType: initialScenarioType,
          initialPercentageDelta: initialPercentageDelta,
          initialTargetCategory: initialTargetCategory,
          initialFixedAmountDelta: initialFixedAmountDelta,
          initialScenarioName: initialScenarioName,
        ),
      ),
    );
  }

  void _openSmsReviewScreen(BuildContext context) {
    final business = widget.businessController.currentBusiness;
    if (business == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SmsReviewScreen(
          controller: _smsController,
          business: business,
          existingTransactions: _transactionController.transactions,
        ),
      ),
    );
  }

  void _navigateToAiCfoWithAlert(Alert alert) {
    setState(() {
      _alertToExplainInAi = alert;
      _selectedIndex = 2; // AI CFO tab index
    });

    _aiCfoController.sendMessage(
      message:
          'Explain this signal: "${alert.title}" and provide practical next steps.',
      businessId: widget.businessController.currentBusiness!.id,
      alertContext: alert,
      currentMetrics: _healthController.currentMetric,
      business: widget.businessController.currentBusiness,
      activeAlerts: _alertsController.allAlerts,
      recentTransactions: _transactionController.transactions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final business = widget.businessController.currentBusiness;

    if (business == null) {
      return const Scaffold(body: Center(child: Text('No business selected.')));
    }

    return ListenableBuilder(
      listenable: _alertsController,
      builder: (context, _) {
        final unreadAlerts = _alertsController.unreadCount;

        final pages = [
          DashboardScreen(
            healthController: _healthController,
            transactionController: _transactionController,
            alertsController: _alertsController,
            aiCfoController: _aiCfoController,
            forecastController: _forecastController,
            business: business,
            onNavigateToTransactions: () {
              setState(() => _selectedIndex = 1);
            },
            onNavigateToAlerts: () {
              setState(() => _selectedIndex = 3);
            },
            onNavigateToAiCfo: () {
              setState(() => _selectedIndex = 2);
            },
            onNavigateToForecasts: () => _openForecastsScreen(context),
            onNavigateToSimulations: () => _openSimulationsScreen(context),
            onExplainAlert: _navigateToAiCfoWithAlert,
          ),
          TransactionsScreen(
            controller: _transactionController,
            businessId: business.id,
            currency: business.currency,
            business: business,
            smsController: _smsController,
          ),
          AICFOScreen(
            controller: _aiCfoController,
            business: business,
            currentMetrics: _healthController.currentMetric,
            activeAlerts: _alertsController.allAlerts,
            recentTransactions: _transactionController.transactions,
            initialAlertToExplain: _alertToExplainInAi,
          ),
          AlertsScreen(
            controller: _alertsController,
            businessId: business.id,
            business: business,
            currentMetrics: _healthController.currentMetric,
            onAskAiAboutAlert: _navigateToAiCfoWithAlert,
          ),
          _buildSettingsTab(context),
        ];

        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: _buildFuturisticHeader(context, business),
          body: Stack(
            children: [
              // Screen content with bottom inset padding for floating nav bar
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 74),
                  child: IndexedStack(index: _selectedIndex, children: pages),
                ),
              ),
              // Floating Glassmorphic Navigation Island
              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).padding.bottom + 10,
                child: _buildFloatingNavigationBar(unreadAlerts),
              ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildFuturisticHeader(BuildContext context, Business business) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(128),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1D55D8),
                Color(0xFF2563EB),
                Color(0xFF3B82F6),
                Color(0xFF4F46E5),
              ],
              stops: [0.0, 0.35, 0.70, 1.0],
            ),
            border: const Border(
              bottom: BorderSide(color: Color(0x3338BDF8), width: 1.0),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1D4ED8).withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Profile & Action Row
                  Row(
                    children: [
                      // Glowing Glass Avatar
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1.2,
                          ),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Business Title + Subtitle
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showBusinessHubSheet(context, business),
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      business.name,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: -0.2,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: Colors.white.withValues(alpha: 0.9),
                                    size: 20,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.businessController.isDemoMode
                                    ? '${business.currency} • Demo Active'
                                    : '${business.currency} • Transactions Sync Active',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.white.withValues(alpha: 0.82),
                                  fontWeight: FontWeight.w400,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Action / Exit Button
                      Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: widget.businessController.isDemoMode
                              ? widget.businessController.exitDemoMode
                              : _handleSignOut,
                          borderRadius: BorderRadius.circular(16),
                          child: Ink(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25),
                                width: 1.2,
                              ),
                            ),
                            child: Icon(
                              widget.businessController.isDemoMode
                                  ? Icons.exit_to_app_rounded
                                  : Icons.logout_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                // Fine Translucent Divider Line
                Container(
                  height: 1,
                  margin: const EdgeInsets.only(top: 12, bottom: 10),
                  color: Colors.white.withValues(alpha: 0.16),
                ),

                // Action Pills Row: Growth | Flow | Goals | Filters
                Row(
                  children: [
                    _buildActionPill(
                      icon: Icons.trending_up_rounded,
                      iconColor: const Color(0xFF34D399),
                      label: 'Growth',
                      onTap: () => _openAnalyticsScreen(context),
                    ),
                    const SizedBox(width: 7),
                    _buildActionPill(
                      icon: Icons.swap_vert_rounded,
                      iconColor: const Color(0xFF38BDF8),
                      label: 'Flow',
                      onTap: () => _openForecastsScreen(context),
                    ),
                    const SizedBox(width: 7),
                    _buildActionPill(
                      icon: Icons.flag_rounded,
                      iconColor: const Color(0xFFFBBF24),
                      label: 'Goals',
                      onTap: () => _openGoalsScreen(context),
                    ),
                    const SizedBox(width: 7),
                    _buildActionPill(
                      icon: Icons.tune_rounded,
                      iconColor: Colors.white,
                      label: 'Filters',
                      onTap: () => _openSimulationsScreen(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _buildActionPill({
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBusinessHubSheet(BuildContext context, Business business) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            business.name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            '${business.currency} • ${business.industry ?? "General"}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 6),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.cyberIndigo.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.checklist_rtl_rounded, color: AppTheme.cyberIndigo, size: 20),
                  ),
                  title: const Text('CFO Action Plan', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: const Text('30 & 90 day strategic roadmap', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openActionPlanScreen(context);
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.tune_rounded, color: AppTheme.primaryColor, size: 20),
                  ),
                  title: const Text('What-If Scenario Simulator', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: const Text('Stress-test revenue and expenses', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openSimulationsScreen(context);
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.insights_rounded, color: AppTheme.accentColor, size: 20),
                  ),
                  title: const Text('Advanced Business Intelligence', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: const Text('Deep dive into margins, OPEX, and cash flows', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openAnalyticsScreen(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloatingNavigationBar(int unreadAlerts) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF102A54), Color(0xFF16376D)],
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0x3538BDF8), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF102A54).withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavItem(0, Icons.dashboard_outlined, Icons.dashboard_rounded, 'Dashboard'),
          _buildNavItem(1, Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Ledger'),
          _buildNavItem(2, Icons.psychology_outlined, Icons.psychology_rounded, 'AI CFO'),
          _buildNavItem(3, Icons.notifications_none_rounded, Icons.notifications_rounded, 'Signals', badgeCount: unreadAlerts),
          _buildNavItem(4, Icons.settings_outlined, Icons.settings_rounded, 'Workspace'),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData icon,
    IconData selectedIcon,
    String label, {
    int badgeCount = 0,
  }) {
    final isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 12 : 8,
          vertical: 6,
        ),
        decoration: isSelected
            ? BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryLight.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isSelected ? selectedIcon : icon,
                  color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                  size: 20,
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: -4,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.errorColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTab(BuildContext context) {
    final user = widget.authController.currentUser;
    final business = widget.businessController.currentBusiness;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
      children: [
        const Text(
          'Account & Workspace',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.8)),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    color: AppTheme.primaryColor,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'User Email',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                subtitle: Text(
                  user?.email ?? 'N/A',
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.store_outlined,
                    color: AppTheme.accentColor,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Business Name',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                subtitle: Text(
                  business?.name ?? 'N/A',
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.warningColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.monetization_on_outlined,
                    color: AppTheme.warningColor,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Base Currency',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                subtitle: Text(
                  business?.currency ?? 'USD',
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.cyberIndigo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.calendar_month_outlined,
                    color: AppTheme.cyberIndigo,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Fiscal Year Start Month',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                subtitle: Text(
                  'Month ${business?.fiscalYearStartMonth ?? 1}',
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        // Strategic Intelligence & Tools Section
        const Text(
          'Strategic Intelligence & Tools',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.8)),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.insights_rounded,
                    color: AppTheme.accentColor,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Advanced BI & Analytics Matrix',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: const Text(
                  '6-Tab deep dive: Category trends, period comparisons & margin drivers',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.textSecondary),
                onTap: () => _openAnalyticsScreen(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.cyberIndigo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.checklist_rtl_rounded,
                    color: AppTheme.cyberIndigo,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'AI CFO Strategic Action Plan',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: const Text(
                  'Prioritized 30/90-day execution roadmap and status tracking',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.textSecondary),
                onTap: () => _openActionPlanScreen(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.flag_rounded,
                    color: AppTheme.primaryLight,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Financial Targets & Goals',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: const Text(
                  'Live goal progress bars, status badges & AI advisory hooks',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.textSecondary),
                onTap: () => _openGoalsScreen(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.auto_graph_rounded,
                    color: AppTheme.accentColor,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Predictive Trends & Forecasts',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: const Text(
                  '3-Month horizons with linear trend & confidence intervals',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.textSecondary),
                onTap: () => _openForecastsScreen(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: AppTheme.primaryColor,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'What-If Scenario Simulator',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: const Text(
                  'Simulate revenue shifts, expense cuts, pricing, and headcount',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.textSecondary),
                onTap: () => _openSimulationsScreen(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        // Automations & Ingestion Section
        const Text(
          'Automations & Ingestion',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.8)),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.sms_outlined,
                    color: AppTheme.primaryLight,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Android SMS Ingestion',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: const Text(
                  'Detect incoming bank & wallet SMS transactions',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                trailing: Switch(
                  value: _smsController.isIngestionEnabled,
                  activeThumbColor: AppTheme.primaryLight,
                  onChanged: (val) {
                    setState(() {
                      _smsController.toggleIngestion(val);
                    });
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.infoColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.fact_check_outlined,
                    color: AppTheme.infoColor,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Review SMS Candidates',
                  style: TextStyle(fontSize: 14, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${_smsController.pendingCandidates.length} pending approval',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: AppTheme.textSecondary,
                ),
                onTap: () => _openSmsReviewScreen(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        // Product Guide & Presentation Tools
        const Text(
          'Product Guide & Presentation',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.8)),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.menu_book_outlined,
                    color: AppTheme.primaryLight,
                    size: 20,
                  ),
                ),
                title: const Text(
                  '4-Pillar Architecture Guide',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: const Text(
                  'Review deterministic engine, What-If simulator, and AI CFO concepts',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.textSecondary),
                onTap: () => OnboardingGuideDialog.show(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.warningColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.science_outlined,
                    color: AppTheme.warningColor,
                    size: 20,
                  ),
                ),
                title: Text(
                  widget.businessController.isDemoMode ? 'Exit Demo Mode' : 'Load Hackathon Demo Dataset',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: Text(
                  widget.businessController.isDemoMode
                      ? 'Currently running isolated sample SMB scenario'
                      : 'Test Pacific Coast Roasters scenario (revenue growth with expense surge)',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.textSecondary),
                onTap: () {
                  if (widget.businessController.isDemoMode) {
                    widget.businessController.exitDemoMode();
                  } else {
                    final demo = DemoBusinessService.getDemoData();
                    widget.businessController.loadDemoMode(demo.business);
                    _loadDemoState();
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: widget.businessController.isDemoMode ? widget.businessController.exitDemoMode : _handleSignOut,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.errorColor,
            side: BorderSide(color: AppTheme.errorColor.withValues(alpha: 0.6)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          icon: Icon(widget.businessController.isDemoMode ? Icons.exit_to_app_rounded : Icons.logout_rounded, size: 18),
          label: Text(widget.businessController.isDemoMode ? 'Exit Demo Mode' : 'Log Out of Finora'),
        ),
        const SizedBox(height: 30),
      ],
    );
  }
}
