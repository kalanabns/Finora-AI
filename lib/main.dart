import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/auth_gate.dart';
import 'app/authenticated_app_shell.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'features/authentication/application/auth_controller.dart';
import 'features/businesses/application/business_controller.dart';
import 'features/businesses/data/demo_business_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? initError;
  try {
    SupabaseConfig.validate();
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  } catch (e) {
    initError = e.toString().replaceAll('Bad state: ', '').replaceAll('Exception: ', '');
  }

  runApp(FinoraApp(initError: initError));
}

class FinoraApp extends StatefulWidget {
  const FinoraApp({super.key, this.initError});

  final String? initError;

  @override
  State<FinoraApp> createState() => _FinoraAppState();
}

class _FinoraAppState extends State<FinoraApp> {
  late final AuthController _authController;
  late final BusinessController _businessController;

  @override
  void initState() {
    super.initState();
    if (widget.initError == null) {
      _authController = AuthController();
      _businessController = BusinessController();
      final demo = DemoBusinessService.getDemoData();
      _businessController.loadDemoMode(demo.business);
    }
  }

  @override
  void dispose() {
    if (widget.initError == null) {
      _authController.dispose();
      _businessController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finora AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      home: widget.initError != null
          ? _buildInitErrorScreen(widget.initError!)
          : AuthenticatedAppShell(
              authController: _authController,
              businessController: _businessController,
            ),
    );
  }

  Widget _buildInitErrorScreen(String error) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryNavy,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.settings_suggest_rounded,
                    size: 40,
                    color: AppTheme.tealAccent,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Configuration Setup Required',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Launch Command:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      SizedBox(height: 6),
                      SelectableText(
                        'flutter run --dart-define-from-file=config/supabase.local.json',
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: AppTheme.navyPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
