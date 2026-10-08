import 'package:flutter_test/flutter_test.dart';
import 'package:alibaba/features/businesses/application/business_controller.dart';
import 'package:alibaba/features/businesses/data/demo_business_service.dart';
import 'package:alibaba/features/financial_health/domain/health_score_breakdown.dart';

void main() {
  group('Stage 14 — Hackathon Demo Mode & SMB Scenario Integrity', () {
    test('demo dataset contains realistic distress scenario numbers for Pacific Coast Roasters', () {
      final dataset = DemoBusinessService.getDemoData();

      expect(dataset.business.name, equals('Pacific Coast Roasters'));
      expect(dataset.business.currency, equals('LKR'));
      expect(dataset.buckets.length, equals(6));

      // Check scenario numbers:
      // Revenue is growing ($68,000 -> $72,500)
      expect(dataset.currentMetric.revenue, equals(72500.0));
      expect(dataset.previousMetric.revenue, equals(68000.0));

      // Expenses growing faster ($56,000 -> $64,800)
      expect(dataset.currentMetric.expenses, equals(64800.0));
      expect(dataset.previousMetric.expenses, equals(56000.0));

      // Net cash flow negative (-$4,200)
      expect(dataset.currentMetric.netCashFlow, equals(-4200.0));

      // Receivables high ($18,500)
      expect(dataset.currentMetric.receivables, equals(18500.0));

      // Health score band is Watch (57 / 100)
      expect(dataset.breakdown.totalScore, equals(57.0));
      expect(dataset.breakdown.band, equals(HealthScoreBand.watch));
      expect(dataset.alerts, isNotEmpty);
      expect(dataset.forecasts, isNotEmpty);
    });

    test('BusinessController safely toggles demo mode without modifying persistent auth', () {
      final controller = BusinessController();
      expect(controller.isDemoMode, isFalse);

      final demo = DemoBusinessService.getDemoData();
      controller.loadDemoMode(demo.business);

      expect(controller.isDemoMode, isTrue);
      expect(controller.currentBusiness?.name, equals('Pacific Coast Roasters'));
      expect(controller.state, equals(BusinessState.hasBusiness));

      controller.exitDemoMode();
      expect(controller.isDemoMode, isFalse);
      expect(controller.currentBusiness, isNull);
    });
  });
}
