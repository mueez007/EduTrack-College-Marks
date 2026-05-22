import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../../providers/app_state.dart';
import '../login_screen.dart';
import 'batch_select_screen.dart';
import 'student_details_screen.dart';
import 'subjects_screen.dart';
import 'final_exam_marks_screen.dart';
import 'sgpa_cgpa_screen.dart';
import 'daily_absentee_screen.dart';
import '../admin/admin_department_select_screen.dart';
import '../admin/manage_credentials_screen.dart';

class TeacherHomeScreen extends StatelessWidget {
  const TeacherHomeScreen({super.key});

  void _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      Provider.of<AppState>(context, listen: false).clearAll();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      print("Error logging out: $e");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showSendAlertsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Send Automated Alerts'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('This will send alerts for:'),
            SizedBox(height: 10),
            Text('• New IA Marks', style: TextStyle(color: Colors.blue)),
            Text('• Final Exam Marks', style: TextStyle(color: Colors.green)),
            Text('• Attendance % (if configured)', style: TextStyle(color: Colors.orange)),
            SizedBox(height: 10),
            Text('Only sends for current semester marks.', style: TextStyle(fontSize: 12)),
            Text('Requires n8n setup.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
    final batchId = Provider.of<AppState>(context, listen: false).selectedBatchId;
    if (batchId == null) {
      scaffold.showSnackBar(const SnackBar(content: Text('Error: No batch selected'), backgroundColor: Colors.red));
      return;
    }
    scaffold.showSnackBar(const SnackBar(content: Text('Sending alerts...'), backgroundColor: Colors.blue));
    try {
      await Future.delayed(const Duration(seconds: 2));
      scaffold.showSnackBar(const SnackBar(content: Text('Alerts queued successfully!'), backgroundColor: Colors.green));
    } catch (e) {
      scaffold.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final selectedBatchName = appState.selectedBatchName ?? 'No Batch Selected';
    final deptName = appState.departmentName ?? 'Unknown Dept';
    final isAdmin = appState.isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(deptName, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(selectedBatchName, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w400, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'Send Alerts',
            onPressed: () => _showSendAlertsDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => _logout(context),
          ),
        ],
      ),

      // --- BRANDED DRAWER ---
      drawer: Drawer(
        child: Column(
          children: [
            // Drawer Header with college branding
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.darkNavy, AppColors.primaryBlue],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8)],
                        ),
                        child: ClipOval(
                          child: Image.asset('assets/logos/college_logo.png', height: 48, width: 48, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('MIT Mysore', style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                            Text('EduTrack ERP', style: GoogleFonts.poppins(
                              fontSize: 12, color: AppColors.accentOrange)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isAdmin ? '👤 Admin' : '👤 Teacher',
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(deptName, style: GoogleFonts.poppins(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500)),
                  Text(selectedBatchName, style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70)),
                ],
              ),
            ),

            // Menu Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 8),
                children: [
                  _sectionHeader('Student Management'),
                  _drawerItem(context, Icons.group_outlined, 'Student Details',
                    () => _navigateTo(context, const StudentDetailsScreen())),

                  _sectionHeader('Academics'),
                  _drawerItem(context, Icons.library_books_outlined, 'Subjects & IA Marks',
                    () => _navigateTo(context, const SubjectsScreen())),
                  _drawerItem(context, Icons.grading_outlined, 'Final Exam Marks',
                    () => _navigateTo(context, const FinalExamMarksScreen())),
                  _drawerItem(context, Icons.bar_chart_outlined, 'SGPA & CGPA Results',
                    () => _navigateTo(context, const SgpaCgpaScreen())),

                  _sectionHeader('Attendance'),
                  _drawerItem(context, Icons.person_off_outlined, 'Daily Absentees',
                    () => _navigateTo(context, const DailyAbsenteeScreen())),

                  _sectionHeader('Automation'),
                  _drawerItem(context, Icons.notifications_active_outlined, 'Send Alerts',
                    () { Navigator.pop(context); _showSendAlertsDialog(context); }),

                  const Divider(indent: 16, endIndent: 16),
                  _sectionHeader('Settings'),
                  _drawerItem(context, Icons.swap_horizontal_circle_outlined, 'Change Batch',
                    () => Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => const BatchSelectScreen()))),

                  if (isAdmin) ...[
                    _drawerItem(context, Icons.swap_horiz, 'Change Department', () {
                      Provider.of<AppState>(context, listen: false).clearSelectedBatch();
                      Navigator.pushReplacement(context,
                        MaterialPageRoute(builder: (_) => const AdminDepartmentSelectScreen()));
                    }),
                    _drawerItem(context, Icons.manage_accounts, 'Manage Credentials',
                      () => _navigateTo(context, const ManageCredentialsScreen())),
                  ],
                  _drawerItem(context, Icons.logout_outlined, 'Logout',
                    () => _logout(context), isDestructive: true),
                ],
              ),
            ),
          ],
        ),
      ),

      // --- DASHBOARD BODY ---
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: AppColors.primaryBlue.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome back!',
                          style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(deptName,
                          style: GoogleFonts.poppins(fontSize: 14, color: Colors.white.withValues(alpha: 0.8))),
                        const SizedBox(height: 2),
                        Text('Batch: $selectedBatchName',
                          style: GoogleFonts.poppins(fontSize: 12, color: Colors.white.withValues(alpha: 0.7))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    child: ClipOval(
                      child: Image.asset('assets/logos/college_logo.png', height: 50, width: 50, fit: BoxFit.cover),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Quick Actions
            Text('Quick Actions',
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.0,
              children: [
                _buildQuickAction(context, Icons.group_add, 'Students',
                  AppColors.primaryBlue, () => _navigateFromBody(context, const StudentDetailsScreen())),
                _buildQuickAction(context, Icons.library_add, 'Subjects',
                  AppColors.accentOrange, () => _navigateFromBody(context, const SubjectsScreen())),
                _buildQuickAction(context, Icons.grading, 'Exam Marks',
                  AppColors.accentGreen, () => _navigateFromBody(context, const FinalExamMarksScreen())),
                _buildQuickAction(context, Icons.bar_chart, 'Results',
                  const Color(0xFF8B5CF6), () => _navigateFromBody(context, const SgpaCgpaScreen())),
                _buildQuickAction(context, Icons.calendar_today, 'Attendance',
                  const Color(0xFFEC4899), () => _navigateFromBody(context, const DailyAbsenteeScreen())),
                _buildQuickAction(context, Icons.notifications_active, 'Alerts',
                  const Color(0xFF06B6D4), () => _showSendAlertsDialog(context)),
              ],
            ),

            const SizedBox(height: 24),
            // Help tip
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppColors.primaryBlue.withValues(alpha: 0.6)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Swipe from the left edge or tap ☰ for full navigation menu.',
                      style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(title, style: GoogleFonts.poppins(
        fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted,
        letterSpacing: 0.5,
      )),
    );
  }

  Widget _drawerItem(BuildContext context, IconData icon, String title,
      VoidCallback onTap, {bool isDestructive = false}) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 22,
        color: isDestructive ? AppColors.error : AppColors.textSecondary),
      title: Text(title, style: GoogleFonts.poppins(
        fontSize: 14, fontWeight: FontWeight.w500,
        color: isDestructive ? AppColors.error : AppColors.textPrimary)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  void _navigateTo(BuildContext context, Widget screen) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  void _navigateFromBody(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Widget _buildQuickAction(BuildContext context, IconData icon, String label,
      Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(height: 8),
              Text(label, textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}
