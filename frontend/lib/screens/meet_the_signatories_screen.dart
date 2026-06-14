import 'package:flutter/material.dart';
import '../core/theme.dart';

class MeetTheSignatoriesScreen extends StatelessWidget {
  const MeetTheSignatoriesScreen({super.key});

  static const _team = [
    {
      'name': 'Khushi Katiyar',
      'role': 'Backend, Model Training',
      'photo': 'assets/images/khushi.jpg',
      'bio': 'Built the dual-screen UI, camera overlay, and chat system.',
      'color': Color(0xFF4B9EFF),
    },
    {
      'name': 'Vanshvi Jain',
      'role': 'Feature Integration',
      'photo': 'assets/images/vanshvi.jpg',
      'bio': 'Trained the ASL gesture classifier and built the inference pipeline.',
      'color': Color(0xFF3DD68C),
    },
    {
      'name': 'Deepanshi Mane',
      'role': 'Flutter Frontend',
      'photo': 'assets/images/deepanshi.jpg',
      'bio': 'Built the smart suggestions engine, translation, and speech APIs.',
      'color': Color(0xFFF5A623),
    },
    {
      'name': 'Achal Goyal',
      'role': 'Backend, Model Training',
      'photo': 'assets/images/achal.jpg',
      'bio': 'Wired everything together and made the demo actually work.',
      'color': Color(0xFFB06EFF),
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back button
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios,
                      color: AppTheme.textMuted, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ),

              // Title section
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Meet the\nSignatories',
                      style: TextStyle(
                        fontFamily: 'ArchivoBlack',
                        fontSize: 36,
                        fontWeight: FontWeight.w400,
                        color: AppTheme.textPrimary,
                        height: 1.1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'The team behind CosmicSigns.',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 14,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Team cards
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _team.length,
                  itemBuilder: (context, i) {
                    final member = _team[i];
                    final color = member['color'] as Color;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: color.withValues(alpha: 0.25),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Avatar
                            Stack(
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: color.withValues(alpha: 0.5),
                                      width: 2,
                                    ),
                                    color: AppTheme.bgSurface,
                                  ),
                                  child: ClipOval(
                                    child: Image.asset(
                                      member['photo'] as String,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Center(
                                        child: Text(
                                          (member['name'] as String)[0],
                                          style: TextStyle(
                                            fontFamily: 'ArchivoBlack',
                                            color: color,
                                            fontSize: 24,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: color,
                                      border: Border.all(
                                          color: AppTheme.bgCard, width: 2),
                                    ),
                                    child: const Icon(Icons.star,
                                        color: Colors.white, size: 9),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),

                            // Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    member['name'] as String,
                                    style: const TextStyle(
                                      fontFamily: 'ArchivoBlack',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w400,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      color: color.withValues(alpha: 0.1),
                                      border: Border.all(
                                          color: color.withValues(alpha: 0.3),
                                          width: 1),
                                    ),
                                    child: Text(
                                      member['role'] as String,
                                      style: TextStyle(
                                        fontFamily: 'Outfit',
                                        fontSize: 11,
                                        color: color,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    member['bio'] as String,
                                    style: const TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 12,
                                      color: AppTheme.textMuted,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}