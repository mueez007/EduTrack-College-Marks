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
    _selectedBatchId = Provider.of<AppState>(context, listen: false).selectedBatchId;

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
             const SnackBar(content: Text('Error: Batch ID is missing. Please select a batch first.'), backgroundColor: Colors.red),
           );
           Navigator.of(context).pop(); 
        }
      });
    }
  }

  // --- Add New Student Dialog (MANUAL AUTH VERSION) ---
  void _showAddStudentDialog() {
    final nameController = TextEditingController();
    final usnController = TextEditingController();
    final numberController = TextEditingController();
    final passwordController = TextEditingController();
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
                    passwordController,
                    nameController,
                    numberController,
                    setDialogState,
                    () => isSaving = false
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
                        decoration: const InputDecoration(labelText: "Student Name"),
                        validator: (value) => value == null || value.isEmpty ? 'Please enter a name' : null,
                        textInputAction: TextInputAction.next,
                      ),
                      TextFormField(
                        controller: usnController,
                        decoration: const InputDecoration(labelText: "USN (Student ID)"),
                         validator: (value) => value == null || value.isEmpty ? 'Please enter a USN' : null,
                         textCapitalization: TextCapitalization.characters,
                         textInputAction: TextInputAction.next,
                      ),
                      TextFormField(
                        controller: numberController,
                        decoration: const InputDecoration(labelText: "Phone Number (Optional)"),
                        keyboardType: TextInputType.phone,
                         textInputAction: TextInputAction.next,
                      ),
                      TextFormField(
                        controller: passwordController,
                        decoration: const InputDecoration(labelText: "Set Password (Min 6 chars)"),
                        obscureText: true, 
                         validator: (value) {
                           if (value == null || value.isEmpty) return 'Please enter password';
                           if (value.length < 6) return 'Password must be at least 6 characters';
                           return null; 
                         },
                         textInputAction: TextInputAction.done, 
                         onFieldSubmitted: (_) { 
                           if (!isSaving) handleAction();
                         },
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 10.0),
                        // Note for Teacher/Admin:
                        child: Text("NOTE: Auth user must be manually created for login.", style: TextStyle(color: Colors.orange, fontSize: 11)), 
                      )
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: isSaving ? null : handleAction,
                   child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text("Add Student"),
                ),
              ],
            );
          }
        );
      },
    );
  } 

  // --- Helper function for the Add Student action logic (STABLE MANUAL WRITE) ---
   Future<void> _handleAddStudentAction(
      BuildContext dialogContext,
      TextEditingController usnController,
      TextEditingController passwordController,
      TextEditingController nameController,
      TextEditingController numberController,
      StateSetter setDialogState,
      VoidCallback resetIsSaving) async {

    final String name = nameController.text.trim();
    final String usn = usnController.text.trim().toUpperCase();
    final String number = numberController.text.trim();
    final String password = passwordController.text.trim();
    final currentBatchId = Provider.of<AppState>(context, listen: false).selectedBatchId;
    
    // NOTE: UID is set to null/placeholder because Auth is done MANUALLY
    
    if (currentBatchId == null) {
      resetIsSaving(); 
      if (!mounted) return; 
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: No batch selected. Cannot add student.'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      // 1. CREATE STUDENT DOCUMENT (Data Record) in Firestore /students
      DocumentReference studentRef = FirebaseFirestore.instance.collection('students').doc('${currentBatchId}_$usn');

      // 2. Check for Duplicates
      DocumentSnapshot docSnapshot = await studentRef.get();
      if (docSnapshot.exists) {
         throw Exception("USN $usn already registered in this batch."); 
      }
      
      // 3. Perform Simple Write
      await studentRef.set({
        'name': name,
        'usn': usn,
        'number': number.isEmpty ? null : number,
        'password': password, // Storing raw password for MANUAL Auth verification/lookup
        'batchYear': currentBatchId,
        // The UID link will be added manually by admin after Auth user is created.
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      // Success
      resetIsSaving(); 
      if (!dialogContext.mounted) return;
      Navigator.of(dialogContext).pop(); 
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Student $usn added. Auth user required.'), backgroundColor: Colors.green),
      );

    } catch (e) {
       resetIsSaving(); 
       print("Error adding student: $e");
       ScaffoldMessenger.of(dialogContext).showSnackBar(
         SnackBar(content: Text('Failed to add student. Error: ${e.toString()}'), backgroundColor: Colors.red),
       );
    }
  } 


  @override
  Widget build(BuildContext context) {
    final selectedBatchName = Provider.of<AppState>(context).selectedBatchName ?? 'Students';

    return Scaffold(
      appBar: AppBar(
        title: Text('Students - $selectedBatchName'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _studentsStream,
        builder: (context, snapshot) {
          if (_selectedBatchId == null) {
            return const Center(child: Text("Batch information is missing. Please go back."));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error fetching students: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Text(
                  'No students added for this batch yet.\nTap the + button below to add the first student.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            );
          }

          final students = snapshot.data!.docs;
          return ListView.builder(
            itemCount: students.length,
            itemBuilder: (context, index) {
              final studentDoc = students[index];
              final studentData = studentDoc.data() as Map<String, dynamic>? ?? {};
              final name = studentData['name'] as String? ?? 'Unnamed Student';
              final usn = studentData['usn'] as String? ?? 'No USN';
              final number = studentData['number'] as String? ?? 'N/A'; 

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                elevation: 2, 
                child: ListTile(
                  leading: CircleAvatar( 
                    backgroundColor: Theme.of(context).primaryColorLight,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColorDark),
                    )
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text('USN: $usn | Phone: $number'),
                ),
              ); 
            }, 
          ); 
        }, 
      ), 
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddStudentDialog,
        tooltip: 'Add New Student',
        child: const Icon(Icons.add),
      ), 
    );
  }
}