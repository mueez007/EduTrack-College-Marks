import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/department_config.dart';
import '../config/app_theme.dart';
import '../providers/app_state.dart';
import '../services/password_hash_service.dart';
import '../services/firestore_helper.dart';
import 'teacher/batch_select_screen.dart';
import 'student/student_dashboard_screen.dart';
import 'admin/admin_department_select_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _idController = TextEditingController();
  bool _isLoading = false;
  String _loginType = 'student';
  String? _selectedDepartmentId;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    if (DepartmentConfig.departments.isNotEmpty) {
      _selectedDepartmentId = DepartmentConfig.departments.first.id;
    }
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _idController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (_loginType == 'admin') {
      _handleAdminLogin();
      return;
    }

    if (_idController.text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter ID/USN.')),
      );
      return;
    }

    if (_loginType == 'teacher' && _selectedDepartmentId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a department.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final inputID = _idController.text.trim();

    if (_loginType == 'teacher') {
      await _handleTeacherLogin(inputID);
    } else {
      await _handleStudentLogin(inputID.toUpperCase());
    }
  }

  void _handleAdminLogin() {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.admin_panel_settings,
                  color: AppColors.primaryBlue, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Admin Login'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter admin credentials',
                style: TextStyle(color: Colors.grey[600], fontSize: 14)),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              onSubmitted: (_) => Navigator.pop(context, true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Login'),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed != true) return;
      final enteredPassword = passwordController.text;
      if (enteredPassword.isEmpty) return;

      setState(() => _isLoading = true);
      try {
        // Sign in anonymously first to read Firestore
        await FirebaseAuth.instance.signInAnonymously();

        // Check for stored admin password hash in Firestore
        final adminDoc = await FirebaseFirestore.instance
            .collection('appConfig')
            .doc('adminAuth')
            .get();

        bool isValid = false;

        if (adminDoc.exists && adminDoc.data()?['passwordHash'] != null) {
          // Verify against stored hash
          final storedHash = adminDoc.data()!['passwordHash'] as String;
          isValid = PasswordHashService.verifyPassword(enteredPassword, storedHash);
        } else {
          // First-time setup: no admin password exists yet.
          // Accept the entered password and store its hash.
          final newHash = PasswordHashService.hashPassword(enteredPassword);
          await FirebaseFirestore.instance
              .collection('appConfig')
              .doc('adminAuth')
              .set({
            'passwordHash': newHash,
            'createdAt': FieldValue.serverTimestamp(),
            'note': 'SHA-256 hashed admin password. Delete this doc to reset.',
          });
          isValid = true;
          debugPrint('[ADMIN] First-time admin password set successfully.');
        }

        if (!mounted) return;

        if (isValid) {
          Provider.of<AppState>(context, listen: false).setAdminMode(true);
          Provider.of<AppState>(context, listen: false).setUserEmail('admin');
          Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (context) => const AdminDepartmentSelectScreen(),
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid admin password.'), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        debugPrint('Admin login error: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Admin login failed: $e'), backgroundColor: Colors.red),
        );
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  Future<void> _handleTeacherLogin(String email) async {
    final deptId = _selectedDepartmentId!;
    final dept = DepartmentConfig.getById(deptId);
    final deptName = dept?.name ?? deptId;

    try {
      final credQuery = await FirestoreHelper.deptCollection(deptId, 'teacher_credentials')
          .where('email', isEqualTo: email).limit(1).get();
      if (credQuery.docs.isEmpty) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('This email is not registered for $deptName.'),
          backgroundColor: Colors.red, duration: const Duration(seconds: 4),
        ));
        return;
      }
    } catch (e) { debugPrint("Credential check error: $e"); }

    final passwordController = TextEditingController();
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.accentOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.person, color: AppColors.accentOrange, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Teacher Login')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow(Icons.email, email),
            const SizedBox(height: 4),
            _infoRow(Icons.business, deptName),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Login')),
        ],
      ),
    );

    if (confirmed != true || passwordController.text.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: passwordController.text);
      final uid = userCredential.user!.uid;
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!userDoc.exists || userDoc.get('role') != 'faculty') {
        await FirebaseAuth.instance.signOut();
        throw Exception("Access Denied: Faculty profile not found.");
      }
      if (mounted) {
        Provider.of<AppState>(context, listen: false).setDepartment(deptId, deptName);
        Provider.of<AppState>(context, listen: false).setUserEmail(email);
        Provider.of<AppState>(context, listen: false).setAdminMode(false);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const BatchSelectScreen()));
      }
    } on FirebaseAuthException catch (e) {
      _showError(_getAuthErrorMessage(e));
    } catch (e) {
      _showError('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleStudentLogin(String usn) async {
    try {
      try { await FirebaseAuth.instance.signInAnonymously(); } catch (e) { debugPrint("Anon auth: $e"); }
      String? foundDeptId;
      String? foundDeptName;
      for (final dept in DepartmentConfig.departments) {
        final query = await FirestoreHelper.deptCollection(dept.id, 'students')
            .where('usn', isEqualTo: usn).limit(1).get();
        if (query.docs.isNotEmpty) {
          foundDeptId = dept.id;
          foundDeptName = dept.name;
          break;
        }
      }
      if (foundDeptId == null) {
        throw Exception('Student with USN "$usn" not found in any department.');
      }
      if (mounted) {
        Provider.of<AppState>(context, listen: false).setDepartment(foundDeptId, foundDeptName!);
        Provider.of<AppState>(context, listen: false).setAdminMode(false);
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => StudentDashboardScreen(usn: usn),
        ));
      }
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found': case 'wrong-password': return 'Invalid teacher credentials.';
      case 'too-many-requests': return 'Too many attempts. Try again later.';
      default: return 'Login failed: ${e.message}';
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  Widget _infoRow(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 16, color: Colors.grey[500]),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey[700]))),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: AppColors.backgroundLight,
        child: Column(
          children: [
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // --- GRADIENT HEADER ---
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.only(top: 50, bottom: 30),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [AppColors.darkNavy, AppColors.primaryBlue],
                        ),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(32),
                          bottomRight: Radius.circular(32),
                        ),
                      ),
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: Column(
                          children: [
                            // MET Trust Logo (shown in white rounded container)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Image.asset(
                                'assets/logos/trust_logo.png',
                                height: 30,
                              ),
                            ),
                            const SizedBox(height: 14),
                            // College Logo
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20, spreadRadius: 1),
                                ],
                              ),
                              child: ClipOval(
                                child: Image.asset('assets/logos/college_logo.png', height: 80, width: 80, fit: BoxFit.cover),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text('MAHARAJA INSTITUTE OF TECHNOLOGY',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 1.2),
                            ),
                            const SizedBox(height: 2),
                            Text('MYSORE',
                              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.accentOrange, letterSpacing: 2),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                color: Colors.white.withValues(alpha: 0.12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                              ),
                              child: Text('EduTrack ERP',
                                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // --- LOGIN FORM ---
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                        child: Column(
                          children: [
                            // Role Selector
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.cardBorder),
                              ),
                              child: Row(
                                children: [
                                  _buildRoleTab('student', Icons.school_outlined, 'Student'),
                                  _buildRoleTab('teacher', Icons.person_outline, 'Teacher'),
                                  _buildRoleTab('admin', Icons.admin_panel_settings_outlined, 'Admin'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Department (teacher only)
                            if (_loginType == 'teacher') ...[
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.cardBorder),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Department',
                                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                                    ),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      initialValue: _selectedDepartmentId,
                                      decoration: const InputDecoration(
                                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      ),
                                      isExpanded: true,
                                      items: DepartmentConfig.departments.map((dept) {
                                        return DropdownMenuItem<String>(value: dept.id,
                                          child: Text(dept.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                                        );
                                      }).toList(),
                                      onChanged: (v) => setState(() => _selectedDepartmentId = v),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],

                            // Input Field
                            if (_loginType != 'admin') ...[
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.cardBorder),
                                ),
                                child: TextField(
                                  controller: _idController,
                                  decoration: InputDecoration(
                                    labelText: _loginType == 'teacher' ? 'Teacher Email' : 'Student USN',
                                    hintText: _loginType == 'teacher' ? 'Enter your college email' : 'e.g., 4MH23CI001',
                                    prefixIcon: Icon(_loginType == 'teacher' ? Icons.email_outlined : Icons.badge_outlined),
                                    suffixIcon: _idController.text.isNotEmpty
                                        ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _idController.clear()))
                                        : null,
                                  ),
                                  keyboardType: _loginType == 'teacher' ? TextInputType.emailAddress : TextInputType.text,
                                  textInputAction: TextInputAction.done,
                                  onChanged: (_) => setState(() {}),
                                  onSubmitted: (_) => _isLoading ? null : _handleLogin(),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],

                            // Login Button
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryBlue,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                child: _isLoading
                                    ? const SizedBox(height: 22, width: 22,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(_loginType == 'admin' ? Icons.admin_panel_settings
                                              : _loginType == 'teacher' ? Icons.login : Icons.arrow_forward, size: 20),
                                          const SizedBox(width: 8),
                                          Text(
                                            _loginType == 'admin' ? 'Admin Login'
                                                : _loginType == 'teacher' ? 'Teacher Login' : 'Student Access',
                                            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                              ),
                            ),

                            const SizedBox(height: 16),
                            Text(
                              _loginType == 'student' ? 'Enter your USN. Department is auto-detected.'
                                  : _loginType == 'teacher' ? 'Select department, enter email. Password will be requested.'
                                  : 'Full access to all departments.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(color: AppColors.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // --- FIXED BOTTOM FOOTER ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                border: Border(
                  top: BorderSide(color: AppColors.cardBorder.withValues(alpha: 0.5)),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Motivational Quote
                  Text(
                    '"Education is the most powerful weapon which you can use to change the world."',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // AIML Logo + Powered by
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.2), width: 1),
                        ),
                        child: ClipOval(
                          child: Image.asset('assets/logos/aiml_logo.png', height: 26, width: 26, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Powered by Dept. of CSE (AI & ML)',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
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

  Widget _buildRoleTab(String type, IconData icon, String label) {
    final isSelected = _loginType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() { _loginType = type; _idController.clear(); }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isSelected ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(label, style: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              )),
            ],
          ),
        ),
      ),
    );
  }
}
