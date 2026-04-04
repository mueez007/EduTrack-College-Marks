import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../providers/app_state.dart';

class StudentDetailsScreen extends StatefulWidget {
  const StudentDetailsScreen({super.key});

  @override
  State<StudentDetailsScreen> createState() => _StudentDetailsScreenState();
}

class _StudentDetailsScreenState extends State<StudentDetailsScreen> {
  Stream<QuerySnapshot>? _studentsStream;
  String? _selectedBatchId;

  @override
  void initState() {
    super.initState();
    _selectedBatchId = Provider.of<AppState>(
      context,
      listen: false,
    ).selectedBatchId;

    if (_selectedBatchId != null) {
      _studentsStream = FirebaseFirestore.instance
          .collection('students')
          .where('batchYear', isEqualTo: _selectedBatchId)
          .orderBy('name')
          .snapshots();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Error: Batch ID is missing. Please select a batch first.',
              ),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.of(context).pop();
        }
      });
    }
  }

  // --- Add New Student Dialog (NO PASSWORD VERSION) ---
  void _showAddStudentDialog() {
    final nameController = TextEditingController();
    final usnController = TextEditingController();
    final numberController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (stfContext, setDialogState) {
            Future<void> handleAction() async {
              if (formKey.currentState!.validate()) {
                setDialogState(() => isSaving = true);

                await _handleAddStudentAction(
                  dialogContext,
                  usnController,
                  nameController,
                  numberController,
                  setDialogState,
                  () => isSaving = false,
                );
              }
            }

            return AlertDialog(
              title: const Text("Add New Student"),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: "Student Name *",
                        ),
                        validator: (value) =>
                            value == null || value.isEmpty ? 'Required' : null,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: usnController,
                        decoration: const InputDecoration(
                          labelText: "USN (Student ID) *",
                        ),
                        validator: (value) =>
                            value == null || value.isEmpty ? 'Required' : null,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: numberController,
                        decoration: const InputDecoration(
                          labelText: "Phone Number (Optional)",
                        ),
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                      ),
                      const SizedBox(height: 8),
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          "Note: Student can login using USN only, no password required.",
                          style: TextStyle(color: Colors.green, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: isSaving ? null : handleAction,
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text("Add Student"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- Helper function for Add Student action (NO PASSWORD) ---
  Future<void> _handleAddStudentAction(
    BuildContext dialogContext,
    TextEditingController usnController,
    TextEditingController nameController,
    TextEditingController numberController,
    StateSetter setDialogState,
    VoidCallback resetIsSaving,
  ) async {
    final String name = nameController.text.trim();
    final String usn = usnController.text.trim().toUpperCase();
    final String number = numberController.text.trim();
    final currentBatchId = Provider.of<AppState>(
      context,
      listen: false,
    ).selectedBatchId;

    if (currentBatchId == null) {
      resetIsSaving();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: No batch selected. Cannot add student.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // 1. CREATE STUDENT DOCUMENT in Firestore
      DocumentReference studentRef = FirebaseFirestore.instance
          .collection('students')
          .doc('${currentBatchId}_$usn');

      // 2. Check for Duplicates
      DocumentSnapshot docSnapshot = await studentRef.get();
      if (docSnapshot.exists) {
        throw Exception("USN $usn already registered in this batch.");
      }

      // 3. Perform Simple Write (NO PASSWORD FIELD)
      await studentRef.set({
        'name': name,
        'usn': usn,
        'number': number.isEmpty ? null : number,
        'batchYear': currentBatchId,
        // NO PASSWORD FIELD - Students login with USN only
        'currentSemester': 1, // Default to semester 1
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Success
      resetIsSaving();
      if (!dialogContext.mounted) return;
      Navigator.of(dialogContext).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Student $usn added successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      resetIsSaving();
      print("Error adding student: $e");
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(
          content: Text('Failed to add student. Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // --- Bulk Add Students Dialog ---
  void _showBulkAddDialog() {
    final textController = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Bulk Add Students'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter one student per line in format:\nUSN, Name, Phone (optional)',
                ),
                const Text(
                  'Example:\n4MH23CI001, John Doe, 9876543210\n4MH23CI002, Jane Smith',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: textController,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        '4MH23CI001, John Doe, 9876543210\n4MH23CI002, Jane Smith\n...',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final lines = textController.text.trim().split('\n');
                        if (lines.isEmpty) return;

                        setState(() => isSaving = true);
                        final currentBatchId = Provider.of<AppState>(
                          context,
                          listen: false,
                        ).selectedBatchId;

                        int successCount = 0;
                        int errorCount = 0;

                        for (var line in lines) {
                          final parts = line
                              .split(',')
                              .map((p) => p.trim())
                              .toList();
                          if (parts.length < 2) continue;

                          final usn = parts[0].toUpperCase();
                          final name = parts[1];
                          final number = parts.length > 2 ? parts[2] : '';

                          try {
                            await FirebaseFirestore.instance
                                .collection('students')
                                .doc('${currentBatchId}_$usn')
                                .set({
                                  'name': name,
                                  'usn': usn,
                                  'number': number.isEmpty ? null : number,
                                  'batchYear': currentBatchId,
                                  'currentSemester': 1,
                                  'createdAt': FieldValue.serverTimestamp(),
                                }, SetOptions(merge: true));
                            successCount++;
                          } catch (e) {
                            errorCount++;
                          }
                        }

                        setState(() => isSaving = false);
                        Navigator.pop(context);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Added $successCount students. Failed: $errorCount',
                            ),
                            backgroundColor: successCount > 0
                                ? Colors.green
                                : Colors.red,
                          ),
                        );
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Add Students'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedBatchName =
        Provider.of<AppState>(context).selectedBatchName ?? 'Students';

    return Scaffold(
      appBar: AppBar(
        title: Text('Students - $selectedBatchName'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _studentsStream,
        builder: (context, snapshot) {
          if (_selectedBatchId == null) {
            return const Center(
              child: Text("Batch information is missing. Please go back."),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Error fetching students: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'No students added for this batch yet.\nTap the + button below to add students.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.upload),
                      label: const Text('Bulk Add Students'),
                      onPressed: _showBulkAddDialog,
                    ),
                  ],
                ),
              ),
            );
          }

          final students = snapshot.data!.docs;
          return ListView.builder(
            itemCount: students.length,
            itemBuilder: (context, index) {
              final studentDoc = students[index];
              final studentData =
                  studentDoc.data() as Map<String, dynamic>? ?? {};
              final name = studentData['name'] as String? ?? 'Unnamed Student';
              final usn = studentData['usn'] as String? ?? 'No USN';
              final number = studentData['number'] as String? ?? 'N/A';
              final currentSemester =
                  studentData['currentSemester'] as int? ?? 1;

              return Dismissible(
                key: Key(studentDoc.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (direction) async {
                  _showDeleteStudentDialog(studentDoc.id, name, usn);
                  return false; // We handle deletion in the dialog
                },
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.red,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  elevation: 2,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).primaryColorLight,
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColorDark,
                        ),
                      ),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('USN: $usn'),
                        Text('Phone: $number | Sem: $currentSemester'),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                      onSelected: (value) {
                        if (value == 'edit') {
                          _editStudent(studentDoc.id, studentData);
                        } else if (value == 'delete') {
                          _showDeleteStudentDialog(studentDoc.id, name, usn);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Edit'), dense: true, contentPadding: EdgeInsets.zero)),
                        const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, color: Colors.red), title: Text('Delete', style: TextStyle(color: Colors.red)), dense: true, contentPadding: EdgeInsets.zero)),
                      ],
                    ),
                    onTap: () => _editStudent(studentDoc.id, studentData),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'bulk',
            onPressed: _showBulkAddDialog,
            tooltip: 'Bulk Add Students',
            child: const Icon(Icons.upload),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            onPressed: _showAddStudentDialog,
            tooltip: 'Add New Student',
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  // --- Delete Student Dialog ---
  void _showDeleteStudentDialog(String studentDocId, String studentName, String usn) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        bool isDeleting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Delete Student?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodyMedium,
                      children: [
                        const TextSpan(text: 'Are you sure you want to delete '),
                        TextSpan(text: '$studentName ($usn)', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const TextSpan(text: '?'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This will also delete ALL marks, final exam marks, and semester results for this student.',
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isDeleting ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: isDeleting ? null : () async {
                    setDialogState(() => isDeleting = true);
                    try {
                      final batch = FirebaseFirestore.instance.batch();
                      
                      // Delete from marks collection
                      final marksSnap = await FirebaseFirestore.instance
                          .collection('marks')
                          .where('studentRef', isEqualTo: FirebaseFirestore.instance.doc('students/$studentDocId'))
                          .get();
                      for (var doc in marksSnap.docs) {
                        batch.delete(doc.reference);
                      }

                      // Delete from finalExamMarks collection
                      final finalMarksSnap = await FirebaseFirestore.instance
                          .collection('finalExamMarks')
                          .where('studentRef', isEqualTo: FirebaseFirestore.instance.doc('students/$studentDocId'))
                          .get();
                      for (var doc in finalMarksSnap.docs) {
                        batch.delete(doc.reference);
                      }

                      // Delete from semesterResults collection
                      final resultsSnap = await FirebaseFirestore.instance
                          .collection('semesterResults')
                          .where('studentId', isEqualTo: studentDocId)
                          .get();
                      for (var doc in resultsSnap.docs) {
                        batch.delete(doc.reference);
                      }

                      // Delete the student document itself
                      batch.delete(FirebaseFirestore.instance.collection('students').doc(studentDocId));

                      await batch.commit();

                      if (!dialogContext.mounted) return;
                      Navigator.of(dialogContext).pop();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$studentName deleted with all related data.'), backgroundColor: Colors.green),
                        );
                      }
                    } catch (e) {
                      setDialogState(() => isDeleting = false);
                      if (!dialogContext.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error deleting: $e'), backgroundColor: Colors.red),
                      );
                    }
                  },
                  child: isDeleting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Delete', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- Edit Student Dialog ---
  void _editStudent(String studentId, Map<String, dynamic> studentData) {
    final nameController = TextEditingController(
      text: studentData['name'] ?? '',
    );
    final usnController = TextEditingController(text: studentData['usn'] ?? '');
    final numberController = TextEditingController(
      text: studentData['number']?.toString() ?? '',
    );
    final semesterController = TextEditingController(
      text: (studentData['currentSemester'] ?? 1).toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Student'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextFormField(
                controller: usnController,
                decoration: const InputDecoration(labelText: 'USN'),
                enabled: false, // USN cannot be changed
              ),
              TextFormField(
                controller: numberController,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
              ),
              TextFormField(
                controller: semesterController,
                decoration: const InputDecoration(
                  labelText: 'Current Semester',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .collection('students')
                    .doc(studentId)
                    .update({
                      'name': nameController.text.trim(),
                      'number': numberController.text.trim().isEmpty
                          ? null
                          : numberController.text.trim(),
                      'currentSemester':
                          int.tryParse(semesterController.text) ?? 1,
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Student updated'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
