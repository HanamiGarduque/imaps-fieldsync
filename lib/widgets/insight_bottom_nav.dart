import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// ==================================================================
/// SHARED BOTTOM NAV — used by Home, Tasks, Updates, Profile.
/// Inactive items show icon only; the active item expands into a
/// filled pill with its label, animated. Replaces the old per-screen
/// duplicated _BottomNavItem (icon + label always stacked underneath).
/// ==================================================================

class InsightNavItem {
  final IconData icon;
  final String label;
  const InsightNavItem({required this.icon, required this.label});
}

class InsightBottomNav extends StatelessWidget {
  final int currentIndex;
  final List<InsightNavItem> items;
  final ValueChanged<int> onTap;

  const InsightBottomNav({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  static const _blue1 = Color(0xFF3D6BFF);
  static const _blue2 = Color(0xFF0B2FBF);
  static const _ink3 = Color.fromARGB(220, 227, 197, 216);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 225, 230, 232).withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                boxShadow: const [
                  BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2)),
                  BoxShadow(color: Color(0x15000000), blurRadius: 24, offset: Offset(0, 12)),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (int i = 0; i < items.length; i++)
                    _NavPillItem(
                      item: items[i],
                      isActive: i == currentIndex,
                      onTap: () {
                        if (i != currentIndex) HapticFeedback.selectionClick();
                        onTap(i);
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavPillItem extends StatelessWidget {
  final InsightNavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _NavPillItem({required this.item, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: isActive ? 16 : 12, vertical: 11),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(colors: [InsightBottomNav._blue1, InsightBottomNav._blue2], begin: Alignment.topLeft, end: Alignment.bottomRight)
              : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isActive
              ? [BoxShadow(color: InsightBottomNav._blue1.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, color: isActive ? Colors.white : const Color.fromARGB(255, 136, 139, 145), size: 21),
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: isActive
                  ? Padding(
                      padding: const EdgeInsets.only(left: 7),
                      child: Text(
                        item.label,
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    )
                  : const SizedBox(width: 0, height: 0),
            ),
          ],
        ),
      ),
    );
  }
}