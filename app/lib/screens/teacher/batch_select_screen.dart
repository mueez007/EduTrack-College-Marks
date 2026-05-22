import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../../providers/app_state.dart';
import '../../services/firestore_helper.dart';
import 'teacher_home_screen.dart';
import '../login_screen.dart';
import '../admin/admin_department_select_screen.dart';

class BatchSelectScreen extends StatefulWidget {
  const BatchSelectScreen({super.key});

  @override
  State<BatchSelectScreen> createState() => _BatchSelectScreenState();
}

class _BatchSelectScreenState extends State<BatchSelectScreen> {
  Stream<QuerySnapshot>? _batchesStream;
  String? _selectedBatchId;
  String? _selectedBatchName;

  @override
  void initState() {
    super.initState();
    final deptId = Provider.of<AppState>(context, listen: false).departmentId;
    if (deptId != null) {
      _batchesStream = FirestoreHelper.deptCollection(deptId, 'batches')
          .orderBy('yearName', descending: true)
          .snapshots();
    }
  }

  void _selectBatch(String batchId, String batchName) {
    if (!mounted) return;
    setState(() {
      _selectedBatchId = batchId;
      _selectedBatchName = batchName;
    });
    print("Selected Batch ID: $batchId, Name: $batchName");
    Provider.of<AppState>(context, listen: false).setSelectedBatch(batchId, batchName);
    Navigator.pushReplacement(context,
      MaterialPageRoute(builder: (context) => const TeacherHomeScreen()));
  }

  void _addNewBatch() {
    final yearController = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Add New Batch Year"),
          content: TextField(
            controller: yearController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: "Enter Year (e.g., 2026)"),
          ),
          actions: [
            TextButton(child: const Text("Cancel"), onPressed: () => Navigator.of(context).pop()),
            ElevatedButton(
              child: const Text("Add"),
              onPressed: () async {
                final String year = yearController.text.trim();
                if (year.isNotEmpty && year.length == 4 && int.tryParse(year) != null) {
                  String batchId = year;
                  String batchName = "$year Batch";
                  final deptId = Provider.of<AppState>(context, listen: false).departmentId;
                  if (deptId == null) return;
                  try {
                    final doc = await FirestoreHelper.deptDoc(deptId, 'batches', batchId).get();
                    if (doc.exists) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Batch $year already exists.'), backgroundColor: Colors.orange));
                      }
                    } else {
                      await FirestoreHelper.deptDoc(deptId, 'batches', batchId).set({
                        'yearName': batchName, 'createdAt': FieldValue.serverTimestamp()});
                      if (mounted) Navigator.of(context).pop();
                    }
                  } catch (e) {
                    print("Error adding batch: $e");
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to add batch. Error: $e'), backgroundColor: Colors.red));
                    }
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid 4-digit year.'), backgroundColor: Colors.red));
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Provider.of<AppState>(context, listen: false).clearAll();
        Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (Route<dynamic> route) => false);
      }
    } catch (e) {
      print("Error logging out: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logout failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _changeDepartment() {
    Provider.of<AppState>(context, listen: false).clearSelectedBatch();
    Navigator.pushReplacement(context,
      MaterialPageRoute(builder: (context) => const AdminDepartmentSelectScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final deptName = appState.departmentName ?? 'Unknown';
    final isAdmin = appState.isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: Text(isAdmin ? 'Select Batch' : 'Select Batch'),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Change Department',
              onPressed: _changeDepartment,
            ),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Logout', onPressed: _logout),
        ],
      ),
      body: Column(
        children: [
          // Department header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.05),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
                  ),
                  child: ClipOval(
                    child: Image.asset('assets/logos/college_logo.png', height: 48, width: 48, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 10),
                Text(deptName,
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.primaryBlue)),
                const SizedBox(height: 4),
                Text('Select your batch year',
                  style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMuted)),
              ],
            ),
          ),
          const Divider(height: 1),

          // Batches list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _batchesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text('No batches found', style: GoogleFonts.poppins(color: AppColors.textMuted)),
                        const SizedBox(height: 4),
                        Text('Tap + to add a batch year', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
                      ],
                    ),
                  );
                }

                final batches = snapshot.data!.docs;
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: batches.length,
                  itemBuilder: (context, index) {
                    final batchDoc = batches[index];
                    final batchId = batchDoc.id;
                    final batchName = batchDoc['yearName'];
                    final isSelected = _selectedBatchId == batchId;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _selectBatch(batchId, batchName),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primaryBlue : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected ? AppColors.primaryBlue : AppColors.cardBorder,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primaryBlue.withValues(alpha: isSelected ? 0.15 : 0.03),
                                  blurRadius: 8, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.white.withValues(alpha: 0.2)
                                        : AppColors.primaryBlue.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.calendar_month,
                                    color: isSelected ? Colors.white : AppColors.primaryBlue, size: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(batchName,
                                        style: GoogleFonts.poppins(
                                          fontSize: 16, fontWeight: FontWeight.w600,
                                          color: isSelected ? Colors.white : AppColors.textPrimary)),
                                      Text('Batch ID: $batchId',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: isSelected ? Colors.white70 : AppColors.textMuted)),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios, size: 16,
                                  color: isSelected ? Colors.white70 : AppColors.textMuted),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Add batch button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addNewBatch,
                icon: const Icon(Icons.add_circle_outline),
                label: Text('Add New Batch Year', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}