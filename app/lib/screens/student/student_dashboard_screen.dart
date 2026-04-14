import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../login_screen.dart';
import 'student_subject_view_screen.dart';
import 'student_attendance_screen.dart';

class StudentDashboardScreen extends StatefulWidget {
  final String? usn; // Add this parameter

  const StudentDashboardScreen({super.key, this.usn});

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;
  String? _studentId; // This is the UID
  String? _selectedBatchId;
  String? _studentUsn;
  String? _studentName;
  int _selectedSemester = 1;

  Stream<QuerySnapshot>? _subjectsStream;
  Stream<DocumentSnapshot>? _resultStream;

  @override
  void initState() {
    super.initState();

    // Priority 1: Use USN from parameter (direct login)
    // Priority 2: Use Firebase Auth user
    if (widget.usn != null) {
      _studentUsn = widget.usn;
      _loadStudentByUsn();
    } else {
      _studentId = _user?.uid;
      _loadStudentDetails();
    }
  }

  // Fetch student by USN directly (for password-less login)
  Future<void> _loadStudentByUsn() async {
    if (_studentUsn == null) return;

    try {
      // Query Firestore for student by USN
      QuerySnapshot studentQuery = await FirebaseFirestore.instance
          .collection('students')
          .where('usn', isEqualTo: _studentUsn)
          .limit(1)
          .get();

      if (studentQuery.docs.isNotEmpty) {
        final studentDoc = studentQuery.docs.first;
        final studentData = studentDoc.data() as Map<String, dynamic>;

        setState(() {
          _selectedBatchId = studentData['batchYear'];
          _studentName = studentData['name'];
          _studentId = studentDoc.id; // Store document ID
        });

        // Also create/update user record for Firebase Auth compatibility
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .set({
            'role': 'student',
            'usn': _studentUsn,
            'name': _studentName,
            'batchYear': _selectedBatchId,
            'studentId': studentDoc.id,
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        _loadSemesterData();
      } else {
        print("Student with USN $_studentUsn not found");
      }
    } catch (e) {
      print("Error loading student by USN: $e");
    }
  }

  // Fetch student's initial details (USN, Batch) from Firestore (original method)
  Future<void> _loadStudentDetails() async {
    if (_studentId == null) return;

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_studentId!)
          .get();
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        setState(() {
          _selectedBatchId = data['batchYear'];
          _studentUsn = data['usn'];
          _studentName = data['name'];
        });
        _loadSemesterData(); // Load data for the initial semester (Sem 1)
      }
    } catch (e) {
      print("Error loading student details: $e");
    }
  }

  // Load subjects and results for the current semester
  void _loadSemesterData() {
    if (_selectedBatchId == null || _studentUsn == null) return;

    // Build the students collection document id which matches how teacher writes data
    final String studentDocId = '${_selectedBatchId}_$_studentUsn';

    // 1. Subjects Stream (filtered by student's batch and selected semester)
    setState(() {
      _subjectsStream = FirebaseFirestore.instance
          .collection('subjects')
          .where('batchYear', isEqualTo: _selectedBatchId)
          .where('semester', isEqualTo: _selectedSemester)
          .orderBy('subjectCode')
          .snapshots();

      // 2. Result Stream (for the main rank card)
      final resultDocId = '${studentDocId}_S$_selectedSemester';
      _resultStream = FirebaseFirestore.instance
          .collection('semesterResults')
          .doc(resultDocId)
          .snapshots();
    });
  }

  // Handle Logout
  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  // --- Rank Card UI Builder (Debit Card Style) ---
  Widget _buildRankCard(
      {required String sgpa,
      required String cgpa,
      required String rank,
      required String usn}) {
    final Color primaryColor = Theme.of(context).primaryColor;
    final Color secondaryColor = primaryColor.withOpacity(0.7);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            colors: [primaryColor, secondaryColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('SEMESTER $_selectedSemester',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 16)),
                const Icon(Icons.school, color: Colors.white70, size: 28),
              ],
            ),
            const SizedBox(height: 20),

            // CGPA & SGPA
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CGPA',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    Text(cgpa,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('SGPA',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    Text(sgpa,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // RANK and USN
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('CLASS RANK: $rank',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                Text(usn,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 16)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedBatchId == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator.adaptive(),
              const SizedBox(height: 20),
              Text(
                widget.usn != null
                    ? 'Loading data for USN: ${widget.usn}'
                    : 'Loading student data...',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    // Construct the students collection document id (used across teacher-written docs)
    final String studentDocId = '${_selectedBatchId}_$_studentUsn';

    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome, ${_studentName ?? 'Student'}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Semester Selection (ChoiceChip Row) ---
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SizedBox(
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 8,
                itemBuilder: (context, index) {
                  int semester = index + 1;
                  bool isSelected = semester == _selectedSemester;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: ChoiceChip(
                      label: Text('Sem $semester'),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected && mounted) {
                          setState(() {
                            _selectedSemester = semester;
                          });
                          _loadSemesterData(); // Reload data for the new semester
                        }
                      },
                      selectedColor: Theme.of(context).primaryColor,
                      labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : Theme.of(context).textTheme.bodyLarge?.color),
                      backgroundColor:
                          Theme.of(context).chipTheme.backgroundColor ??
                              Colors.grey[200],
                      shape: StadiumBorder(
                          side: BorderSide(
                              color: isSelected
                                  ? Theme.of(context).primaryColor
                                  : Colors.grey)),
                    ),
                  );
                },
              ),
            ),
          ),
          const Divider(),

          // --- 1. SGPA/CGPA Rank Card (Debit Card Style) ---
          StreamBuilder<DocumentSnapshot>(
            stream: _resultStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator.adaptive()));
              }

              String sgpa = 'N/A', cgpa = 'N/A', rank = 'N/A';

              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>;
                sgpa = (data['sgpa'] as num?)?.toStringAsFixed(2) ?? 'N/A';
                cgpa = (data['cgpa'] as num?)?.toStringAsFixed(2) ?? 'N/A';
                rank = data['rank']?.toString() ??
                    'N/A'; // Assuming rank is calculated and saved by teacher logic
              }

              return _buildRankCard(
                  sgpa: sgpa, cgpa: cgpa, rank: rank, usn: _studentUsn ?? '');
            },
          ),

          const SizedBox(height: 8),

          // --- Attendance Button ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => StudentAttendanceScreen(
                        studentId: studentDocId,
                        batchId: _selectedBatchId,
                        semester: _selectedSemester,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.calendar_month, color: Colors.blue, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'View Attendance',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Subject-wise attendance summary',
                              style: TextStyle(color: Colors.grey[600], fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text('Subjects for Semester $_selectedSemester',
                style: Theme.of(context).textTheme.titleLarge),
          ),
          const Divider(),

          // --- 2. Subject List ---
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _subjectsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator.adaptive());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                      child: Text('No subjects recorded for this semester.'));
                }

                final subjects = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: subjects.length,
                  itemBuilder: (context, index) {
                    final subjectDoc = subjects[index];
                    final subjectData =
                        subjectDoc.data() as Map<String, dynamic>;
                    final name = subjectData['subjectName'] ?? 'No Name';
                    final code = subjectData['subjectCode'] ?? 'No Code';

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      elevation: 1,
                      child: ListTile(
                        leading: const Icon(Icons.menu_book),
                        title: Text('$code - $name'),
                        subtitle:
                            Text('Credits: ${subjectData['credits'] ?? '?'}'),
                        trailing: const Icon(Icons.arrow_forward_ios),
                        onTap: () {
                          // Navigate to Subject View, passing student and subject info
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => StudentSubjectViewScreen(
                                // pass students collection doc id (batch_usn) so it matches teacher-written docs
                                studentId: studentDocId,
                                subjectId: subjectDoc.id,
                                subjectName: name,
                                subjectData: subjectData,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
