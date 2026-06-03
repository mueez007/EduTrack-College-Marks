import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/app_theme.dart';
import '../providers/app_state.dart';
import 'login_screen.dart';
import 'teacher/teacher_home_screen.dart';
import 'teacher/batch_select_screen.dart';
import 'admin/admin_department_select_screen.dart';
import 'student/student_dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.elasticOut),
    );

    _slideAnimation = Tween<double>(begin: 30, end: 0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );

    _fadeController.forward();

    // Navigate after splash delay
    Future.delayed(const Duration(milliseconds: 3000), () async {
      if (mounted) await _navigateBasedOnSession();
    });
  }

  Future<void> _navigateBasedOnSession() async {
    final appState = Provider.of<AppState>(context, listen: false);

    // --- FIREBASE AUTH RECOVERY ---
    // If SharedPreferences fails to persist on Web refresh, but Firebase Auth is alive,
    // we recover the session securely from Firestore!
    if (!appState.isLoggedIn) {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        debugPrint("Splash: Recovering session from Firebase Auth...");
        try {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
          if (userDoc.exists) {
            final data = userDoc.data() as Map<String, dynamic>;
            appState.setUserRole(data['role']);
            appState.setUserEmail(data['email'] ?? currentUser.email);
            if (data['role'] == 'admin' || data['role'] == 'faculty') {
              if (data['departmentId'] != null) {
                appState.setDepartment(data['departmentId'], data['departmentId']);
              }
              if (data['lastSelectedBatchId'] != null) {
                appState.setSelectedBatch(
                  data['lastSelectedBatchId'], 
                  data['lastSelectedBatchName'] ?? data['lastSelectedBatchId']
                );
              }
              if (data['role'] == 'admin') {
                appState.setAdminMode(true);
              }
            }
          }
        } catch (e) {
          debugPrint("Failed to recover session: $e");
          await FirebaseAuth.instance.signOut();
        }
      }
    }

    if (!mounted) return;

    Widget destination;

    if (!appState.isLoggedIn) {
      // No saved session → go to login
      destination = const LoginScreen();
    } else if (appState.userRole == 'student') {
      // Student session → go to dashboard
      final usn = appState.studentUsn ?? '';
      destination = StudentDashboardScreen(usn: usn);
    } else if (appState.userRole == 'admin' && appState.departmentId == null) {
      // Admin without department selected → department picker
      destination = const AdminDepartmentSelectScreen();
    } else if (appState.selectedBatchId == null) {
      // Teacher/Admin with department but no batch → batch picker
      destination = const BatchSelectScreen();
    } else {
      // Teacher/Admin with department + batch → home
      destination = const TeacherHomeScreen();
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.darkNavy,
              AppColors.primaryBlue,
              Color(0xFF2563EB),
            ],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _fadeAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 2),

                    // Trust Logo (small, top)
                    Transform.translate(
                      offset: Offset(0, _slideAnimation.value),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Image.asset(
                          'assets/logos/trust_logo.png',
                          height: 40,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // College Logo (main, center)
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 30,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/logos/college_logo.png',
                            height: 130,
                            width: 130,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // College Name
                    Transform.translate(
                      offset: Offset(0, _slideAnimation.value),
                      child: Text(
                        'MAHARAJA INSTITUTE OF TECHNOLOGY',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Transform.translate(
                      offset: Offset(0, _slideAnimation.value),
                      child: Text(
                        'MYSORE',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.accentOrange,
                          letterSpacing: 3,
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // App Name
                    Transform.translate(
                      offset: Offset(0, _slideAnimation.value * 1.5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        child: Text(
                          'EduTrack ERP',
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Transform.translate(
                      offset: Offset(0, _slideAnimation.value * 1.5),
                      child: Text(
                        'Academic Management System',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),

                    const Spacer(flex: 2),

                    // Loading indicator
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: 0.4 + (_pulseController.value * 0.6),
                          child: const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Loading...',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Department & Powered by Tag
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/logos/aiml_logo.png',
                              height: 30,
                              width: 30,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Powered by',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                        Text(
                          'Dept. of CSE (AI & ML)',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
