import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/constants.dart';
import 'screens/login_screen.dart';
import 'screens/output_screen/output_view.dart';
import 'services/app_state.dart';
import 'core/theme.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const AslRetailApp(),
    ),
  );
}

class AslRetailApp extends StatelessWidget {
  const AslRetailApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Maneora ASL Desk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.midnightAmberTheme,
      home: const AppInitializer(),
    );
  }
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({Key? key}) : super(key: key);

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (appState.isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.bgDeep,
        body: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.backgroundGradient,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Logo with amber glow ───────────────────────────
                Container(
                  width: 110,
                  height: 110,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x20F5A623),
                        blurRadius: 48,
                        spreadRadius: 4,
                      ),
                    ],
                    color: AppTheme.bgSurface,
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(
                          'M',
                          style: GoogleFonts.archivoBlack(
                            fontSize: 44,
                            color: AppTheme.amber,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // Amber spinner
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: AppTheme.amber,
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(height: 28),

                Text(
                  AppConstants.aslEngineHost != 'localhost'
                      ? 'Cashier mode — connecting to ${AppConstants.aslEngineHost}'
                      : 'Connecting to server...',
                  style: GoogleFonts.archivoBlack(
                    fontSize: 18,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'First load may take up to 50 seconds',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: AppTheme.textMuted,
                  ),
                ),

                if (appState.errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppTheme.borderDefault, width: 1),
                    ),
                    child: Text(
                      appState.errorMessage,
                      style: GoogleFonts.outfit(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // ── Device B (tablet/cashier): skip login → go straight to cashier output ──
    if (AppConstants.aslEngineHost != 'localhost') {
      return const OutputView(isAdmin: true);
    }

    // ── Device A: show normal login/role selection ──
    return const LoginScreen();
  }
}
