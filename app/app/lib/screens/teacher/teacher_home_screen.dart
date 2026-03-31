import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Import necessary screens
import '../../providers/app_state.dart';
import '../login_screen.dart';
import 'batch_select_screen.dart'; 
import 'student_details_screen.dart'; 
import 'subjects_screen.dart'; 
import 'final_exam_marks_screen.dart'; 
import 'sgpa_cgpa_screen.dart'; // <-- SGPA/CGPA Screen Import

class TeacherHomeScreen extends StatelessWidget {
  const TeacherHomeScreen({super.key});

  // Function to handle logout
  void _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      // Clear selected batch state
      Provider.of<AppState>(context, listen: false).clearSelectedBatch();
      // Navigate back to Login Screen and remove all previous routes
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false, // Remove all routes below LoginScreen
      );
    } catch (e) {
      print("Error logging out: $e");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Read the selected batch from AppState using Provider
    final selectedBatchName = Provider.of<AppState>(context).selectedBatchName ?? 'No Batch Selected';

    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard - $selectedBatchName'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => _logout(context), // Call logout function
          ),
        ],
      ),
      // --- Drawer Menu ---
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
              ),
              child: Text(
                'Menu - $selectedBatchName',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_customize_outlined),
              title: const Text('Dashboard'),
              onTap: () {
                Navigator.pop(context); // Close the drawer
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: const Text('Student Details'),
              onTap: () {
                Navigator.pop(context); 
                Navigator.push( 
                  context,
                  MaterialPageRoute(builder: (context) => const StudentDetailsScreen()),
                );
              },
            ),
             ListTile(
              leading: const Icon(Icons.library_books_outlined),
              title: const Text('Subjects & IA Marks'),
              onTap: () {
                 Navigator.pop(context); 
                 Navigator.push(
                   context,
                   MaterialPageRoute(builder: (context) => const SubjectsScreen()),
                 );
              },
            ),
             ListTile(
              leading: const Icon(Icons.grading_outlined),
              title: const Text('Final Exam Marks'),
              onTap: () {
                 Navigator.pop(context); 
                 Navigator.push(
                   context,
                   MaterialPageRoute(builder: (context) => const FinalExamMarksScreen()),
                 );
              },
            ),
            // ***** CORRECTED SGPA/CGPA NAVIGATION *****
            ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: const Text('SGPA & CGPA Results'),
              onTap: () {
                 Navigator.pop(context); // Close drawer
                 // --- Navigate to SGPA/CGPA Screen ---
                 Navigator.push(
                   context,
                   MaterialPageRoute(builder: (context) => const SgpaCgpaScreen()),
                 );
                 // ------------------------------------
              },
            ),
            // ***** END OF CORRECTION *****
            const Divider(), // Visual separator
             ListTile(
              leading: const Icon(Icons.swap_horizontal_circle_outlined),
              title: const Text('Change Batch'),
              onTap: () {
                // Navigate back to Batch Selection Screen
                 Navigator.pushReplacement(
                   context,
                   MaterialPageRoute(builder: (context) => const BatchSelectScreen()),
                 );
              },
            ),
             ListTile(
              leading: const Icon(Icons.logout_outlined),
              title: const Text('Logout'),
              onTap: () => _logout(context), // Call logout function
            ),
          ],
        ),
      ),
      // --- End of Drawer ---

      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Welcome to the Teacher Dashboard for $selectedBatchName.\n\nUse the menu (☰) to navigate.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
      ),
    );
  }
}