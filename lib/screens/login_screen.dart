import 'dart:ui';
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:google_fonts/google_fonts.dart';

// TODO: Uncomment your actual imports
// import '../services/auth_service.dart';
// import '../services/notification_service.dart';
// import 'tasks_screen.dart';

/// ------------------------------------------------------------------
/// WELCOME / GET STARTED SCREEN
/// ------------------------------------------------------------------
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLoading = false;
  late AnimationController _floatingController;

  // Onboarding Data specific to iMAPS FieldSync
  final List<Map<String, dynamic>> _onboardingData = [
    {
      "title": "Map Your Field",
      "subtitle": "The official field inspection tool for Rosario iMAPS. Access precise geospatial data on the go.",
      "icon": Icons.map_outlined,
      "color": const Color(0xFFE0F2FE), // Soft light blue
      "iconColor": const Color(0xFF0284C7),
    },
    {
      "title": "Seamless Sync",
      "subtitle": "Synchronize your field reports directly to the municipal network in real-time.",
      "icon": Icons.cloud_sync_outlined,
      "color": const Color(0xFFF3E8FF), // Soft purple
      "iconColor": const Color(0xFF7E22CE),
    },
    {
      "title": "Ready to Inspect",
      "subtitle": "Empowering inspectors with accurate, secure, and up-to-date information anywhere.",
      "icon": Icons.verified_user_outlined,
      "color": const Color(0xFFECFDF5), // Soft mint green
      "iconColor": const Color(0xFF059669),
    },
  ];

  @override
  void initState() {
    super.initState();
    // Subtle floating animation for the central icons
    _floatingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _floatingController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _onboardingData.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    } else {
      _handleGetStarted();
    }
  }

  void _skip() {
    _pageController.animateToPage(
      _onboardingData.length - 1,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _handleGetStarted() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: const LoginScreen(), 
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Clean white background like the reference
      body: SafeArea(
        child: Column(
          children: [
            // --- TOP HEADER ---
            Padding(
              padding: const EdgeInsets.only(top: 24.0, bottom: 16.0),
              child: Text(
                'iMAPS FieldSync',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A), // Dark slate
                  letterSpacing: -0.2,
                ),
              ),
            ),

            // --- CAROUSEL CONTENT ---
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _onboardingData.length,
                itemBuilder: (context, index) {
                  return _buildPageContent(
                    data: _onboardingData[index],
                    index: index,
                  );
                },
              ),
            ),

            // --- BOTTOM NAVIGATION BAR ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Skip Button (Hidden on the last page)
                  AnimatedOpacity(
                    opacity: _currentPage == _onboardingData.length - 1 ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 300),
                    child: IgnorePointer(
                      ignoring: _currentPage == _onboardingData.length - 1,
                      child: TextButton(
                        onPressed: _skip,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF64748B),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          backgroundColor: const Color(0xFFF1F5F9), // Soft gray pill
                        ),
                        child: Text(
                          'Skip',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Page Indicators (Dots / Dashes)
                  Row(
                    children: List.generate(
                      _onboardingData.length,
                      (index) => _buildIndicator(index == _currentPage),
                    ),
                  ),

                  // Next / Let's Go Button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _nextPage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A), // Dark stylish button
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24), // Pill shape
                      ),
                    ),
                    child: _isLoading && _currentPage == _onboardingData.length - 1
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.0,
                            ),
                          )
                        : Text(
                            _currentPage == _onboardingData.length - 1 ? "Let's Go" : "Next",
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Individual Page Builder
  Widget _buildPageContent({required Map<String, dynamic> data, required int index}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Illustration / Icon wrapped in an organic blob
          SizedBox(
            height: 300,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Custom Organic Background Shape
                CustomPaint(
                  size: const Size(280, 280),
                  painter: _OrganicBlobPainter(color: data['color']),
                ),
                // Floating Icon inside the blob
                AnimatedBuilder(
                  animation: _floatingController,
                  builder: (context, child) {
                    // Different floating offset pattern based on the page index
                    final offset = sin(_floatingController.value * 2 * pi + (index * pi / 2)) * 12;
                    return Transform.translate(
                      offset: Offset(0, offset),
                      child: child,
                    );
                  },
                  child: Icon(
                    data['icon'],
                    size: 100,
                    color: data['iconColor'],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
          
          // Title
          Text(
            data['title'],
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          
          // Subtitle
          Text(
            data['subtitle'],
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: const Color(0xFF64748B), // Slate 500
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // Animated Dot / Dash Indicator
  Widget _buildIndicator(bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 6,
      width: isActive ? 20 : 6, // Expands into a dash when active
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// CUSTOM PAINTER: ORGANIC BACKGROUND BLOB
/// Draws a smooth, uneven, organic shape similar to the reference art
/// ------------------------------------------------------------------
class _OrganicBlobPainter extends CustomPainter {
  final Color color;

  _OrganicBlobPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    
    // Creating an organic, fluid shape using cubic bezier curves
    path.moveTo(size.width * 0.2, size.height * 0.3);
    path.cubicTo(
      size.width * 0.1, size.height * 0.05, 
      size.width * 0.7, size.height * 0.0, 
      size.width * 0.85, size.height * 0.2
    );
    path.cubicTo(
      size.width * 1.0, size.height * 0.4, 
      size.width * 0.95, size.height * 0.8, 
      size.width * 0.7, size.height * 0.9
    );
    path.cubicTo(
      size.width * 0.4, size.height * 1.0, 
      size.width * 0.05, size.height * 0.85, 
      size.width * 0.1, size.height * 0.6
    );
    path.cubicTo(
      size.width * 0.15, size.height * 0.45, 
      size.width * 0.3, size.height * 0.5, 
      size.width * 0.2, size.height * 0.3
    );

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _OrganicBlobPainter oldDelegate) {
    return oldDelegate.color != color;
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

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // TODO: Uncomment actual auth logic
      // Simulating network request for the demo UI
      await Future.delayed(const Duration(seconds: 2));
      throw Exception("Demo Mode: Backend not connected.");
    } catch (e) {
      setState(() {
        _errorMessage = 'Invalid email or password. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      body: Stack(
        children: [
          // 1. Clean, subtle background (No flashy gradients)
          Container(
            color: const Color(0xFF0F172A),
          ),
          
          // 2. Main Content (Staggered)
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    
                    // Header
                    _StaggeredWidget(
                      delay: 100,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: const Icon(
                              Icons.lock_outline_rounded,
                              color: Color(0xFF818CF8),
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Welcome Back',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Enter your credentials to access FieldSync',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Clean Form Card
                    _StaggeredWidget(
                      delay: 250,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF334155),
                            width: 1.0,
                          ),
                        ),
                        child: Column(
                          children: [
                            // Email Field
                            _buildTextField(
                              controller: _emailController,
                              hintText: 'Email Address',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 16),
                            
                            // Password Field
                            _buildTextField(
                              controller: _passwordController,
                              hintText: 'Password',
                              icon: Icons.lock_outline,
                              isPassword: true,
                              obscureText: _obscurePassword,
                              onTogglePassword: () {
                                setState(() => _obscurePassword = !_obscurePassword);
                              },
                            ),
                            
                            // Error Message
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.red.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline,
                                        color: Colors.redAccent, size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: GoogleFonts.inter(
                                          color: Colors.redAccent,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            
                            const SizedBox(height: 32),
                            
                            // Professional Sign In Button
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4F46E5),
                                  disabledBackgroundColor: const Color(0xFF334155),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : Text(
                                        'Sign In',
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Footer
                    _StaggeredWidget(
                      delay: 400,
                      child: Text(
                        'Don\'t have an account?\nContact your MPDO Administrator.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: Colors.white38,
                          fontSize: 12,
                          height: 1.5,
                        ),
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

  /// Helper method for clean, professional input fields
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
      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
      cursorColor: const Color(0xFF818CF8),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
        prefixIcon: Icon(icon, color: Colors.white54, size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: Colors.white54,
                  size: 20,
                ),
                onPressed: onTogglePassword,
                splashRadius: 20,
              )
            : null,
        filled: true,
        fillColor: const Color(0xFF0F172A), // Darker inset background
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: const Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF818CF8), width: 1.5),
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// PROPER STAGGERED ANIMATION WIDGET
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
      if (mounted) {
        setState(() {
          _isVisible = true;
        });
      }
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
        transform: Matrix4.translationValues(0, _isVisible ? 0 : 20, 0),
        child: widget.child,
      ),
    );
  }
}