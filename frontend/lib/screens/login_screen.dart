import 'package:flutter/material.dart';
import 'input_screen/input_view.dart';
import 'output_screen/output_view.dart';
import 'input_screen/widgets/glass_container.dart';
import 'meet_the_signatories_screen.dart';
import '../core/theme.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: SizedBox(
              width: 800,
              child: _buildCard(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.borderDefault, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 60,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // Subtle amber glow at top-centre
            Positioned(
              top: -80,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 500,
                  height: 340,
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topCenter,
                      radius: 0.9,
                      colors: [
                        Color(0x18F5A623),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(64, 52, 64, 52),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Logo ─────────────────────────────────────────
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MeetTheSignatoriesScreen(),
                      ),
                    ),
                    child: _buildLogo(),
                  ),
                  const SizedBox(height: 44),

                  // ── Divider with label ────────────────────────────
                  Row(
                    children: [
                      Expanded(
                          child: Divider(
                              color: AppTheme.borderDefault, thickness: 1)),
                      const SizedBox(width: 16),
                      const Text(
                        'SELECT YOUR ROLE',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMuted,
                          letterSpacing: 2.5,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                          child: Divider(
                              color: AppTheme.borderDefault, thickness: 1)),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // ── Role Buttons ──────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _buildRoleButton(
                          title: 'Staff Terminal',
                          subtitle: 'SIGN & MANAGE',
                          icon: Icons.admin_panel_settings_outlined,
                          isFeatured: true,
                          onTap: () => _showAdminPortalChoices(context),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _buildRoleButton(
                          title: 'Guest Tablet',
                          subtitle: 'SIGN & ORDER',
                          icon: Icons.tablet_mac_outlined,
                          isFeatured: false,
                          onTap: () => Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const InputView(isAdmin: false),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ── Status row ────────────────────────────────────
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.green,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x663DD68C),
                              blurRadius: 8,
                            )
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Server online · ASL Engine ready',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        // Logo — no border, just glow shadow
        Container(
          width: 160,
          height: 160,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x20F5A623),
                blurRadius: 60,
                spreadRadius: 4,
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Center(
                child: Text(
                  'M',
                  style: TextStyle(
                    fontFamily: 'ArchivoBlack',
                    fontSize: 64,
                    color: AppTheme.amber,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isFeatured,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isFeatured
                ? const Color(0x50F5A623)
                : AppTheme.borderDefault,
            width: 1,
          ),
          boxShadow: isFeatured
              ? const [
                  BoxShadow(
                    color: Color(0x12F5A623),
                    blurRadius: 32,
                    offset: Offset(0, 8),
                  )
                ]
              : null,
        ),
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0x14F5A623),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x35F5A623), width: 1),
              ),
              child: Icon(icon, size: 28, color: AppTheme.amber),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'ArchivoBlack',
                fontSize: 17,
                fontWeight: FontWeight.w400,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                fontFamily: 'Outfit',
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAdminPortalChoices(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppTheme.borderDefault, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Staff Portal',
                style: TextStyle(
                  fontFamily: 'ArchivoBlack',
                  fontSize: 20,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose your role for this session.',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 13,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 24),
              _buildDialogOption(
                context,
                icon: Icons.sign_language,
                title: 'I will Sign',
                subtitle: 'INPUT MODE',
                onTap: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const InputView(isAdmin: true),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _buildDialogOption(
                context,
                icon: Icons.chat_bubble_outline,
                title: 'I will Read',
                subtitle: 'OUTPUT MODE',
                onTap: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OutputView(isAdmin: true),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDialogOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.borderDefault, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0x14F5A623),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x35F5A623), width: 1),
              ),
              child: Icon(icon, color: AppTheme.amber, size: 20),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'ArchivoBlack',
                    fontWeight: FontWeight.w400,
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios,
                size: 13, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}