import 'package:flutter/material.dart';
import '../features/authentication/application/auth_controller.dart';
import '../features/authentication/presentation/login_screen.dart';
import '../features/businesses/application/business_controller.dart';
import '../features/businesses/presentation/business_onboarding_screen.dart';
import '../shared/widgets/finora_error_view.dart';
import '../shared/widgets/finora_loading_indicator.dart';
import 'authenticated_app_shell.dart';

import '../features/businesses/data/demo_business_service.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.authController,
    required this.businessController,
  });

  final AuthController authController;
  final BusinessController businessController;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    widget.authController.addListener(_onAuthChanged);
    _onAuthChanged();

    final uri = Uri.base;
    if (uri.queryParameters['demo'] == 'true' || uri.queryParameters['demo'] == '1') {
      final demo = DemoBusinessService.getDemoData();
      widget.businessController.loadDemoMode(demo.business);
    }
  }

  @override
  void dispose() {
    widget.authController.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (widget.businessController.isDemoMode) return;

    if (widget.authController.isAuthenticated) {
      if (widget.businessController.state == BusinessState.initial) {
        widget.businessController.loadUserBusiness();
      }
    } else {
      if (widget.businessController.state != BusinessState.initial) {
        widget.businessController.reset();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.authController, widget.businessController]),
      builder: (context, _) {
        if (widget.businessController.isDemoMode) {
          return AuthenticatedAppShell(
            authController: widget.authController,
            businessController: widget.businessController,
          );
        }

        final authStatus = widget.authController.status;

        if (authStatus == AuthStatus.initial ||
            widget.authController.isLoading) {
          return const FinoraLoadingIndicator(
            message: 'Initializing Finora AI...',
          );
        }

        if (authStatus == AuthStatus.unauthenticated) {
          return LoginScreen(
            authController: widget.authController,
            businessController: widget.businessController,
          );
        }

        // User is authenticated, evaluate business state
        final businessState = widget.businessController.state;

            switch (businessState) {
              case BusinessState.initial:
              case BusinessState.loading:
                return const FinoraLoadingIndicator(
                  message: 'Loading business workspace...',
                );

              case BusinessState.noBusiness:
                return BusinessOnboardingScreen(
                  businessController: widget.businessController,
                );

              case BusinessState.hasBusiness:
                return AuthenticatedAppShell(
                  authController: widget.authController,
                  businessController: widget.businessController,
                );

              case BusinessState.error:
                return Scaffold(
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: FinoraErrorView(
                        message:
                            widget.businessController.errorMessage ??
                            'Failed to load business details.',
                        onRetry: widget.businessController.loadUserBusiness,
                      ),
                    ),
                  ),
                );
            }
      },
    );
  }
}
