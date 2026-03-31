import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'teacher/batch_select_screen.dart';
import 'student/student_dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _idController = TextEditingController();
  bool _isLoading = false;
  String _loginType = 'student'; // Default to student

  // Function to handle login
  void _handleLogin() async {
    if (_idController.text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter ID/USN.')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final inputID = _idController.text.trim();

    if (_loginType == 'teacher') {
      await _handleTeacherLogin(inputID);
    } else {
      await _handleStudentLogin(inputID.toUpperCase());
    }
  }

  // --- TEACHER LOGIN (Existing Firebase Auth) ---
  Future<void> _handleTeacherLogin(String email) async {
    final passwordController = TextEditingController();

    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Teacher Login'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Email: $email'),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
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
    );

    if (confirmed != true || passwordController.text.isEmpty) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: email,
            password: passwordController.text,
          );
      final uid = userCredential.user!.uid;

      // Check Role in Firestore
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!userDoc.exists || userDoc.get('role') != 'faculty') {
        await FirebaseAuth.instance.signOut();
        throw Exception("Access Denied: Faculty profile not found.");
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const BatchSelectScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      _showError(_getAuthErrorMessage(e));
    } catch (e) {
      _showError('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted)
        setState(() {
          _isLoading = false;
        });
    }
  }

  // --- STUDENT LOGIN (USN-ONLY, NO PASSWORD) ---
  Future<void> _handleStudentLogin(String usn) async {
    try {
      // 1. First try to authenticate anonymously (for Firestore rules)
      try {
        await FirebaseAuth.instance.signInAnonymously();
      } catch (e) {
        // If anonymous fails, continue anyway
        print("Anonymous auth failed: $e");
      }

      // 2. Query Firestore for student by USN
      QuerySnapshot studentQuery = await FirebaseFirestore.instance
          .collection('students')
          .where('usn', isEqualTo: usn)
          .limit(1)
          .get();

      if (studentQuery.docs.isEmpty) {
        throw Exception('Student not found. Check your USN: $usn');
      }

      // 3. Navigate to dashboard with USN parameter
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => StudentDashboardScreen(usn: usn),
          ),
        );
      }
    } catch (e) {
      _showError('Login failed: ${e.toString()}');

      // Fallback: Still navigate but with error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Limited access. Showing demo data for USN: $usn'),
            backgroundColor: Colors.orange,
          ),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => StudentDashboardScreen(usn: usn),
          ),
        );
      }
    } finally {
      if (mounted)
        setState(() {
          _isLoading = false;
        });
    }
  }

  String _getAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
        return 'Invalid teacher credentials.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      default:
        return 'Login failed: ${e.message}';
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('College Portal Login'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.school,
                size: 80,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 20),

              // Simple Login Type Selector
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        'Login As',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ToggleButtons(
                        isSelected: [
                          _loginType == 'student',
                          _loginType == 'teacher',
                        ],
                        onPressed: (index) {
                          setState(() {
                            _loginType = index == 0 ? 'student' : 'teacher';
                            _idController.text = '';
                          });
                        },
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.school, size: 20),
                                SizedBox(width: 8),
                                Text('Student'),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.person, size: 20),
                                SizedBox(width: 8),
                                Text('Teacher'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // Input Field
              TextField(
                controller: _idController,
                decoration: InputDecoration(
                  labelText: _loginType == 'teacher'
                      ? 'Teacher Email'
                      : 'Student USN',
                  helperText: _loginType == 'teacher'
                      ? 'Enter your college email'
                      : 'Enter your USN only (e.g., 1MS21CS001)',
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(
                    _loginType == 'teacher' ? Icons.email : Icons.badge,
                  ),
                  suffixIcon: _idController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () =>
                              setState(() => _idController.clear()),
                        )
                      : null,
                ),
                keyboardType: _loginType == 'teacher'
                    ? TextInputType.emailAddress
                    : TextInputType.text,
                textInputAction: TextInputAction.done,
                onChanged: (value) => setState(() {}),
                onSubmitted: (_) => _isLoading ? null : _handleLogin(),
              ),
              const SizedBox(height: 40),

              // Login Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : Text(
                          _loginType == 'teacher'
                              ? 'Teacher Login'
                              : 'Student Access',
                        ),
                ),
              ),

              // Help Text
              const SizedBox(height: 30),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Text(
                  _loginType == 'student'
                      ? 'Students: Enter USN only. No password required.'
                      : 'Teachers: Enter email. Password will be requested.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }
}
