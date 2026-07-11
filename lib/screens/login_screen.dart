import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'tasks_screen.dart';

/// ==================================================================
/// DESIGN TOKENS
/// Rosario iMAPS FieldSync — visual identity is built around the idea
/// of a field survey instrument: contour lines, a graticule, coordinate
/// read-outs, corner-bracket "viewfinder" framing, mono data type.
/// Base gradient matches FieldSync's original deep indigo/navy theme.
/// ==================================================================
class AppColors {
  static const bgTop = Color(0xFF2E2B8C); // bright indigo core
  static const bgMid = Color(0xFF201E5E);
  static const bgDeep = Color(0xFF15142F); // deep navy edge
  static const bgSurface = Color(0xFF1C1B4C);
  static const bgSurfaceAlt = Color(0xFF211F58);
  static const bgInset = Color(0xFF171638);
  static const border = Color(0xFF32306E);
  static const borderBright = Color(0xFF423F8A);
  static const textPrimary = Color(0xFFEEEEFA);
  static const textSecondary = Color(0xFFA8ABCB);
  static const textTertiary = Color(0xFF6E7199);
  static const amber = Color(0xFFD8A643); // brass / survey instrument
  static const amberDim = Color(0xFFB07F2A);
  static const teal = Color(0xFF3FCDB0); // live / sync / GPS lock
  static const steel = Color(0xFF7FA8E0); // security / trust
  static const crimson = Color(0xFFEB6354); // alerts / errors
  static const onAccent = Color(0xFF15142F); // icon/text color atop accent fills
}

TextStyle _display(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) =>
    GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: w, color: c ?? AppColors.textPrimary, height: h, letterSpacing: ls);

TextStyle _body(double size, {FontWeight w = FontWeight.w400, Color? c, double? h}) =>
    GoogleFonts.ibmPlexSans(fontSize: size, fontWeight: w, color: c ?? AppColors.textSecondary, height: h);

TextStyle _mono(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) =>
    GoogleFonts.ibmPlexMono(fontSize: size, fontWeight: w, color: c ?? AppColors.textTertiary, letterSpacing: ls ?? 0.6);

