import 'dart:async';
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'home_dashboard_screen.dart';

/// ==================================================================
/// EXACT MATCH DESIGN TOKENS
/// ==================================================================
class AppColors {
  static const bg = Color(0xFFF2F4FB); 
  static const surface = Color(0xFFFFFFFF);
  
  static const ink = Color(0xFF12141F);
  static const ink2 = Color(0xFF666C82);
  static const ink3 = Color(0xFFA2A7BC); 
  
  static const blue1 = Color(0xFF3D6BFF); 
  static const blue2 = Color(0xFF0B2FBF);
  static const blueInk = Color(0xFF1A3FC4);
  
  static const amber = Color(0xFFFFB700); 
  
  static const line = Color(0x12141628); 
  static const lineStrong = Color(0x21141628); 
}

class AppText {
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w700, Color? c, double? ls}) => 
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? AppColors.ink, letterSpacing: ls);
      
  static TextStyle inter(double size, {FontWeight w = FontWeight.w600, Color? c, double? ls, double? lh}) => 
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? AppColors.ink, letterSpacing: ls, height: lh);
      
  static TextStyle mono(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) => 
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c ?? AppColors.ink3, letterSpacing: ls);
}

/// ==================================================================
/// SCREEN 1 — SPLASH
/// Purely presentational; auto-advances into the login flow
/// after a short delay.
/// ==================================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Keep it displayed slightly longer to appreciate the loading sequence
    Timer(const Duration(seconds: 3), () { 
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 700),
          pageBuilder: (_, anim, __) => FadeTransition(opacity: anim, child: const LoginScreen()),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Light text overlay since the background is now a dark blue gradient
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    return Scaffold(
      body: Container(
        // Exact gradient match from the HTML: linear-gradient(155deg, var(--blue-1), var(--blue-2))
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.blue1, AppColors.blue2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight, 
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Glassmorphic Logo Match
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withOpacity(0.35)),
                            ),
                            child: const Center(
                              child: _ExactLogoSVG(size: 36, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      
                      // Wordmark Match
                      RichText(
                        text: TextSpan(children: [
                          TextSpan(
                            text: 'InSight', 
                            style: AppText.poppins(28, w: FontWeight.w800, c: Colors.white, ls: -0.01)
                          ),
                          TextSpan(
                            text: '.', 
                            style: AppText.poppins(28, w: FontWeight.w800, c: Colors.white.withOpacity(0.7), ls: -0.01)
                          ),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      
                      // Tagline Match
                      Text(
                        'INITIALIZING FIELD UNIT…', 
                        style: AppText.mono(10.5, c: Colors.white.withOpacity(0.7), ls: 0.8)
                      ),
                    ],
                  ),
                ),
              ),
              
              // Bottom Loading Icon Animation[cite: 5]
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.amber),
                ),
              ),
              const SizedBox(height: 24), // Push away from footer
              
              // Footer Tag Match
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'MUNICIPAL PLANNING & ZONING OFFICE · V1.0.0', 
                  style: AppText.mono(10, c: Colors.white.withOpacity(0.6)), 
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// REFINED LOGIN SCREEN
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
  bool _staySignedIn = false;
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
          MaterialPageRoute(builder: (_) => HomeDashboardScreen(profile: profile)),
        );
      } else {
        setState(() {
          _errorMessage = 'Login succeeded, but no profile found. Contact Administrator.';
        });
      }
    } catch (e) {
      debugPrint('LOGIN ERROR: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Invalid ID or passcode. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _contactAdministrator() async {
    const adminEmail = 'admin@mpdo-rosario.gov.ph';
    final String subject = Uri.encodeComponent('Passcode Reset Request');
    final String body = Uri.encodeComponent('Please assist with resetting my passcode.');
    
    final Uri emailLaunchUri = Uri.parse('mailto:$adminEmail?subject=$subject&body=$body');

    try {
      final bool launched = await launchUrl(emailLaunchUri);
      if (!launched) throw Exception('No default mail client found.');
    } catch (e) {
      debugPrint('Could not launch email client: $e');
      await Clipboard.setData(const ClipboardData(text: adminEmail));
      
      if (mounted) {
        setState(() => _errorMessage = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Admin email copied to clipboard!', 
              style: AppText.inter(13, c: Colors.white),
            ),
            backgroundColor: AppColors.ink,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          const _DeviceBackground(),
          
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Sleek Header & Logo
                    Column(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              colors: [AppColors.blue1, AppColors.blue2],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.blue1.withOpacity(0.35),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              )
                            ],
                          ),
                          child: const Center(
                            child: _ExactLogoSVG(size: 26, color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('InSight', style: AppText.poppins(24, w: FontWeight.w800, ls: -0.01)),
                            Text('.', style: AppText.poppins(24, w: FontWeight.w800, c: AppColors.blue1, ls: -0.01)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.blue1.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.blue1.withOpacity(0.1)),
                          ),
                          child: Text(
                            'ZONING & LAND USE VERIFICATION',
                            style: AppText.mono(9.5, ls: 0.8, c: AppColors.blue2),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 36),
                    
                    // Section Label
                    Row(
                      children: [
                        Container(
                          width: 10, 
                          height: 2.5, 
                          decoration: BoxDecoration(
                            color: AppColors.blue1, 
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('LOG IN TO CONTINUE', style: AppText.mono(10, w: FontWeight.w600, ls: 1.0)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Core Form Card - STRICTLY INPUTS ONLY
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.line),
                        boxShadow: const [
                          BoxShadow(color: Color(0x0A141628), blurRadius: 2, offset: Offset(0, 1)),
                          BoxShadow(color: Color(0x0F141628), blurRadius: 30, offset: Offset(0, 14)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('EMAIL'),
                          const SizedBox(height: 6),
                          _buildTextField(
                            controller: _emailController,
                            hintText: 'inspector@test.com',
                            icon: Icons.badge_outlined,
                            obscureText: false,
                          ),
                          
                          const SizedBox(height: 16),
                          
                          _buildFieldLabel('PASSCODE'),
                          const SizedBox(height: 6),
                          _buildTextField(
                            controller: _passwordController,
                            hintText: '••••••••',
                            icon: Icons.lock_outline,
                            obscureText: _obscurePassword,
                            isPassword: true,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Options Row: Checkbox + Forgot Passcode
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: Checkbox(
                                  value: _staySignedIn,
                                  onChanged: (val) {
                                    setState(() => _staySignedIn = val ?? false);
                                  },
                                  activeColor: AppColors.blue1,
                                  checkColor: Colors.white,
                                  fillColor: WidgetStateProperty.resolveWith((states) {
                                    if (states.contains(WidgetState.selected)) {
                                      return AppColors.blue1;
                                    }
                                    return Colors.transparent;
                                  }),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.5)),
                                  side: const BorderSide(color: AppColors.ink3, width: 1.5),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => setState(() => _staySignedIn = !_staySignedIn),
                                child: Text('Stay signed in', style: AppText.inter(13, w: FontWeight.w500, c: AppColors.ink2)),
                              ),
                            ],
                          ),
                          
                          // Sleek Text Button
                          GestureDetector(
                            onTap: _contactAdministrator,
                            child: Text(
                              'Forgot passcode?',
                              style: AppText.inter(13, w: FontWeight.w600, c: AppColors.blueInk),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE23B4E).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE23B4E).withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Color(0xFFE23B4E), size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_errorMessage!, style: AppText.inter(12, w: FontWeight.w600, c: const Color(0xFFE23B4E))),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 28),
                    
                    // Primary Sign In Button
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.blue1, AppColors.blue2],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.blue1.withOpacity(0.32),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          )
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isLoading ? null : _handleLogin,
                        child: _isLoading 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.white))
                            : Text('Sign in', style: AppText.poppins(14, w: FontWeight.w600, c: Colors.white)),
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

  Widget _buildFieldLabel(String text) {
    return Text(text, style: AppText.mono(10, ls: 0.6, w: FontWeight.w600, c: AppColors.ink2));
  }

  Widget _buildTextField({
    required TextEditingController controller, 
    required String hintText, 
    required IconData icon,
    required bool obscureText,
    bool isPassword = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      obscuringCharacter: '•',
      style: AppText.inter(13, w: FontWeight.w600, c: AppColors.ink),
      cursorColor: AppColors.blue1,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: AppText.inter(13, w: FontWeight.w500, c: AppColors.ink3),
        filled: true,
        fillColor: AppColors.bg.withOpacity(0.6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        prefixIcon: Icon(icon, color: AppColors.ink3, size: 18),
        suffixIcon: isPassword 
          ? IconButton(
              icon: Icon(
                obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: AppColors.ink3,
                size: 18,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ) 
          : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lineStrong, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lineStrong, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.blue1, width: 1.2),
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// EXACT UI COMPONENTS
/// ------------------------------------------------------------------

class _DeviceBackground extends StatelessWidget {
  const _DeviceBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -40,
          right: -40,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.blue1.withOpacity(0.15),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.7],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -60,
          left: -60,
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.blue1.withOpacity(0.10),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.7],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExactLogoSVG extends StatelessWidget {
  final double size;
  final Color color;
  
  const _ExactLogoSVG({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 0.75,
            height: size * 0.75,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.5), width: 1.8),
            ),
          ),
          Container(
            width: size * 0.458, 
            height: size * 0.458,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.8),
            ),
          ),
          Container(
            width: size * 0.15,
            height: size * 0.15,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}