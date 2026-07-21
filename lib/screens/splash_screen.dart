import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../widgets/imaps_loading_indicator.dart';
import 'home_dashboard_screen.dart';

/// ==================================================================
/// EXACT MATCH DESIGN TOKENS
/// ==================================================================
class AppColors {
  static const bg = Color(0xFFF2F4FB); //[cite: 1]
  static const surface = Color(0xFFFFFFFF); //[cite: 1]
  
  static const ink = Color(0xFF12141F); //[cite: 1]
  static const ink2 = Color(0xFF666C82); //[cite: 1]
  static const ink3 = Color(0xFFA2A7BC); //[cite: 1]
  
  static const blue1 = Color(0xFF3D6BFF); //[cite: 1]
  static const blue2 = Color(0xFF0B2FBF); //[cite: 1]
  static const blueInk = Color(0xFF1A3FC4); //[cite: 1]
  
  static const amber = Color(0xFFFFB700); //[cite: 1]
  
  static const line = Color(0x12141628); //[cite: 1]
  static const lineStrong = Color(0x21141628); //[cite: 1]
}

class AppText {
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w700, Color? c, double? ls}) => 
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? AppColors.ink, letterSpacing: ls); //[cite: 1]
      
  static TextStyle inter(double size, {FontWeight w = FontWeight.w600, Color? c, double? ls, double? lh}) => 
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? AppColors.ink, letterSpacing: ls, height: lh); //[cite: 1]
      
  static TextStyle mono(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) => 
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c ?? AppColors.ink3, letterSpacing: ls); //[cite: 1]
}