/// ------------------------------------------------------------------
/// WELCOME / GET STARTED SCREEN
/// ------------------------------------------------------------------
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLoading = false;
  late AnimationController _floatingController;
  late AnimationController _driftController; // slow contour-line drift

  final List<Map<String, dynamic>> _onboardingData = [
    {
      "tag": "MAP-01",
      "eyebrow": "FIELD SURVEY",
      "title": "Map Your\nField",
      "subtitle": "The official field inspection tool for Rosario iMAPS. Access precise geospatial data on the go.",
      "icon": Icons.terrain_rounded,
      "accent": AppColors.amber,
      "coord": "13.8544° N, 121.2093° E",
    },
    {
      "tag": "SYN-02",
      "eyebrow": "REAL-TIME DATA",
      "title": "Seamless\nSync",
      "subtitle": "Synchronize your field reports directly to the municipal network in real-time, instantly.",
      "icon": Icons.sync_alt_rounded,
      "accent": AppColors.teal,
      "coord": "UPLINK · MPDO-NET",
    },
    {
      "tag": "SEC-03",
      "eyebrow": "ACCESS CONTROL",
      "title": "Secure &\nReady",
      "subtitle": "Empowering inspectors with accurate, secure, and up-to-date information anywhere in the field.",
      "icon": Icons.verified_user_rounded,
      "accent": AppColors.steel,
      "coord": "AES-256 · VERIFIED",
    },
  ];

  @override
  void initState() {
    super.initState();
    _floatingController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    _driftController = AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _floatingController.dispose();
    _driftController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _onboardingData.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 550), curve: Curves.easeOutCubic);
    } else {
      _handleGetStarted();
    }
  }

  void _skip() {
    _pageController.animateToPage(
      _onboardingData.length - 1,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _handleGetStarted() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: const LoginScreen(),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _onboardingData[_currentPage];
    final Color accent = data['accent'] as Color;
    final bool isLast = _currentPage == _onboardingData.length - 1;

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(
        children: [
          // --- FieldSync signature indigo/navy wash ---
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.62),
                radius: 1.35,
                colors: [AppColors.bgTop, AppColors.bgMid, AppColors.bgDeep],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
            child: SizedBox.expand(),
          ),

          // --- topographic contour lines + graticule (signature texture) ---
          AnimatedBuilder(
            animation: _driftController,
            builder: (context, _) => CustomPaint(
              size: Size.infinite,
              painter: _TopoPainter(progress: _driftController.value, accent: accent),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _DeviceStatusBar(accent: accent),

                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (index) => setState(() => _currentPage = index),
                    itemCount: _onboardingData.length,
                    itemBuilder: (context, index) {
                      return _buildVisualElement(data: _onboardingData[index], index: index);
                    },
                  ),
                ),

                // --- bottom instrument panel ---
                ClipRRect(
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(28, 30, 28, 34),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface.withValues(alpha:0.68),
                        border: Border(top: BorderSide(color: accent.withValues(alpha:0.4), width: 1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 350),
                            switchInCurve: Curves.easeOut,
                            child: Column(
                              key: ValueKey<int>(_currentPage),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(data['tag'], style: _mono(11.5, c: accent, w: FontWeight.w700, ls: 1.4)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Container(height: 1, color: AppColors.border),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(data['eyebrow'], style: _mono(10.5, c: AppColors.textTertiary, ls: 1.6)),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  data['title'],
                                  style: _display(30, w: FontWeight.w700, h: 1.05, ls: -0.4),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  data['subtitle'],
                                  style: _body(14, h: 1.55, c: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text('0${_currentPage + 1}', style: _mono(12, c: accent, w: FontWeight.w700)),
                                        Text(' / 0${_onboardingData.length}', style: _mono(12, c: AppColors.textTertiary)),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: List.generate(
                                        _onboardingData.length,
                                        (index) => _buildTick(index == _currentPage, accent),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    GestureDetector(
                                      onTap: isLast ? null : _skip,
                                      child: AnimatedOpacity(
                                        opacity: isLast ? 0.0 : 1.0,
                                        duration: const Duration(milliseconds: 250),
                                        child: Text('SKIP', style: _mono(11.5, c: AppColors.textSecondary, ls: 1.8)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _CircularIconButton(
                                accent: accent,
                                icon: isLast ? Icons.check_rounded : Icons.chevron_right_rounded,
                                loading: _isLoading && isLast,
                                onTap: _isLoading ? null : _nextPage,
                              ),
                            ],
                          ),
                        ],
                      ),
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

  Widget _buildVisualElement({required Map<String, dynamic> data, required int index}) {
    final Color accent = data['accent'] as Color;
    return Center(
      child: AnimatedBuilder(
        animation: _floatingController,
        builder: (context, child) {
          final floatOffset = sin(_floatingController.value * 2 * pi + (index * pi / 2)) * 10;
          return Transform.translate(
            offset: Offset(0, floatOffset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CornerBracketFrame(
                  accent: accent,
                  size: 176,
                  child: Icon(data['icon'], size: 54, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface.withValues(alpha:0.6),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PulseDot(color: accent),
                      const SizedBox(width: 8),
                      Text(data['coord'], style: _mono(11, c: AppColors.textSecondary, ls: 1.0)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTick(bool isActive, Color accent) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(right: 5),
      height: 3,
      width: isActive ? 20 : 10,
      decoration: BoxDecoration(
        color: isActive ? accent : AppColors.borderBright,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// SHARED CHROME: device status bar (signal / GPS lock / battery)
/// Gives the app the texture of a real field-issued unit rather than
/// a generic consumer app.
/// ------------------------------------------------------------------
class _DeviceStatusBar extends StatelessWidget {
  final Color accent;
  const _DeviceStatusBar({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.bgSurface.withValues(alpha:0.8),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(Icons.satellite_alt_rounded, color: accent, size: 16),
          ),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('iMAPS FieldSync', style: _display(14, w: FontWeight.w600, c: AppColors.textPrimary)),
              Text('ROSARIO · MPDO FIELD UNIT', style: _mono(9, c: AppColors.textTertiary, ls: 1.2)),
            ],
          ),
          const Spacer(),
          _SignalBars(color: accent),
          const SizedBox(width: 10),
          Row(
            children: [
              _PulseDot(color: AppColors.teal, size: 6),
              const SizedBox(width: 5),
              Text('GPS', style: _mono(9.5, c: AppColors.teal, ls: 1.0)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  final Color color;
  final int active;
  const _SignalBars({required this.color, this.active = 3});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 14,
      child: CustomPaint(painter: _SignalBarsPainter(color: color, active: active)),
    );
  }
}

class _SignalBarsPainter extends CustomPainter {
  final Color color;
  final int active;
  _SignalBarsPainter({required this.color, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 4;
    final barWidth = size.width / (barCount * 1.6);
    for (int i = 0; i < barCount; i++) {
      final barHeight = size.height * ((i + 1) / barCount);
      final paint = Paint()..color = i < active ? color : AppColors.borderBright;
      final rect = Rect.fromLTWH(
        i * barWidth * 1.6,
        size.height - barHeight,
        barWidth,
        barHeight,
      );
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(1)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignalBarsPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.active != active;
}

/// Small breathing dot used for "live" indicators.
class _PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  const _PulseDot({required this.color, this.size = 7});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = 0.4 + (_c.value * 0.6);
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha:t),
            boxShadow: [BoxShadow(color: widget.color.withValues(alpha:t * 0.5), blurRadius: 6, spreadRadius: 1)],
          ),
        );
      },
    );
  }
}

/// Corner-bracket "viewfinder" frame — the signature motif reused across
/// the onboarding icon and the login lock mark.
class _CornerBracketFrame extends StatelessWidget {
  final Widget child;
  final Color accent;
  final double size;
  const _CornerBracketFrame({required this.child, required this.accent, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 0.78,
            height: size * 0.78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: accent.withValues(alpha:0.2), blurRadius: 54, spreadRadius: 16)],
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: size * 0.62,
                height: size * 0.62,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha:0.05),
                  borderRadius: BorderRadius.circular(size * 0.22),
                  border: Border.all(color: Colors.white.withValues(alpha:0.14)),
                ),
                child: Center(child: child),
              ),
            ),
          ),
          CustomPaint(
            size: Size(size, size),
            painter: _CornerBracketPainter(color: accent),
          ),
        ],
      ),
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  final Color color;
  _CornerBracketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha:0.9)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final len = size.width * 0.12;
    final inset = size.width * 0.06;
    final w = size.width;
    final h = size.height;

    // top-left
    canvas.drawLine(Offset(inset, inset + len), Offset(inset, inset), paint);
    canvas.drawLine(Offset(inset, inset), Offset(inset + len, inset), paint);
    // top-right
    canvas.drawLine(Offset(w - inset - len, inset), Offset(w - inset, inset), paint);
    canvas.drawLine(Offset(w - inset, inset), Offset(w - inset, inset + len), paint);
    // bottom-left
    canvas.drawLine(Offset(inset, h - inset - len), Offset(inset, h - inset), paint);
    canvas.drawLine(Offset(inset, h - inset), Offset(inset + len, h - inset), paint);
    // bottom-right
    canvas.drawLine(Offset(w - inset - len, h - inset), Offset(w - inset, h - inset), paint);
    canvas.drawLine(Offset(w - inset, h - inset), Offset(w - inset, h - inset - len), paint);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketPainter oldDelegate) => oldDelegate.color != color;
}

/// Minimal icon-only circular action button — a soft accent-filled disc
/// with a bold rounded glyph, no text, press-scale feedback.
class _CircularIconButton extends StatefulWidget {
  final Color accent;
  final IconData icon;
  final bool loading;
  final VoidCallback? onTap;
  final double size;
  const _CircularIconButton({
    required this.accent,
    required this.icon,
    required this.onTap,
    this.loading = false,
    this.size = 58,
  });

  @override
  State<_CircularIconButton> createState() => _CircularIconButtonState();
}

class _CircularIconButtonState extends State<_CircularIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: widget.accent.withValues(alpha:0.45), blurRadius: 22, offset: const Offset(0, 8)),
            ],
          ),
          child: Center(
            child: widget.loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: AppColors.onAccent, strokeWidth: 2.4),
                  )
                : Icon(widget.icon, color: AppColors.onAccent, size: 26),
          ),
        ),
      ),
    );
  }
}

