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
import 'sgpa_cgpa_screen.dart';
import 'attendance_percentage_screen.dart'; // NEW: Attendance screen
import 'daily_absentee_screen.dart'; // NEW: Daily absentee screen

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
        SnackBar(
          content: Text('Logout failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Function to show Send Alerts dialog
  void _showSendAlertsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Automated Alerts'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('This will send alerts for:'),
            SizedBox(height: 10),
            Text('• New IA Marks', style: TextStyle(color: Colors.blue)),
            Text('• Final Exam Marks', style: TextStyle(color: Colors.green)),
            Text(
              '• Attendance % (if configured)',
              style: TextStyle(color: Colors.orange),
            ),
            SizedBox(height: 10),
            Text(
              'Only sends for current semester marks.',
              style: TextStyle(fontSize: 12),
            ),
            Text(
              'Requires n8n setup.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _triggerAlerts(context);
            },
            child: const Text('Send Alerts'),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerAlerts(BuildContext context) async {
    final scaffold = ScaffoldMessenger.of(context);
    final batchId = Provider.of<AppState>(
      context,
      listen: false,
    ).selectedBatchId;

    if (batchId == null) {
      scaffold.showSnackBar(
        const SnackBar(
          content: Text('Error: No batch selected'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    scaffold.showSnackBar(
      const SnackBar(
        content: Text('Sending alerts...'),
        backgroundColor: Colors.blue,
      ),
    );

    try {
      // TODO: Implement Cloud Function call to trigger n8n
      await Future.delayed(const Duration(seconds: 2));

      scaffold.showSnackBar(
        const SnackBar(
          content: Text('Alerts queued successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Read the selected batch from AppState using Provider
    final selectedBatchName =
        Provider.of<AppState>(context).selectedBatchName ?? 'No Batch Selected';

    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard - $selectedBatchName'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'Send Alerts',
            onPressed: () => _showSendAlertsDialog(context),
          ),
          const SizedBox(width: 8),
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
              decoration: BoxDecoration(color: Theme.of(context).primaryColor),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    'Teacher Portal',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    selectedBatchName,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
            ),

            // --- STUDENT MANAGEMENT SECTION ---
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Student Management',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: const Text('Student Details'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const StudentDetailsScreen(),
                  ),
                );
              },
            ),

            // --- ACADEMICS SECTION ---
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Academics',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.library_books_outlined),
              title: const Text('Subjects & IA Marks'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SubjectsScreen(),
                  ),
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
                  MaterialPageRoute(
                    builder: (context) => const FinalExamMarksScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: const Text('SGPA & CGPA Results'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SgpaCgpaScreen(),
                  ),
                );
              },
            ),

            // --- ATTENDANCE SECTION ---
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Attendance',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_view_month_outlined),
              title: const Text('Monthly Attendance %'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AttendancePercentageScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Daily Absentees'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DailyAbsenteeScreen(),
                  ),
                );
              },
            ),

            // --- AUTOMATION SECTION ---
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Automation',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Send Alerts'),
              onTap: () {
                Navigator.pop(context);
                _showSendAlertsDialog(context);
              },
            ),

            const Divider(), // Visual separator
            // --- SETTINGS SECTION ---
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Settings',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horizontal_circle_outlined),
              title: const Text('Change Batch'),
              onTap: () {
                // Navigate back to Batch Selection Screen
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BatchSelectScreen(),
                  ),
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.dashboard_customize_outlined,
                size: 80,
                color: Theme.of(context).primaryColor.withOpacity(0.7),
              ),
              const SizedBox(height: 20),
              Text(
                'Welcome to Teacher Dashboard',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Batch: $selectedBatchName',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        'Quick Actions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _buildQuickActionButton(
                            context: context,
                            icon: Icons.group_add,
                            label: 'Add Student',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const StudentDetailsScreen(),
                                ),
                              );
                            },
                          ),
                          _buildQuickActionButton(
                            context: context,
                            icon: Icons.library_add,
                            label: 'Add Subject',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SubjectsScreen(),
                                ),
                              );
                            },
                          ),
                          _buildQuickActionButton(
                            context: context,
                            icon: Icons.notifications_active,
                            label: 'Send Alerts',
                            onTap: () => _showSendAlertsDialog(context),
                          ),
                          _buildQuickActionButton(
                            context: context,
                            icon: Icons.calendar_today,
                            label: 'Attendance',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const AttendancePercentageScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.0),
                child: Text(
                  'Use the menu (☰) for full navigation.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).primaryColor.withOpacity(0.3),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 30, color: Theme.of(context).primaryColor),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
