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
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false; 

  // Function to handle login
  void _handleLogin() async {
    if (_idController.text.isEmpty || _passwordController.text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both ID and password.')),
      );
      return;
    }

    setState(() { _isLoading = true; });

    // Determine the login ID (Teacher uses full email, Student uses USN which is converted)
    final inputID = _idController.text.trim();
    final isLikelyStudent = !inputID.contains('@');
    final password = _passwordController.text.trim();

    // Construct the email needed for Firebase Auth
    String emailToSend = isLikelyStudent ? '${inputID.toUpperCase()}@mit.com' : inputID;
    
    try {
      // 1. Authenticate via Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailToSend, 
        password: password,
      );
      final uid = userCredential.user!.uid;

      // 2. Check Role in Firestore (Mandatory)
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (!userDoc.exists) {
        await FirebaseAuth.instance.signOut();
        throw Exception("Access Denied: Profile not registered.");
      }

      final userRole = userDoc.get('role');
      
      // 3. NAVIGATE based on Role
      if (userRole == 'faculty') {
        if (mounted) {
          Navigator.pushReplacement( 
            context,
            MaterialPageRoute(builder: (context) => const BatchSelectScreen()),
          );
          return; 
        }
      } else if (userRole == 'student') {
        if (mounted) {
          // Student Path: GOES DIRECTLY TO DASHBOARD
          Navigator.pushReplacement( 
            context,
            MaterialPageRoute(builder: (context) => const StudentDashboardScreen()),
          );
          return;
        }
      } else {
        await FirebaseAuth.instance.signOut();
        throw Exception("Access Denied: Role not authorized.");
      }

    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Invalid ID or password.';
      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
          errorMessage = 'Invalid ID or password. (Note: Student IDs must be in USN format.)';
      } else if (e.code == 'too-many-requests') {
        errorMessage = 'Too many attempts. Try again later.';
      }
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
         );
      }
    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('An unexpected error occurred. Please try again.'), backgroundColor: Colors.red),
         );
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
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
              Icon(Icons.school, size: 80, color: Theme.of(context).primaryColor),
              const SizedBox(height: 40),

              // ID Input Field (Unified for Teacher Email or Student USN)
              TextField(
                controller: _idController,
                decoration: const InputDecoration(
                  labelText: 'Teacher Email or Student USN (e.g., S101)',
                  helperText: 'Students use USN. Teachers use full email.',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 20),

              // Password Input Field
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
                textInputAction: TextInputAction.done,
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
                     textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  child: _isLoading
                    ? const SizedBox( 
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                      )
                    : const Text('Login'),
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
    _passwordController.dispose();
    super.dispose();
  }
}