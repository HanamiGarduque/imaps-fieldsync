import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'tasks_screen.dart';

/// ==================================================================
/// DESIGN TOKENS
/// Original variables are 100% preserved.
/// ==================================================================
class AppColors {
  static const bgTop = Color(0xFF2E2B8C);
  static const bgMid = Color(0xFF201E5E);
  static const bgDeep = Color(0xFF15142F);
  static const bgSurface = Color(0xFF1C1B4C);
  static const bgSurfaceAlt = Color(0xFF211F58);
  static const bgInset = Color(0xFF171638);
  static const border = Color(0xFF32306E);
  static const borderBright = Color(0xFF423F8A);
  static const textPrimary = Color(0xFFEEEEFA);
  static const textSecondary = Color(0xFFA8ABCB);
  static const textTertiary = Color(0xFF6E7199);
  static const amber = Color(0xFFD8A643);
  static const amberDim = Color(0xFFB07F2A);
  static const teal = Color(0xFF3FCDB0);
  static const steel = Color(0xFF7FA8E0);
  static const crimson = Color(0xFFEB6354);
  static const onAccent = Color(0xFF15142F);
  
  static const surfaceGlass = Color(0x261C1B4C);
}

class AppText {
  static TextStyle display(double size, {FontWeight w = FontWeight.w600, Color? c, double? ls, double? h}) => 
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? AppColors.textPrimary, letterSpacing: ls ?? -1.0, height: h ?? 1.1);
      
  static TextStyle body(double size, {FontWeight w = FontWeight.w400, Color? c, double? h}) => 
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? AppColors.textSecondary, height: h ?? 1.6);
      
  static TextStyle label(double size, {FontWeight w = FontWeight.w600, Color? c, double? ls}) => 
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? AppColors.textTertiary, letterSpacing: ls ?? 1.5);
}

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

  final List<Map<String, dynamic>> _onboardingData = [
    {
      "tag": "ZONING & ANALYTICS",
      "eyebrow": "ROSARIO MPDO",
      "title": "Map Your\nField",
      "subtitle": "The official spatial analytics tool. Access intelligent municipal data on the go.",
    },
    {
      "tag": "LIVE UPLINK",
      "eyebrow": "DATA QUALITY",
      "title": "Seamless\nSync",
      "subtitle": "Push zoning classifications to the central architecture in real-time, instantly.",
    },
    {
      "tag": "ENCRYPTED NODE",
      "eyebrow": "ACCESS CONTROL",
      "title": "Secure &\nReady",
      "subtitle": "Empowering field inspectors with 99.9% uptime and uncompromised privacy.",
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _onboardingData.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 600), curve: Curves.easeOutExpo);
    } else {
      _handleGetStarted();
    }
  }

  Future<void> _handleGetStarted() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    // PRESERVED EXACT ROUTING LOGIC
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 1000),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic),
            child: const LoginScreen(),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(
        children: [
          // 1. The Dynamic Mesh Background
          const Positioned.fill(child: _GeospatialMeshBackground()),
          
          SafeArea(
            child: Column(
              children: [
                // Header
                _StaggeredReveal(
                  delay: 200,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const _PulseRing(color: AppColors.amber),
                            const SizedBox(width: 12),
                            Text('iMAPS FieldSync', style: AppText.display(14, w: FontWeight.w700, ls: 0.5)),
                          ],
                        ),
                        if (_currentPage < _onboardingData.length - 1)
                          GestureDetector(
                            onTap: () => _pageController.animateToPage(_onboardingData.length - 1, duration: const Duration(milliseconds: 600), curve: Curves.easeOutExpo),
                            child: Text('SKIP', style: AppText.label(12, c: AppColors.amber)),
                          ),
                      ],
                    ),
                  ),
                ),
                
                const Spacer(),
                
                // Cinematic Bottom Panel
                _StaggeredReveal(
                  delay: 400,
                  child: _buildFloatingGlassPanel(),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingGlassPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      height: MediaQuery.of(context).size.height * 0.42,
      child: Stack(
        children: [
          // Glass Base
          ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceGlass,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: AppColors.bgDeep.withValues(alpha: 0.9), blurRadius: 40, offset: const Offset(0, 20))
                  ],
                ),
              ),
            ),
          ),
          
          // Content
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (idx) => setState(() => _currentPage = idx),
                    itemCount: _onboardingData.length,
                    itemBuilder: (context, index) {
                      final data = _onboardingData[index];
                      // Parallax effect on swipe
                      return AnimatedBuilder(
                        animation: _pageController,
                        builder: (context, child) {
                          double value = 1.0;
                          if (_pageController.position.haveDimensions) {
                            value = _pageController.page! - index;
                            value = (1 - (value.abs() * 0.3)).clamp(0.0, 1.0);
                          }
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 20 * (1 - value)),
                              child: child,
                            ),
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Text(data['tag'], style: AppText.label(11, c: AppColors.amber)),
                                const SizedBox(width: 12),
                                Expanded(child: Container(height: 1, color: AppColors.borderBright)),
                                const SizedBox(width: 12),
                                Text(data['eyebrow'], style: AppText.label(10, c: AppColors.textTertiary)),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(data['title'], style: AppText.display(48, w: FontWeight.w800, ls: -2.0, h: 1.0)),
                            const SizedBox(height: 16),
                            Text(data['subtitle'], style: AppText.body(15)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                
                // Indicators & Action
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: List.generate(_onboardingData.length, (index) {
                        final isActive = _currentPage == index;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutExpo,
                          margin: const EdgeInsets.only(right: 8),
                          height: 4,
                          width: isActive ? 32 : 12,
                          decoration: BoxDecoration(
                            color: isActive ? AppColors.amber : AppColors.borderBright,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: isActive ? [BoxShadow(color: AppColors.amber.withValues(alpha: 0.5), blurRadius: 8)] : [],
                          ),
                        );
                      }),
                    ),
                    _CinematicButton(
                      onTap: _nextPage,
                      loading: _isLoading,
                      text: _currentPage == _onboardingData.length - 1 ? 'Initialize' : 'Next',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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

  // 100% Original Business Logic Preserved
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
          _errorMessage = 'Login succeeded, but no profile found. Contact your Administrator.';
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      resizeToAvoidBottomInset: true, // Let it naturally adjust for keyboard
      body: Stack(
        children: [
          const Positioned.fill(child: _GeospatialMeshBackground(isFast: true)), // Faster particles on login
          
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      // Status Bar
                      _StaggeredReveal(
                        delay: 100,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                          child: Row(
                            children: [
                              const _PulseRing(color: AppColors.steel),
                              const SizedBox(width: 12),
                              Text('iMAPS SYSTEM', style: AppText.display(14, w: FontWeight.w700, ls: 0.5)),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.steel.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(color: AppColors.steel.withValues(alpha: 0.3)),
                                ),
                                child: Text('AES-256', style: AppText.label(10, c: AppColors.steel)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const Spacer(),
                      
                      // Central Login Module
                      _StaggeredReveal(
                        delay: 300,
                        child: _buildLoginModule(),
                      ),
                      
                      const Spacer(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginModule() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppColors.surfaceGlass,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.5),
                  boxShadow: [BoxShadow(color: AppColors.bgDeep.withValues(alpha: 0.9), blurRadius: 40, offset: const Offset(0, 20))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Animated Scanner Line Title
                    const _ScannerTitle(title: 'Secure Access'),
                    const SizedBox(height: 8),
                    Text('Authenticate credentials for municipal grid.', style: AppText.body(14)),
                    const SizedBox(height: 40),
                    
                    _CyberTextField(
                      label: 'INSPECTOR IDENTITY',
                      hint: 'name@rosario.gov.ph',
                      controller: _emailController,
                      icon: Icons.fingerprint_rounded,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 24),
                    
                    _CyberTextField(
                      label: 'PASSWORD',
                      hint: '••••••••',
                      controller: _passwordController,
                      icon: Icons.lock_outline_rounded,
                      isPassword: true,
                      obscureText: _obscurePassword,
                      onToggleVisibility: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    
                    // Animated Error Container
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutExpo,
                      child: _errorMessage == null ? const SizedBox.shrink() : Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.crimson.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.crimson.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: AppColors.crimson, size: 20),
                              const SizedBox(width: 12),
                              Expanded(child: Text(_errorMessage!, style: AppText.label(12, c: AppColors.crimson, ls: 0.5))),
                            ],
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: _CinematicButton(
                        onTap: _handleLogin,
                        loading: _isLoading,
                        text: 'Sign In',
                        isPrimary: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// AWARD-WINNING CUSTOM ANIMATIONS & UI COMPONENTS
/// ------------------------------------------------------------------

/// Creates a stunning, interactive-feeling mesh network background
/// Mimics K-Means/Spatial clustering algorithms finding nodes.
class _GeospatialMeshBackground extends StatefulWidget {
  final bool isFast;
  const _GeospatialMeshBackground({this.isFast = false});

  @override
  State<_GeospatialMeshBackground> createState() => _GeospatialMeshBackgroundState();
}

class _GeospatialMeshBackgroundState extends State<_GeospatialMeshBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Particle> _particles = [];
  final int _particleCount = 35;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    
    final random = math.Random();
    for (int i = 0; i < _particleCount; i++) {
      _particles.add(_Particle(
        x: random.nextDouble(),
        y: random.nextDouble(),
        vx: (random.nextDouble() - 0.5) * (widget.isFast ? 0.003 : 0.001),
        vy: (random.nextDouble() - 0.5) * (widget.isFast ? 0.003 : 0.001),
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.5,
          colors: [AppColors.bgTop, AppColors.bgMid, AppColors.bgDeep],
          stops: [0.0, 0.4, 1.0],
        ),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          for (var p in _particles) {
            p.x += p.vx;
            p.y += p.vy;
            if (p.x < 0 || p.x > 1) p.vx *= -1;
            if (p.y < 0 || p.y > 1) p.vy *= -1;
          }
          return CustomPaint(
            painter: _MeshPainter(particles: _particles, accentColor: AppColors.teal),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _Particle {
  double x, y, vx, vy;
  _Particle({required this.x, required this.y, required this.vx, required this.vy});
}

class _MeshPainter extends CustomPainter {
  final List<_Particle> particles;
  final Color accentColor;
  _MeshPainter({required this.particles, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 1.0;
    const maxDistance = 0.25; // 25% of screen width

    for (int i = 0; i < particles.length; i++) {
      for (int j = i + 1; j < particles.length; j++) {
        final p1 = particles[i];
        final p2 = particles[j];
        
        final dx = p1.x - p2.x;
        final dy = p1.y - p2.y;
        final distance = math.sqrt(dx * dx + dy * dy);

        if (distance < maxDistance) {
          final opacity = (1.0 - (distance / maxDistance)) * 0.15; // Faint lines
          paint.color = accentColor.withValues(alpha: opacity);
          canvas.drawLine(
            Offset(p1.x * size.width, p1.y * size.height),
            Offset(p2.x * size.width, p2.y * size.height),
            paint,
          );
        }
      }
      // Draw nodes
      canvas.drawCircle(
        Offset(particles[i].x * size.width, particles[i].y * size.height), 
        1.5, 
        Paint()..color = accentColor.withValues(alpha: 0.3)
      );
    }
  }
  @override
  bool shouldRepaint(covariant _MeshPainter old) => true;
}

/// Input field with glowing focus outline and animated label
class _CyberTextField extends StatefulWidget {
  final String label, hint;
  final TextEditingController controller;
  final IconData icon;
  final bool isPassword, obscureText;
  final VoidCallback? onToggleVisibility;
  final TextInputType? keyboardType;

  const _CyberTextField({
    required this.label, required this.hint, required this.controller, required this.icon,
    this.isPassword = false, this.obscureText = false, this.onToggleVisibility, this.keyboardType,
  });

  @override
  State<_CyberTextField> createState() => _CyberTextFieldState();
}

class _CyberTextFieldState extends State<_CyberTextField> {
  final FocusNode _focus = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _isFocused = _focus.hasFocus));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: AppText.label(11, c: _isFocused ? AppColors.amber : AppColors.textTertiary, ls: 1.5),
          child: Text(widget.label),
        ),
        const SizedBox(height: 10),
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: _isFocused ? AppColors.bgSurface.withValues(alpha: 0.9) : AppColors.bgSurface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _isFocused ? AppColors.amber : AppColors.borderBright, width: _isFocused ? 2.0 : 1.0),
            boxShadow: _isFocused ? [BoxShadow(color: AppColors.amber.withValues(alpha: 0.15), blurRadius: 24, spreadRadius: 2)] : [],
          ),
          child: TextField(
            controller: widget.controller, focusNode: _focus, obscureText: widget.obscureText, keyboardType: widget.keyboardType,
            style: AppText.body(16, c: AppColors.textPrimary), cursorColor: AppColors.amber,
            decoration: InputDecoration(
              hintText: widget.hint, hintStyle: AppText.body(16, c: AppColors.textTertiary),
              prefixIcon: Icon(widget.icon, color: _isFocused ? AppColors.amber : AppColors.textTertiary, size: 22),
              suffixIcon: widget.isPassword 
                ? IconButton(
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(widget.obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded, key: ValueKey(widget.obscureText), color: AppColors.textTertiary, size: 22),
                    ),
                    onPressed: widget.onToggleVisibility,
                  )
                : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 20),
            ),
          ),
        ),
      ],
    );
  }
}