/// Labeled action button — reserved for primary form submissions (e.g.
/// Sign in) where a text affordance keeps the action unambiguous.
class _PrimaryButton extends StatefulWidget {
  final String label;
  final Color accent;
  final bool loading;
  final VoidCallback? onTap;
  const _PrimaryButton({required this.label, required this.accent, required this.onTap, this.loading = false});

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            color: widget.accent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(color: widget.accent.withValues(alpha:0.35), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Center(
            child: widget.loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: AppColors.onAccent, strokeWidth: 2.4),
                  )
                : Text(
                    widget.label,
                    style: GoogleFonts.ibmPlexSans(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.onAccent),
                  ),
          ),
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// TOPOGRAPHIC CONTOUR + GRATICULE BACKGROUND
/// ------------------------------------------------------------------
class _TopoPainter extends CustomPainter {
  final double progress; // 0..1, drives slow drift
  final Color accent;
  _TopoPainter({required this.progress, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    // contour lines
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    const lineCount = 7;
    for (int i = 0; i < lineCount; i++) {
      final baseY = size.height * (0.08 + i * 0.13);
      final path = Path();
      final amp = 26.0 + (i % 3) * 10;
      final phase = progress * 2 * pi + i * 0.9;
      for (double x = 0; x <= size.width; x += 6) {
        final y = baseY + sin((x / size.width * 2 * pi) + phase) * amp;
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      linePaint.color = (i.isEven ? accent : Colors.white).withValues(alpha:0.045 + (i % 2) * 0.018);
      canvas.drawPath(path, linePaint);
    }

    // faint graticule
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha:0.03)
      ..strokeWidth = 1;
    const spacing = 46.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TopoPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.accent != accent;
}

/// ------------------------------------------------------------------
/// LOGIN SCREEN
/// ------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  Future<void> _handleLogin() async {
  setState(() {
    _isLoading = true;
    _errorMessage = null;
  });

  try {
    await AuthService.signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    await NotificationService.registerCurrentDevice();

    final profile = await AuthService.getCurrentProfile();

    if (!mounted) return;

    if (profile != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TasksScreen(profile: profile),
        ),
      );
    } else {
      setState(() {
        _errorMessage =
            'Login succeeded, but no profile found. Contact your Administrator.';
      });
    }
  } catch (e) {
    debugPrint('LOGIN ERROR: $e');

    if (mounted) {
      setState(() {
        _errorMessage = 'Invalid email or password. Please try again.';
      });
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.62),
                radius: 1.35,
                colors: [AppColors.bgTop, AppColors.bgMid, AppColors.bgDeep],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
            child: SizedBox.expand(),
          ),
          CustomPaint(size: Size.infinite, painter: _TopoPainter(progress: 0.2, accent: AppColors.steel)),

          SafeArea(
            child: Column(
              children: [
                const _DeviceStatusBar(accent: AppColors.steel),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _StaggeredWidget(
                            delay: 80,
                            child: Column(
                              children: [
                                _CornerBracketFrame(
                                  accent: AppColors.steel,
                                  size: 92,
                                  child: const Icon(Icons.lock_outline_rounded, color: AppColors.textPrimary, size: 26),
                                ),
                                const SizedBox(height: 20),
                                Text('Welcome back', textAlign: TextAlign.center, style: _display(25, w: FontWeight.w700, ls: -0.3)),
                                const SizedBox(height: 8),
                                Text(
                                  'Sign in with your MPDO field credentials',
                                  textAlign: TextAlign.center,
                                  style: _body(13.5, c: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 36),

                          _StaggeredWidget(
                            delay: 200,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                                child: Container(
                                  padding: const EdgeInsets.all(22),
                                  decoration: BoxDecoration(
                                    color: AppColors.bgSurface.withValues(alpha:0.55),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: AppColors.border, width: 1),
                                  ),
                                  child: Column(
                                    children: [
                                      _FieldLabel(text: 'EMAIL ADDRESS'),
                                      const SizedBox(height: 6),
                                      _buildTextField(
                                        controller: _emailController,
                                        hintText: 'name@rosario.gov.ph',
                                        icon: Icons.email_outlined,
                                        keyboardType: TextInputType.emailAddress,
                                      ),
                                      const SizedBox(height: 18),
                                      _FieldLabel(text: 'PASSWORD'),
                                      const SizedBox(height: 6),
                                      _buildTextField(
                                        controller: _passwordController,
                                        hintText: '••••••••',
                                        icon: Icons.lock_outline_rounded,
                                        isPassword: true,
                                        obscureText: _obscurePassword,
                                        onTogglePassword: () => setState(() => _obscurePassword = !_obscurePassword),
                                      ),
                                      if (_errorMessage != null) ...[
                                        const SizedBox(height: 16),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: AppColors.crimson.withValues(alpha:0.12),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: AppColors.crimson.withValues(alpha:0.35)),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.error_outline_rounded, color: AppColors.crimson, size: 17),
                                              const SizedBox(width: 9),
                                              Expanded(
                                                child: Text(
                                                  _errorMessage!,
                                                  style: _body(12.5, w: FontWeight.w500, c: AppColors.crimson),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 26),
                                      _PrimaryButton(
                                        label: 'Sign in',
                                        accent: AppColors.amber,
                                        loading: _isLoading,
                                        onTap: _isLoading ? null : _handleLogin,
                                      ),
                                      const SizedBox(height: 14),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          _PulseDot(color: AppColors.teal, size: 6),
                                          const SizedBox(width: 7),
                                          Text('CONNECTION SECURED', style: _mono(9.5, c: AppColors.textTertiary, ls: 1.4)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),

                          _StaggeredWidget(
                            delay: 320,
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Container(height: 1, color: AppColors.border)),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      child: Text('NEED ACCESS', style: _mono(9.5, c: AppColors.textTertiary, ls: 1.4)),
                                    ),
                                    Expanded(child: Container(height: 1, color: AppColors.border)),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  "Don't have an account?\nContact your MPDO Administrator.",
                                  textAlign: TextAlign.center,
                                  style: _body(12, c: AppColors.textTertiary, h: 1.6),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType? keyboardType,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onTogglePassword,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: GoogleFonts.ibmPlexMono(color: AppColors.textPrimary, fontSize: 13.5),
      cursorColor: AppColors.amber,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: GoogleFonts.ibmPlexMono(color: AppColors.textTertiary, fontSize: 13.5),
        prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 19),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AppColors.textSecondary,
                  size: 19,
                ),
                onPressed: onTogglePassword,
                splashRadius: 20,
              )
            : null,
        filled: true,
        fillColor: AppColors.bgInset.withValues(alpha:0.8),
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: AppColors.amber, width: 1.4),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: _mono(10, c: AppColors.textTertiary, ls: 1.4)),
    );
  }
}

/// ------------------------------------------------------------------
/// STAGGERED REVEAL WIDGET
/// ------------------------------------------------------------------
class _StaggeredWidget extends StatefulWidget {
  final Widget child;
  final int delay;

  const _StaggeredWidget({required this.child, required this.delay});

  @override
  State<_StaggeredWidget> createState() => _StaggeredWidgetState();
}

class _StaggeredWidgetState extends State<_StaggeredWidget> {
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) setState(() => _isVisible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 600),
      opacity: _isVisible ? 1.0 : 0.0,
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _isVisible ? 0 : 18, 0),
        child: widget.child,
      ),
    );
  }
}
