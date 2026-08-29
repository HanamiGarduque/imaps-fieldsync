import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/insight_theme.dart';

class AboutInsightScreen extends StatelessWidget {
  const AboutInsightScreen({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      body: Stack(
        children: [
          // Background Glow
          Positioned(
            top: -60,
            right: -60,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: InsightTheme.blue1.withValues(alpha: 0.20),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // App Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white),
                            boxShadow: kCardShadow,
                          ),
                          child: const Center(
                            child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: InsightTheme.ink),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text('About', style: InsightTheme.poppins(18, w: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: InsightTheme.primaryGradient,
                            boxShadow: [
                              BoxShadow(
                                color: InsightTheme.blue1.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(Icons.location_on_rounded, color: Colors.white, size: 36),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text('iMAPS:FieldSync', style: InsightTheme.poppins(22, w: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('Version 1.0.0', style: InsightTheme.jetBrains(12, c: InsightTheme.ink2, ls: 0.5)),

                        const SizedBox(height: 32),

                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: InsightTheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: InsightTheme.line),
                            boxShadow: kCardShadow,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ABOUT THE SYSTEM',
                                style: InsightTheme.jetBrains(10, w: FontWeight.w700, ls: 0.8, c: InsightTheme.blue1),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'iMAPS:FieldSync is an intelligent geospatial analytics and zoning application designed specifically for the Municipal Planning and Development Office of Rosario, Batangas.\n\nThis application facilitates active monitoring and analytics reporting of land use and zoning compliance directly from the field unit.',
                                style: InsightTheme.inter(13.5, h: 1.6),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}