/// ==================================================================
/// SCREEN 1 — SPLASH
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
    _checkSession();
  }

  Future<void> _checkSession() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final staySignedIn = prefs.getBool('stay_signed_in') ?? false;

      if (staySignedIn) {
        final profile = await AuthService.getCurrentProfile();
        if (profile != null && mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => HomeDashboardScreen(profile: profile)),
          );
          return;
        }
      } else {
        // Force sign out to clear Supabase's auto-persisted local cache if user opted out
        if (AuthService.isLoggedIn) {
          await AuthService.signOut();
        }
      }
    } catch (e) {
      debugPrint('Session verification failed: $e');
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 700), //[cite: 1]
          pageBuilder: (_, anim, __) => FadeTransition(opacity: anim, child: const LoginScreen()), //[cite: 1]
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light); //[cite: 1]

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration( //[cite: 1]
          gradient: LinearGradient( //[cite: 1]
            colors: [AppColors.blue1, AppColors.blue2], //[cite: 1]
            begin: Alignment.topLeft, //[cite: 1]
            end: Alignment.bottomRight,  //[cite: 1]
          ),
        ),
        child: SafeArea( //[cite: 1]
          child: Column( //[cite: 1]
            children: [
              Expanded( //[cite: 1]
                child: Center( //[cite: 1]
                  child: Column( //[cite: 1]
                    mainAxisSize: MainAxisSize.min, //[cite: 1]
                    children: [
                      ClipRRect( //[cite: 1]
                        borderRadius: BorderRadius.circular(28),
                        child: SizedBox(
                          width: 96,
                          height: 96,
                          child: Transform.scale(
                            scale: 1.45,
                            child: Image.asset(
                              'assets/icon/app_icon.png',
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18), //[cite: 1]
                      
                      Column( //[cite: 1]
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('iMAPS', style: AppText.poppins(28, w: FontWeight.w800, c: Colors.white, ls: -0.01)),
                          Text('inSight', style: AppText.poppins(14, w: FontWeight.w600, c: Colors.white.withOpacity(0.72), ls: 0.02)),
                        ],
                      ),
                      const SizedBox(height: 8), //[cite: 1]
                      
                      Text( //[cite: 1]
                        'INITIALIZING FIELD UNIT…',  //[cite: 1]
                        style: AppText.mono(10.5, c: Colors.white.withOpacity(0.7), ls: 0.8) //[cite: 1]
                      ),
                    ],
                  ),
                ),
              ),
              
              const ImapsLoadingIndicator(size: 54), //[cite: 1]
              const SizedBox(height: 24), //[cite: 1]
              
              Padding( //[cite: 1]
                padding: const EdgeInsets.only(bottom: 12), //[cite: 1]
                child: Text( //[cite: 1]
                  'MUNICIPAL PLANNING & ZONING OFFICE · V1.0.0',  //[cite: 1]
                  style: AppText.mono(10, c: Colors.white.withOpacity(0.6)),  //[cite: 1]
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
  final _emailController = TextEditingController(); //[cite: 1]
  final _passwordController = TextEditingController(); //[cite: 1]
  
  bool _isLoading = false; //[cite: 1]
  bool _obscurePassword = true; //[cite: 1]
  bool _staySignedIn = false; //[cite: 1]
  String? _errorMessage; //[cite: 1]

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('saved_email');
    if (savedEmail != null && mounted) {
      setState(() {
        _emailController.text = savedEmail;
        _staySignedIn = prefs.getBool('stay_signed_in') ?? false;
      });
    }
  }

  Future<void> _handleLogin() async {
    setState(() { //[cite: 1]
      _isLoading = true; //[cite: 1]
      _errorMessage = null; //[cite: 1]
    });

    try {
      await AuthService.signIn( //[cite: 1]
        email: _emailController.text.trim(), //[cite: 1]
        password: _passwordController.text, //[cite: 1]
      );
      await NotificationService.registerCurrentDevice(); //[cite: 1]
      final profile = await AuthService.getCurrentProfile(); //[cite: 1]

      if (!mounted) return; //[cite: 1]

      if (profile != null) { //[cite: 1]
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('stay_signed_in', _staySignedIn);
        if (_staySignedIn) {
          await prefs.setString('saved_email', _emailController.text.trim());
        } else {
          await prefs.remove('saved_email');
        }

        Navigator.of(context).pushReplacement( //[cite: 1]
          MaterialPageRoute(builder: (_) => HomeDashboardScreen(profile: profile)), //[cite: 1]
        );
      } else {
        setState(() { //[cite: 1]
          _errorMessage = 'Login succeeded, but no profile found. Contact Administrator.'; //[cite: 1]
        });
      }
    } catch (e) {
      debugPrint('LOGIN ERROR: $e'); //[cite: 1]
      if (mounted) { //[cite: 1]
        setState(() { //[cite: 1]
          _errorMessage = 'Invalid ID or passcode. Please try again.'; //[cite: 1]
        });
      }
    } finally {
      if (mounted) { //[cite: 1]
        setState(() => _isLoading = false); //[cite: 1]
      }
    }
  }

  Future<void> _handleForgotPasscode() async {
    final email = _emailController.text.trim();
    
    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your email to reset your passcode.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.resetPassword(email: email);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reset instructions sent to $email', 
              style: AppText.inter(13, c: Colors.white),
            ),
            backgroundColor: const Color(0xFF10B981), 
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('RESET ERROR: $e');
      await _contactAdministrator();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _contactAdministrator() async {
    const adminEmail = 'admin@mpdo-rosario.gov.ph'; //[cite: 1]
    final String subject = Uri.encodeComponent('Passcode Reset Request'); //[cite: 1]
    final String body = Uri.encodeComponent('Please assist with resetting my passcode.'); //[cite: 1]
    
    final Uri emailLaunchUri = Uri.parse('mailto:$adminEmail?subject=$subject&body=$body'); //[cite: 1]

    try {
      final bool launched = await launchUrl(emailLaunchUri); //[cite: 1]
      if (!launched) throw Exception('No default mail client found.'); //[cite: 1]
    } catch (e) {
      debugPrint('Could not launch email client: $e'); //[cite: 1]
      await Clipboard.setData(const ClipboardData(text: adminEmail)); //[cite: 1]
      
      if (mounted) { //[cite: 1]
        setState(() => _errorMessage = null); //[cite: 1]
        ScaffoldMessenger.of(context).showSnackBar( //[cite: 1]
          SnackBar( //[cite: 1]
            content: Text( //[cite: 1]
              'Admin email copied to clipboard!',  //[cite: 1]
              style: AppText.inter(13, c: Colors.white), //[cite: 1]
            ),
            backgroundColor: AppColors.ink, //[cite: 1]
            behavior: SnackBarBehavior.floating, //[cite: 1]
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), //[cite: 1]
            duration: const Duration(seconds: 4), //[cite: 1]
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark); //[cite: 1]

    return Scaffold(
      backgroundColor: AppColors.bg, //[cite: 1]
      body: Stack( //[cite: 1]
        children: [
          const _DeviceBackground(), //[cite: 1]
          
          SafeArea( //[cite: 1]
            child: Center( //[cite: 1]
              child: SingleChildScrollView( //[cite: 1]
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20), //[cite: 1]
                physics: const BouncingScrollPhysics(), //[cite: 1]
                child: Column( //[cite: 1]
                  mainAxisAlignment: MainAxisAlignment.center, //[cite: 1]
                  crossAxisAlignment: CrossAxisAlignment.stretch, //[cite: 1]
                  children: [
                    Column( //[cite: 1]
                      children: [
                        ClipRRect( //[cite: 1]
                          borderRadius: BorderRadius.circular(20),
                          child: SizedBox(
                            width: 68,
                            height: 68,
                            child: Transform.scale(
                              scale: 1.45,
                              child: Image.asset(
                                'assets/icon/app_icon.png',
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16), //[cite: 1]
                        Column( //[cite: 1]
                          mainAxisSize: MainAxisSize.min, //[cite: 1]
                          children: [
                            Text('iMAPS', style: AppText.poppins(24, w: FontWeight.w800, ls: -0.01)), //[cite: 1]
                            Text('inSight', style: AppText.poppins(12, w: FontWeight.w600, c: AppColors.blueInk, ls: 0.02)), //[cite: 1]
                          ],
                        ),
                        const SizedBox(height: 8), //[cite: 1]
                        
                        Container( //[cite: 1]
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), //[cite: 1]
                          decoration: BoxDecoration( //[cite: 1]
                            color: AppColors.blue1.withOpacity(0.06), //[cite: 1]
                            borderRadius: BorderRadius.circular(16), //[cite: 1]
                            border: Border.all(color: AppColors.blue1.withOpacity(0.1)), //[cite: 1]
                          ),
                          child: Text( //[cite: 1]
                            'ZONING & LAND USE VERIFICATION', //[cite: 1]
                            style: AppText.mono(9.5, ls: 0.8, c: AppColors.blue2), //[cite: 1]
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 36), //[cite: 1]
                    
                    Row( //[cite: 1]
                      children: [
                        Container( //[cite: 1]
                          width: 10,  //[cite: 1]
                          height: 2.5,  //[cite: 1]
                          decoration: BoxDecoration( //[cite: 1]
                            color: AppColors.blue1,  //[cite: 1]
                            borderRadius: BorderRadius.circular(1.5), //[cite: 1]
                          ),
                        ),
                        const SizedBox(width: 8), //[cite: 1]
                        Text('LOG IN TO CONTINUE', style: AppText.mono(10, w: FontWeight.w600, ls: 1.0)), //[cite: 1]
                      ],
                    ),
                    const SizedBox(height: 12), //[cite: 1]
                    
                    Container( //[cite: 1]
                      padding: const EdgeInsets.all(18), //[cite: 1]
                      decoration: BoxDecoration( //[cite: 1]
                        color: AppColors.surface, //[cite: 1]
                        borderRadius: BorderRadius.circular(20), //[cite: 1]
                        border: Border.all(color: AppColors.line), //[cite: 1]
                        boxShadow: const [ //[cite: 1]
                          BoxShadow(color: Color(0x0A141628), blurRadius: 2, offset: Offset(0, 1)), //[cite: 1]
                          BoxShadow(color: Color(0x0F141628), blurRadius: 30, offset: Offset(0, 14)), //[cite: 1]
                        ],
                      ),
                      child: Column( //[cite: 1]
                        crossAxisAlignment: CrossAxisAlignment.start, //[cite: 1]
                        children: [
                          _buildFieldLabel('EMAIL'), //[cite: 1]
                          const SizedBox(height: 6), //[cite: 1]
                          _buildTextField( //[cite: 1]
                            controller: _emailController, //[cite: 1]
                            hintText: 'inspector@test.com', //[cite: 1]
                            icon: Icons.badge_outlined, //[cite: 1]
                            obscureText: false, //[cite: 1]
                          ),
                          
                          const SizedBox(height: 16), //[cite: 1]
                          
                          _buildFieldLabel('PASSCODE'), //[cite: 1]
                          const SizedBox(height: 6), //[cite: 1]
                          _buildTextField( //[cite: 1]
                            controller: _passwordController, //[cite: 1]
                            hintText: '••••••••', //[cite: 1]
                            icon: Icons.lock_outline, //[cite: 1]
                            obscureText: _obscurePassword, //[cite: 1]
                            isPassword: true, //[cite: 1]
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16), //[cite: 1]

                    Padding( //[cite: 1]
                      padding: const EdgeInsets.symmetric(horizontal: 4), //[cite: 1]
                      child: Row( //[cite: 1]
                        mainAxisAlignment: MainAxisAlignment.spaceBetween, //[cite: 1]
                        children: [
                          Row( //[cite: 1]
                            children: [
                              SizedBox( //[cite: 1]
                                width: 20, //[cite: 1]
                                height: 20, //[cite: 1]
                                child: Checkbox( //[cite: 1]
                                  value: _staySignedIn, //[cite: 1]
                                  onChanged: (val) { //[cite: 1]
                                    setState(() => _staySignedIn = val ?? false); //[cite: 1]
                                  },
                                  activeColor: AppColors.blue1, //[cite: 1]
                                  checkColor: Colors.white, //[cite: 1]
                                  fillColor: WidgetStateProperty.resolveWith((states) { //[cite: 1]
                                    if (states.contains(WidgetState.selected)) { //[cite: 1]
                                      return AppColors.blue1; //[cite: 1]
                                    }
                                    return Colors.transparent; //[cite: 1]
                                  }),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.5)), //[cite: 1]
                                  side: const BorderSide(color: AppColors.ink3, width: 1.5), //[cite: 1]
                                ),
                              ),
                              const SizedBox(width: 8), //[cite: 1]
                              GestureDetector( //[cite: 1]
                                onTap: () => setState(() => _staySignedIn = !_staySignedIn), //[cite: 1]
                                child: Text('Stay signed in', style: AppText.inter(13, w: FontWeight.w500, c: AppColors.ink2)), //[cite: 1]
                              ),
                            ],
                          ),
                          
                          GestureDetector(
                            onTap: _isLoading ? null : _handleForgotPasscode,
                            child: Text( //[cite: 1]
                              'Forgot passcode?', //[cite: 1]
                              style: AppText.inter(13, w: FontWeight.w600, c: AppColors.blueInk), //[cite: 1]
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    if (_errorMessage != null) ...[ //[cite: 1]
                      const SizedBox(height: 16), //[cite: 1]
                      Container( //[cite: 1]
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), //[cite: 1]
                        decoration: BoxDecoration( //[cite: 1]
                          color: const Color(0xFFE23B4E).withOpacity(0.08), //[cite: 1]
                          borderRadius: BorderRadius.circular(10), //[cite: 1]
                          border: Border.all(color: const Color(0xFFE23B4E).withOpacity(0.2)), //[cite: 1]
                        ),
                        child: Row( //[cite: 1]
                          children: [
                            const Icon(Icons.error_outline, color: Color(0xFFE23B4E), size: 16), //[cite: 1]
                            const SizedBox(width: 8), //[cite: 1]
                            Expanded( //[cite: 1]
                              child: Text(_errorMessage!, style: AppText.inter(12, w: FontWeight.w600, c: const Color(0xFFE23B4E))), //[cite: 1]
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 28), //[cite: 1]
                    
                    Container( //[cite: 1]
                      height: 48, //[cite: 1]
                      decoration: BoxDecoration( //[cite: 1]
                        gradient: const LinearGradient( //[cite: 1]
                          colors: [AppColors.blue1, AppColors.blue2], //[cite: 1]
                          begin: Alignment.topCenter, //[cite: 1]
                          end: Alignment.bottomCenter, //[cite: 1]
                        ),
                        borderRadius: BorderRadius.circular(12), //[cite: 1]
                        boxShadow: [ //[cite: 1]
                          BoxShadow( //[cite: 1]
                            color: AppColors.blue1.withOpacity(0.32), //[cite: 1]
                            blurRadius: 18, //[cite: 1]
                            offset: const Offset(0, 8), //[cite: 1]
                          )
                        ],
                      ),
                      child: ElevatedButton( //[cite: 1]
                        style: ElevatedButton.styleFrom( //[cite: 1]
                          backgroundColor: Colors.transparent, //[cite: 1]
                          shadowColor: Colors.transparent, //[cite: 1]
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), //[cite: 1]
                        ),
                        onPressed: _isLoading ? null : _handleLogin, //[cite: 1]
                        child: _isLoading  //[cite: 1]
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.white)) //[cite: 1]
                            : Text('Sign in', style: AppText.poppins(14, w: FontWeight.w600, c: Colors.white)), //[cite: 1]
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

  Widget _buildFieldLabel(String text) { //[cite: 1]
    return Text(text, style: AppText.mono(10, ls: 0.6, w: FontWeight.w600, c: AppColors.ink2)); //[cite: 1]
  }

  Widget _buildTextField({ //[cite: 1]
    required TextEditingController controller,  //[cite: 1]
    required String hintText,  //[cite: 1]
    required IconData icon, //[cite: 1]
    required bool obscureText, //[cite: 1]
    bool isPassword = false, //[cite: 1]
  }) {
    return TextFormField( //[cite: 1]
      controller: controller, //[cite: 1]
      obscureText: obscureText, //[cite: 1]
      obscuringCharacter: '•', //[cite: 1]
      style: AppText.inter(13, w: FontWeight.w600, c: AppColors.ink), //[cite: 1]
      cursorColor: AppColors.blue1, //[cite: 1]
      decoration: InputDecoration( //[cite: 1]
        hintText: hintText, //[cite: 1]
        hintStyle: AppText.inter(13, w: FontWeight.w500, c: AppColors.ink3), //[cite: 1]
        filled: true, //[cite: 1]
        fillColor: AppColors.bg.withOpacity(0.6), //[cite: 1]
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14), //[cite: 1]
        prefixIcon: Icon(icon, color: AppColors.ink3, size: 18), //[cite: 1]
        suffixIcon: isPassword  //[cite: 1]
          ? IconButton( //[cite: 1]
              icon: Icon( //[cite: 1]
                obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined, //[cite: 1]
                color: AppColors.ink3, //[cite: 1]
                size: 18, //[cite: 1]
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword), //[cite: 1]
            ) 
          : null, //[cite: 1]
        border: OutlineInputBorder( //[cite: 1]
          borderRadius: BorderRadius.circular(12), //[cite: 1]
          borderSide: const BorderSide(color: AppColors.lineStrong, width: 1.2), //[cite: 1]
        ),
        enabledBorder: OutlineInputBorder( //[cite: 1]
          borderRadius: BorderRadius.circular(12), //[cite: 1]
          borderSide: const BorderSide(color: AppColors.lineStrong, width: 1.2), //[cite: 1]
        ),
        focusedBorder: OutlineInputBorder( //[cite: 1]
          borderRadius: BorderRadius.circular(12), //[cite: 1]
          borderSide: const BorderSide(color: AppColors.blue1, width: 1.2), //[cite: 1]
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// EXACT UI COMPONENTS
/// ------------------------------------------------------------------

class _DeviceBackground extends StatelessWidget { //[cite: 1]
  const _DeviceBackground(); //[cite: 1]

  @override
  Widget build(BuildContext context) { //[cite: 1]
    return Stack( //[cite: 1]
      children: [
        Positioned( //[cite: 1]
          top: -40, //[cite: 1]
          right: -40, //[cite: 1]
          child: Container( //[cite: 1]
            width: 300, //[cite: 1]
            height: 300, //[cite: 1]
            decoration: BoxDecoration( //[cite: 1]
              shape: BoxShape.circle, //[cite: 1]
              gradient: RadialGradient( //[cite: 1]
                colors: [ //[cite: 1]
                  AppColors.blue1.withOpacity(0.15), //[cite: 1]
                  Colors.transparent, //[cite: 1]
                ],
                stops: const [0.0, 0.7], //[cite: 1]
              ),
            ),
          ),
        ),
        Positioned( //[cite: 1]
          bottom: -60, //[cite: 1]
          left: -60, //[cite: 1]
          child: Container( //[cite: 1]
            width: 260, //[cite: 1]
            height: 260, //[cite: 1]
            decoration: BoxDecoration( //[cite: 1]
              shape: BoxShape.circle, //[cite: 1]
              gradient: RadialGradient( //[cite: 1]
                colors: [ //[cite: 1]
                  AppColors.blue1.withOpacity(0.10), //[cite: 1]
                  Colors.transparent, //[cite: 1]
                ],
                stops: const [0.0, 0.7], //[cite: 1]
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExactLogoSVG extends StatelessWidget { //[cite: 1]
  final double size; //[cite: 1]
  final Color color; //[cite: 1]
  
  const _ExactLogoSVG({required this.size, required this.color}); //[cite: 1]

  @override
  Widget build(BuildContext context) { //[cite: 1]
    return SizedBox( //[cite: 1]
      width: size, //[cite: 1]
      height: size, //[cite: 1]
      child: Stack( //[cite: 1]
        alignment: Alignment.center, //[cite: 1]
        children: [
          Container( //[cite: 1]
            width: size * 0.75, //[cite: 1]
            height: size * 0.75, //[cite: 1]
            decoration: BoxDecoration( //[cite: 1]
              shape: BoxShape.circle, //[cite: 1]
              border: Border.all(color: color.withOpacity(0.5), width: 1.8), //[cite: 1]
            ),
          ),
          Container( //[cite: 1]
            width: size * 0.458,  //[cite: 1]
            height: size * 0.458, //[cite: 1]
            decoration: BoxDecoration( //[cite: 1]
              shape: BoxShape.circle, //[cite: 1]
              border: Border.all(color: color, width: 1.8), //[cite: 1]
            ),
          ),
          Container( //[cite: 1]
            width: size * 0.15, //[cite: 1]
            height: size * 0.15, //[cite: 1]
            decoration: BoxDecoration( //[cite: 1]
              color: color, //[cite: 1]
              shape: BoxShape.circle, //[cite: 1]
            ),
          ),
        ],
      ),
    );
  }
}
