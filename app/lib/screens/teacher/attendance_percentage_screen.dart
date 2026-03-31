// /Users/mueez/Desktop/EduTrack-College-Marks/app/lib/screens/teacher/attendance_percentage_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../providers/app_state.dart';

class AttendancePercentageScreen extends StatefulWidget {
  const AttendancePercentageScreen({super.key});

  @override
  State<AttendancePercentageScreen> createState() =>
      _AttendancePercentageScreenState();
}

class _AttendancePercentageScreenState
    extends State<AttendancePercentageScreen> {
  String? _selectedBatchId;
  int _selectedSemester = 1;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  String? _selectedSubjectId;

  List<StudentAttendanceModel> _students = [];
  List<SubjectModel> _subjects = [];
  bool _isLoading = true;
  bool _isSaving = false;

  final Map<String, Map<String, TextEditingController>> _controllers =
      {}; // studentId -> subjectId -> controller
  final Map<String, Map<String, FocusNode>> _focusNodes =
      {}; // studentId -> subjectId -> focusNode

  final List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

  @override
  void initState() {
    super.initState();
    _selectedBatchId =
        Provider.of<AppState>(context, listen: false).selectedBatchId;
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    if (_selectedBatchId == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    _subjects.clear();

    try {
      QuerySnapshot subjectSnapshot = await FirebaseFirestore.instance
          .collection('subjects')
          .where('batchYear', isEqualTo: _selectedBatchId)
          .where('semester', isEqualTo: _selectedSemester)
          .orderBy('subjectCode')
          .get();

      _subjects = subjectSnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return SubjectModel(
          id: doc.id,
          name: data['subjectName'] ?? 'No Name',
          code: data['subjectCode'] ?? 'N/A',
        );
      }).toList();

      if (_subjects.isNotEmpty) {
        _selectedSubjectId = _subjects.first.id;
        await _loadStudents();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print("Error loading subjects: $e");
      setState(() => _isLoading = false);
      _showError('Failed to load subjects: $e');
    }
  }

  Future<void> _loadStudents() async {
    if (_selectedBatchId == null || _selectedSubjectId == null) {
      setState(() => _isLoading = false);
      return;
    }

    _students.clear();
    _controllers.clear();
    _focusNodes.clear();

    try {
      // 1. Get students for the batch
      QuerySnapshot studentSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('batchYear', isEqualTo: _selectedBatchId)
          .orderBy('name')
          .get();

      // 2. For each student, check existing attendance for this subject
      for (var studentDoc in studentSnapshot.docs) {
        final studentData = studentDoc.data() as Map<String, dynamic>;
        final studentId = studentDoc.id;
        final usn = studentData['usn'] ?? 'N/A';
        final name = studentData['name'] ?? 'No Name';

        // Check existing attendance for this subject and month
        final attendanceDocId =
            '${studentId}_${_selectedSubjectId}_S${_selectedSemester}_M${_selectedMonth}_Y${_selectedYear}';
        DocumentSnapshot attendanceSnapshot = await FirebaseFirestore.instance
            .collection('attendanceMonthly')
            .doc(attendanceDocId)
            .get();

        double existingPercentage = 0.0;
        if (attendanceSnapshot.exists) {
          existingPercentage = (attendanceSnapshot.data()
                  as Map<String, dynamic>)['percentage'] ??
              0.0;
        }

        // Create controller and focus node for this student-subject combination
        if (!_controllers.containsKey(studentId)) {
          _controllers[studentId] = {};
        }
        if (!_focusNodes.containsKey(studentId)) {
          _focusNodes[studentId] = {};
        }

        final controller = TextEditingController(
            text: existingPercentage > 0
                ? existingPercentage.toStringAsFixed(1)
                : '');
        final focusNode = FocusNode();

        _controllers[studentId]![_selectedSubjectId!] = controller;
        _focusNodes[studentId]![_selectedSubjectId!] = focusNode;

        _students.add(StudentAttendanceModel(
          studentId: studentId,
          usn: usn,
          name: name,
          percentage: existingPercentage,
        ));
      }

      setState(() => _isLoading = false);
    } catch (e) {
      print("Error loading students: $e");
      setState(() => _isLoading = false);
      _showError('Failed to load students: $e');
    }
  }

  Future<void> _saveAttendance(StudentAttendanceModel student) async {
    if (_selectedSubjectId == null) return;

    final controller = _controllers[student.studentId]?[_selectedSubjectId!];
    if (controller == null) return;

    final percentageText = controller.text.trim();
    if (percentageText.isEmpty) return;

    final percentage = double.tryParse(percentageText);
    if (percentage == null || percentage < 0 || percentage > 100) {
      _showError('Percentage must be between 0 and 100');
      return;
    }

    try {
      final subject = _subjects.firstWhere((s) => s.id == _selectedSubjectId);
      final attendanceDocId =
          '${student.studentId}_${_selectedSubjectId}_S${_selectedSemester}_M${_selectedMonth}_Y${_selectedYear}';

      await FirebaseFirestore.instance
          .collection('attendanceMonthly')
          .doc(attendanceDocId)
          .set({
        'studentId': student.studentId,
        'usn': student.usn,
        'name': student.name,
        'batchYear': _selectedBatchId,
        'semester': _selectedSemester,
        'subjectId': _selectedSubjectId,
        'subjectName': subject.name,
        'subjectCode': subject.code,
        'month': _selectedMonth,
        'year': _selectedYear,
        'percentage': percentage,
        'sent': false,
        'sentAt': null,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Update local state
      setState(() {
        final index =
            _students.indexWhere((s) => s.studentId == student.studentId);
        if (index != -1) {
          _students[index] = _students[index].copyWith(percentage: percentage);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Saved ${student.name} attendance for ${subject.code}'),
            duration: const Duration(seconds: 1)),
      );
    } catch (e) {
      print("Error saving attendance: $e");
      _showError('Failed to save: $e');
    }
  }

  Future<void> _saveAllAttendance() async {
    if (_selectedSubjectId == null) {
      _showError('Please select a subject');
      return;
    }

    setState(() => _isSaving = true);

    int savedCount = 0;
    int errorCount = 0;
    final subject = _subjects.firstWhere((s) => s.id == _selectedSubjectId);

    for (var student in _students) {
      final controller = _controllers[student.studentId]?[_selectedSubjectId!];
      if (controller == null) continue;

      final percentageText = controller.text.trim();
      if (percentageText.isEmpty) continue;

      final percentage = double.tryParse(percentageText);
      if (percentage == null || percentage < 0 || percentage > 100) {
        errorCount++;
        continue;
      }

      try {
        final attendanceDocId =
            '${student.studentId}_${_selectedSubjectId}_S${_selectedSemester}_M${_selectedMonth}_Y${_selectedYear}';

        await FirebaseFirestore.instance
            .collection('attendanceMonthly')
            .doc(attendanceDocId)
            .set({
          'studentId': student.studentId,
          'usn': student.usn,
          'name': student.name,
          'batchYear': _selectedBatchId,
          'semester': _selectedSemester,
          'subjectId': _selectedSubjectId,
          'subjectName': subject.name,
          'subjectCode': subject.code,
          'month': _selectedMonth,
          'year': _selectedYear,
          'percentage': percentage,
          'sent': false,
          'sentAt': null,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        savedCount++;
      } catch (e) {
        errorCount++;
      }
    }

    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Saved $savedCount students for ${subject.code}. Failed: $errorCount'),
        backgroundColor: savedCount > 0 ? Colors.green : Colors.red,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Widget _buildPercentageInput(StudentAttendanceModel student) {
    final controller = _controllers[student.studentId]?[_selectedSubjectId!];
    final focusNode = _focusNodes[student.studentId]?[_selectedSubjectId!];

    if (controller == null || focusNode == null) {
      return const SizedBox(width: 80, child: Text('-'));
    }

    return SizedBox(
      width: 80,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          hintText: '%',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          border: OutlineInputBorder(),
          suffixText: '%',
          suffixStyle: TextStyle(fontSize: 12),
        ),
        onFieldSubmitted: (_) {
          _saveAttendance(student);
          focusNode.unfocus();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final batchName =
        Provider.of<AppState>(context).selectedBatchName ?? 'Attendance';

    return Scaffold(
      appBar: AppBar(
        title: Text('Monthly Attendance - $batchName'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // --- FILTER CONTROLS ---
          Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _selectedSemester,
                          decoration: const InputDecoration(
                            labelText: 'Semester',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: List.generate(8, (index) {
                            int semester = index + 1;
                            return DropdownMenuItem(
                              value: semester,
                              child: Text('Semester $semester'),
                            );
                          }),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedSemester = value);
                              _loadSubjects();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: _selectedSubjectId,
                          decoration: const InputDecoration(
                            labelText: 'Subject',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: _subjects.map((subject) {
                            return DropdownMenuItem(
                              value: subject.id,
                              child: Text('${subject.code}'),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() => _selectedSubjectId = value);
                            if (value != null) {
                              _loadStudents();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _selectedMonth,
                          decoration: const InputDecoration(
                            labelText: 'Month',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: List.generate(12, (index) {
                            int month = index + 1;
                            return DropdownMenuItem(
                              value: month,
                              child: Text(_months[index]),
                            );
                          }),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedMonth = value);
                              _loadStudents();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _selectedYear,
                          decoration: const InputDecoration(
                            labelText: 'Year',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [2023, 2024, 2025, 2026].map((year) {
                            return DropdownMenuItem(
                              value: year,
                              child: Text(year.toString()),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedYear = value);
                              _loadStudents();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save, size: 18),
                    label: Text(
                        _isSaving ? 'Saving...' : 'Save All for This Subject'),
                    onPressed: _isSaving || _students.isEmpty
                        ? null
                        : _saveAllAttendance,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 40),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // --- STUDENTS LIST ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _students.isEmpty
                    ? const Center(
                        child:
                            Text('No students found for this batch/subject.'),
                      )
                    : SingleChildScrollView(
                        child: DataTable(
                          columnSpacing: 12,
                          headingRowHeight: 40,
                          dataRowMinHeight: 48,
                          columns: const [
                            DataColumn(
                                label: Text('Name',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold))),
                            DataColumn(
                                label: Text('USN',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold))),
                            DataColumn(
                                label: Text('Attendance %',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                numeric: true),
                            DataColumn(
                                label: Text('Save',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold))),
                          ],
                          rows: _students.map((student) {
                            return DataRow(cells: [
                              DataCell(
                                SizedBox(
                                  width: 150,
                                  child: Text(
                                    student.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(Text(student.usn)),
                              DataCell(_buildPercentageInput(student)),
                              DataCell(
                                IconButton(
                                  icon: const Icon(Icons.save_alt, size: 20),
                                  tooltip: 'Save ${student.name}',
                                  onPressed: () => _saveAttendance(student),
                                ),
                              ),
                            ]);
                          }).toList(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class StudentAttendanceModel {
  final String studentId;
  final String usn;
  final String name;
  final double percentage;

  StudentAttendanceModel({
    required this.studentId,
    required this.usn,
    required this.name,
    required this.percentage,
  });

  StudentAttendanceModel copyWith({
    double? percentage,
  }) {
    return StudentAttendanceModel(
      studentId: studentId,
      usn: usn,
      name: name,
      percentage: percentage ?? this.percentage,
    );
  }
}

class SubjectModel {
  final String id;
  final String name;
  final String code;

  SubjectModel({
    required this.id,
    required this.name,
    required this.code,
  });
}