/// A button that feels incredibly physical and features a sweep gradient effect.
class _CinematicButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool loading;
  final String text;
  final bool isPrimary;

  const _CinematicButton({required this.onTap, required this.text, this.loading = false, this.isPrimary = false});

  @override
  State<_CinematicButton> createState() => _CinematicButtonState();
}

class _CinematicButtonState extends State<_CinematicButton> with SingleTickerProviderStateMixin {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.loading ? null : widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.amber, AppColors.amberDim],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: AppColors.amber.withValues(alpha: _isPressed ? 0.2 : 0.4), blurRadius: _isPressed ? 12 : 30, offset: Offset(0, _isPressed ? 4 : 10))
            ],
          ),
          child: Center(
            child: widget.loading 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppColors.onAccent, strokeWidth: 3)) 
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.text, style: AppText.label(16, w: FontWeight.w700, c: AppColors.onAccent, ls: 0.5)),
                      if (!widget.isPrimary) ...[
                        const SizedBox(width: 10),
                        const Icon(Icons.arrow_forward_rounded, color: AppColors.onAccent, size: 20),
                      ]
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Adds a high-tech scanning line effect behind text.
class _ScannerTitle extends StatefulWidget {
  final String title;
  const _ScannerTitle({required this.title});
  @override
  State<_ScannerTitle> createState() => _ScannerTitleState();
}
class _ScannerTitleState extends State<_ScannerTitle> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        Text(widget.title, style: AppText.display(40, w: FontWeight.w800, ls: -1.5, h: 1.0)),
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Positioned(
            left: -50 + (_c.value * 300),
            child: Container(
              width: 10,
              height: 40,
              decoration: BoxDecoration(
                boxShadow: [BoxShadow(color: AppColors.amber.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 5)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Simple pulsing ring for live indicators.
class _PulseRing extends StatefulWidget {
  final Color color;
  const _PulseRing({required this.color});
  @override
  State<_PulseRing> createState() => _PulseRingState();
}
class _PulseRingState extends State<_PulseRing> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: 12, height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle, 
          border: Border.all(color: widget.color, width: 2),
          boxShadow: [BoxShadow(color: widget.color.withValues(alpha: _c.value * 0.8), blurRadius: 12)],
        ),
        child: Center(
          child: Container(width: 4, height: 4, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
        ),
      ),
    );
  }
}

/// Utility for staggering widget reveals.
class _StaggeredReveal extends StatefulWidget {
  final Widget child;
  final int delay;
  const _StaggeredReveal({required this.child, required this.delay});
  @override
  State<_StaggeredReveal> createState() => _StaggeredRevealState();
}
class _StaggeredRevealState extends State<_StaggeredReveal> {
  bool _visible = false;
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) setState(() => _visible = true);
    });
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 800),
      opacity: _visible ? 1.0 : 0.0,
      curve: Curves.easeOutExpo,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutExpo,
        transform: Matrix4.translationValues(0, _visible ? 0 : 30, 0),
        child: widget.child,
      ),
    );
  }
}