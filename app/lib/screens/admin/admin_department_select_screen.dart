import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/department_config.dart';
import '../../config/app_theme.dart';
import '../../providers/app_state.dart';
import '../login_screen.dart';
import '../teacher/batch_select_screen.dart';
import 'manage_credentials_screen.dart';

class AdminDepartmentSelectScreen extends StatelessWidget {
  const AdminDepartmentSelectScreen({super.key});

  void _selectDepartment(BuildContext context, Department dept) {
    Provider.of<AppState>(context, listen: false)
        .setDepartment(dept.id, dept.name);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const BatchSelectScreen()),
    );
  }

  void _logout(BuildContext context) async {
    try { await FirebaseAuth.instance.signOut(); } catch (_) {}
    if (!context.mounted) return;
    Provider.of<AppState>(context, listen: false).clearAll();
    Navigator.pushAndRemoveUntil(context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (Route<dynamic> route) => false);
  }

  void _openCredentialManager(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => const ManageCredentialsScreen()));
  }

  // Color assignments for department cards
  static final List<Color> _cardColors = [
    const Color(0xFF1A3C7A), const Color(0xFFF08C00), const Color(0xFF00A651),
    const Color(0xFF8B5CF6), const Color(0xFFEC4899), const Color(0xFF06B6D4),
    const Color(0xFFEF4444), const Color(0xFF14B8A6), const Color(0xFF6366F1),
    const Color(0xFFF97316), const Color(0xFF84CC16),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Collapsing App Bar with college branding
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: AppColors.primaryBlue,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.darkNavy, AppColors.primaryBlue],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle, color: Colors.white,
                            ),
                            child: ClipOval(
                              child: Image.asset('assets/logos/college_logo.png',
                                height: 48, width: 48, fit: BoxFit.cover),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Admin Portal',
                                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
                              Text('EduTrack ERP • MIT Mysore',
                                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.accentOrange)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('Select a department to manage',
                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.manage_accounts),
                tooltip: 'Manage Teacher Credentials',
                onPressed: () => _openCredentialManager(context),
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Logout',
                onPressed: () => _logout(context),
              ),
            ],
          ),

          // Department Grid
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final dept = DepartmentConfig.departments[index];
                  final color = _cardColors[index % _cardColors.length];
                  return _buildDepartmentCard(context, dept, color);
                },
                childCount: DepartmentConfig.departments.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentCard(BuildContext context, Department dept, Color color) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectDepartment(context, dept),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(dept.id,
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: Text(dept.name,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
