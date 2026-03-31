import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../providers/app_state.dart';

class DailyAbsenteeScreen extends StatefulWidget {
  const DailyAbsenteeScreen({super.key});

  @override
  State<DailyAbsenteeScreen> createState() => _DailyAbsenteeScreenState();
}

class _DailyAbsenteeScreenState extends State<DailyAbsenteeScreen> {
  String? _selectedBatchId;
  int _selectedSemester = 1;
  DateTime _selectedDate = DateTime.now();
  String? _selectedSubjectId;

  List<StudentModel> _students = [];
  List<SubjectModel> _subjects = [];
  Set<String> _absentStudentIds = {};

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedBatchId =
        Provider.of<AppState>(context, listen: false).selectedBatchId;
    _loadData();
  }

  Future<void> _loadData() async {
    if (_selectedBatchId == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    _students.clear();
    _subjects.clear();
    _absentStudentIds.clear();

    try {
      // 1. Load students for the batch
      QuerySnapshot studentSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('batchYear', isEqualTo: _selectedBatchId)
          .orderBy('name')
          .get();

      _students = studentSnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return StudentModel(
          id: doc.id,
          name: data['name'] ?? 'No Name',
          usn: data['usn'] ?? 'N/A',
        );
      }).toList();

      // 2. Load subjects for the selected semester
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
      }

      // 3. Load existing absentees for today
      if (_selectedSubjectId != null) {
        await _loadExistingAbsentees();
      }

      setState(() => _isLoading = false);
    } catch (e) {
      print("Error loading data: $e");
      setState(() => _isLoading = false);
      _showError('Failed to load data: $e');
    }
  }

  Future<void> _loadExistingAbsentees() async {
    if (_selectedSubjectId == null || _selectedBatchId == null) return;

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final absenteeDocId = '${_selectedBatchId}_${_selectedSubjectId}_$dateStr';

    try {
      DocumentSnapshot absenteeDoc = await FirebaseFirestore.instance
          .collection('absentees')
          .doc(absenteeDocId)
          .get();

      if (absenteeDoc.exists) {
        final data = absenteeDoc.data() as Map<String, dynamic>;
        final List<dynamic> absentList = data['absentStudents'] ?? [];
        setState(() {
          _absentStudentIds = Set<String>.from(absentList.cast<String>());
        });
      }
    } catch (e) {
      print("Error loading absentees: $e");
    }
  }

  Future<void> _saveAbsentees() async {
    if (_selectedSubjectId == null || _selectedBatchId == null) {
      _showError('Please select a subject');
      return;
    }

    if (_absentStudentIds.isEmpty) {
      _showError('No absent students selected');
      return;
    }

    setState(() => _isSaving = true);

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final absenteeDocId = '${_selectedBatchId}_${_selectedSubjectId}_$dateStr';
    final subject = _subjects.firstWhere((s) => s.id == _selectedSubjectId);

    try {
      // Prepare absent student details
      List<Map<String, dynamic>> absentDetails = [];
      for (var studentId in _absentStudentIds) {
        final student = _students.firstWhere((s) => s.id == studentId);
        absentDetails.add({
          'studentId': studentId,
          'usn': student.usn,
          'name': student.name,
        });
      }

      await FirebaseFirestore.instance
          .collection('absentees')
          .doc(absenteeDocId)
          .set({
        'batchYear': _selectedBatchId,
        'semester': _selectedSemester,
        'subjectId': _selectedSubjectId,
        'subjectName': subject.name,
        'subjectCode': subject.code,
        'date': dateStr,
        'dateTimestamp': Timestamp.fromDate(_selectedDate),
        'absentStudents': _absentStudentIds.toList(),
        'absentDetails': absentDetails,
        'absentCount': _absentStudentIds.length,
        'sent': false, // For automation
        'sentAt': null,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() => _isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved ${_absentStudentIds.length} absent student(s)'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() => _isSaving = false);
      _showError('Failed to save: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _absentStudentIds.clear();
      });
      await _loadExistingAbsentees();
    }
  }

  @override
  Widget build(BuildContext context) {
    final batchName =
        Provider.of<AppState>(context).selectedBatchName ?? 'Absentees';

    return Scaffold(
      appBar: AppBar(
        title: Text('Daily Absentees - $batchName'),
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
                              _loadData();
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
                              child: Text('${subject.code} - ${subject.name}'),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() => _selectedSubjectId = value);
                            if (value != null) {
                              _loadExistingAbsentees();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(
                              DateFormat('dd/MM/yyyy').format(_selectedDate)),
                          onPressed: () => _selectDate(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save, size: 18),
                          label:
                              Text(_isSaving ? 'Saving...' : 'Save Absentees'),
                          onPressed: _isSaving || _absentStudentIds.isEmpty
                              ? null
                              : _saveAbsentees,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_absentStudentIds.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        '${_absentStudentIds.length} student(s) marked absent',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
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
                        child: Text('No students found for this batch.'),
                      )
                    : ListView.builder(
                        itemCount: _students.length,
                        itemBuilder: (context, index) {
                          final student = _students[index];
                          final isAbsent =
                              _absentStudentIds.contains(student.id);

                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            color: isAbsent ? Colors.red.shade50 : null,
                            child: ListTile(
                              leading: Checkbox(
                                value: isAbsent,
                                onChanged: (value) {
                                  setState(() {
                                    if (value == true) {
                                      _absentStudentIds.add(student.id);
                                    } else {
                                      _absentStudentIds.remove(student.id);
                                    }
                                  });
                                },
                              ),
                              title: Text(
                                student.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: isAbsent ? Colors.red : null,
                                ),
                              ),
                              subtitle: Text('USN: ${student.usn}'),
                              trailing: isAbsent
                                  ? const Icon(Icons.person_off,
                                      color: Colors.red)
                                  : const Icon(Icons.person,
                                      color: Colors.green),
                              onTap: () {
                                setState(() {
                                  if (_absentStudentIds.contains(student.id)) {
                                    _absentStudentIds.remove(student.id);
                                  } else {
                                    _absentStudentIds.add(student.id);
                                  }
                                });
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class StudentModel {
  final String id;
  final String name;
  final String usn;

  StudentModel({
    required this.id,
    required this.name,
    required this.usn,
  });
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
