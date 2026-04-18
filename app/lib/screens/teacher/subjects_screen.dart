import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/app_state.dart'; 
import 'marks_entry_screen.dart'; 

class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({super.key});

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  String? _selectedBatchId;
  int _selectedSemester = 1; 
  Stream<QuerySnapshot>? _subjectsStream;

  // --- Maps for Dropdowns (IA and Final Exam Rules) ---
  final Map<String, String> _iaRuleOptions = {
    'SEM_5_6_SCHEMA': 'Best 2/3 (40) + Proj/Assign (25) -> 50 IA Total', 
    'SEM_SPECIAL_100_MARK_SCHEMA': 'Best 2/3 (30) to 25 + Proj (25) -> 50 IA Total (Special Subject)', 
    'BEST_2_OF_3_AVG': 'Best 2/3 (25) + Assign (10) + Lab (25) -> 50 IA Total',
  };

   final Map<String, String> _finalExamRuleOptions = {
    'HUNDRED_REDUCED_TO_FIFTY': 'Exam (100)/2 + IA (50)', 
    'FIFTY_FIFTY_RAW': 'Exam (50) + IA (50)', 
    'THIRTY_THIRTY_RAW': 'Exam (Scaled to 15) + IA (15) [Total 30]',
  };
  // --- End of Maps ---

  @override
  void initState() {
    super.initState();
    _selectedBatchId = Provider.of<AppState>(context, listen: false).selectedBatchId;
    _loadSubjects();
  }

  void _loadSubjects() {
    if (_selectedBatchId != null) {
      setState(() {
        _subjectsStream = FirebaseFirestore.instance
            .collection('subjects')
            .where('batchYear', isEqualTo: _selectedBatchId)
            .where('semester', isEqualTo: _selectedSemester) 
            .orderBy('subjectCode') 
            .snapshots();
      });
    } else {
       WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Error: Batch ID missing.'), backgroundColor: Colors.red),
           );
        }
      });
    }
  }

  // --- Add New Subject Dialog ---
  void _showAddSubjectDialog() {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final creditsController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    String? dialogSelectedIaRule = _iaRuleOptions.keys.isNotEmpty ? _iaRuleOptions.keys.first : null;
    String? dialogSelectedFinalExamRule = _finalExamRuleOptions.keys.isNotEmpty ? _finalExamRuleOptions.keys.first : null;


    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
            builder: (stfContext, setDialogState) {
          return AlertDialog(
            title: Text("Add New Subject for Sem $_selectedSemester"),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: "Subject Name"),
                      validator: (value) => value == null || value.isEmpty ? 'Required' : null,
                      textInputAction: TextInputAction.next,
                    ),
                    TextFormField(
                      controller: codeController,
                      decoration: const InputDecoration(labelText: "Subject Code"),
                      validator: (value) => value == null || value.isEmpty ? 'Required' : null,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,
                    ),
                    TextFormField(
                      controller: creditsController,
                      decoration: const InputDecoration(labelText: "Credits (0 for no weightage)"),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Required';
                        final parsed = int.tryParse(value);
                        if (parsed == null || parsed < 0) return 'Must be >= 0';
                        return null;
                      },
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 15),
                    // Dropdown for IA Calculation Rule
                    if (_iaRuleOptions.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: dialogSelectedIaRule,
                        decoration: const InputDecoration(labelText: 'IA Calculation Rule', border: OutlineInputBorder()),
                        items: _iaRuleOptions.entries.map((entry) {
                          return DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value, overflow: TextOverflow.ellipsis, maxLines: 2,),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setDialogState(() { dialogSelectedIaRule = newValue; });
                        },
                        validator: (value) => value == null ? 'Please select a rule' : null,
                        isExpanded: true,
                      )
                    else
                      const Text("No IA rules configured.", style: TextStyle(color: Colors.red)),

                     const SizedBox(height: 15),
                    // Dropdown for Final Exam Rule
                     if (_finalExamRuleOptions.isNotEmpty)
                       DropdownButtonFormField<String>(
                        initialValue: dialogSelectedFinalExamRule,
                        decoration: const InputDecoration(labelText: 'Final Exam/Total Rule', border: OutlineInputBorder()),
                        items: _finalExamRuleOptions.entries.map((entry) {
                          return DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value, overflow: TextOverflow.ellipsis, maxLines: 2,),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setDialogState(() { dialogSelectedFinalExamRule = newValue; });
                        },
                        validator: (value) => value == null ? 'Please select a rule' : null,
                         isExpanded: true,
                      )
                     else
                      const Text("No Final Exam rules configured.", style: TextStyle(color: Colors.red)),
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
                onPressed: (isSaving || dialogSelectedIaRule == null || dialogSelectedFinalExamRule == null) ? null : () async {
                  if (formKey.currentState!.validate()) {
                    setDialogState(() => isSaving = true);

                    final String name = nameController.text.trim();
                    final String code = codeController.text.trim().toUpperCase();
                    final int credits = int.parse(creditsController.text.trim());
                    final String iaRule = dialogSelectedIaRule!; 
                    final String finalExamRule = dialogSelectedFinalExamRule!; 
                    final currentBatchId = Provider.of<AppState>(context, listen: false).selectedBatchId;

                    if (currentBatchId == null) {
                      setDialogState(() => isSaving = false);
                       if (!mounted) return;
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text('Error: No batch selected.'), backgroundColor: Colors.red),
                       );
                       return;
                    }

                    try {
                      DocumentReference subjectRef = FirebaseFirestore.instance.collection('subjects').doc('${currentBatchId}_S${_selectedSemester}_$code');
                      final docSnapshot = await subjectRef.get();
                      if (docSnapshot.exists) {
                         setDialogState(() => isSaving = false);
                         if (!dialogContext.mounted) return;
                         ScaffoldMessenger.of(dialogContext).showSnackBar(
                           SnackBar(content: Text('Subject code $code already exists for Sem $_selectedSemester in this batch.'), backgroundColor: Colors.orange),
                         );
                         return;
                      }

                      // --- Dynamic Max Mark Assignment ---
                      int maxInternalTotal = 50; 
                      int maxExamTotal = 50; 
                      int maxSubjectTotal = 100; // <<< DEFAULT FOR SGPA IS SET HERE
                      int baseInternalMax = 40; 
                      int maxProject = 0;
                      int maxAssignment = 0;
                      int maxLab = 0;
                      int maxExamInput = 100;

                      // Logic based on IA Rule
                      if (iaRule == 'SEM_5_6_SCHEMA') {
                          maxProject = 25;
                      } else if (iaRule == 'SEM_SPECIAL_100_MARK_SCHEMA') { 
                          baseInternalMax = 30; 
                          maxProject = 25; 
                      } else if (iaRule == 'BEST_2_OF_3_AVG') {
                          baseInternalMax = 25; 
                          maxAssignment = 10;
                          maxLab = 25;
                          // maxInternalTotal = 15; // Set this manually if IA is reduced to 15
                      }
                      
                      // Logic based on Final Exam Rule (overrides total if 30-mark subject)
                      if (finalExamRule == 'HUNDRED_REDUCED_TO_FIFTY') {
                          maxExamInput = 100; // Input is 100, output is 50
                          maxExamTotal = 50;
                      } else if (finalExamRule == 'FIFTY_FIFTY_RAW') {
                          maxExamInput = 50; // Input is 50, output is 50
                          maxExamTotal = 50;
                      } else if (finalExamRule == 'THIRTY_THIRTY_RAW') {
                          maxExamTotal = 15; // Max exam component is 15
                          maxInternalTotal = 15; // Max IA component is 15
                          maxSubjectTotal = 30; // Total subject mark is 30
                          maxExamInput = 50; // Assume teacher inputs 50 which is scaled down
                      }
                      
                      Map<String, dynamic> subjectData = {
                          'subjectName': name,
                          'subjectCode': code,
                          'credits': credits,
                          'batchYear': currentBatchId,
                          'semester': _selectedSemester,
                          'iaCalculationRule': iaRule,
                          'finalExamRule': finalExamRule,
                          // --- MAX MARK FIELDS ---
                          'maxSubjectTotal': maxSubjectTotal, // <<< SET AUTOMATICALLY HERE
                          'maxInternalTotal': maxInternalTotal, 
                          'maxExamTotal': maxExamTotal, 
                          'baseInternalMax': baseInternalMax, 
                          'maxProject': maxProject, 
                          'maxAssignment': maxAssignment, 
                          'maxLab': maxLab, 
                          'maxExamInput': maxExamInput, 
                          'createdAt': FieldValue.serverTimestamp(),
                        };

                      await subjectRef.set(subjectData);

                      if (!dialogContext.mounted) return;
                      Navigator.of(dialogContext).pop(); 
                      ScaffoldMessenger.of(context).showSnackBar( 
                        SnackBar(content: Text('Subject $code added successfully.'), backgroundColor: Colors.green),
                      );

                    } catch (e) {
                       print("Error adding subject: $e");
                       setDialogState(() => isSaving = false);
                       if (!dialogContext.mounted) return;
                       ScaffoldMessenger.of(dialogContext).showSnackBar(
                         SnackBar(content: Text('Failed to add subject. Error: ${e.toString()}'), backgroundColor: Colors.red),
                       );
                    }
                  }
                },
                 style: ElevatedButton.styleFrom(
                   minimumSize: const Size(110, 40),
                 ),
                child: isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text("Add Subject"),
              ),
            ],
          );
         }
        );
      },
    );
  }

  // --- Edit Subject Dialog ---
  void _showEditSubjectDialog(String subjectDocId, Map<String, dynamic> existingData) {
    final nameController = TextEditingController(text: existingData['subjectName'] ?? '');
    final codeController = TextEditingController(text: existingData['subjectCode'] ?? '');
    final creditsController = TextEditingController(text: (existingData['credits'] ?? 0).toString());
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    String? dialogSelectedIaRule = existingData['iaCalculationRule'] ?? _iaRuleOptions.keys.first;
    String? dialogSelectedFinalExamRule = existingData['finalExamRule'] ?? _finalExamRuleOptions.keys.first;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (stfContext, setDialogState) {
            return AlertDialog(
              title: Text("Edit Subject"),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: "Subject Name"),
                        validator: (value) => value == null || value.isEmpty ? 'Required' : null,
                        textInputAction: TextInputAction.next,
                      ),
                      TextFormField(
                        controller: codeController,
                        decoration: const InputDecoration(labelText: "Subject Code"),
                        enabled: false, // Code cannot be changed as it's part of the doc ID
                        textCapitalization: TextCapitalization.characters,
                      ),
                      TextFormField(
                        controller: creditsController,
                        decoration: const InputDecoration(labelText: "Credits (0 for no weightage)"),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Required';
                          final parsed = int.tryParse(value);
                          if (parsed == null || parsed < 0) return 'Must be >= 0';
                          return null;
                        },
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 15),
                      DropdownButtonFormField<String>(
                        initialValue: dialogSelectedIaRule,
                        decoration: const InputDecoration(labelText: 'IA Calculation Rule', border: OutlineInputBorder()),
                        items: _iaRuleOptions.entries.map((entry) {
                          return DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value, overflow: TextOverflow.ellipsis, maxLines: 2),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setDialogState(() { dialogSelectedIaRule = newValue; });
                        },
                        isExpanded: true,
                      ),
                      const SizedBox(height: 15),
                      DropdownButtonFormField<String>(
                        initialValue: dialogSelectedFinalExamRule,
                        decoration: const InputDecoration(labelText: 'Final Exam/Total Rule', border: OutlineInputBorder()),
                        items: _finalExamRuleOptions.entries.map((entry) {
                          return DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value, overflow: TextOverflow.ellipsis, maxLines: 2),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setDialogState(() { dialogSelectedFinalExamRule = newValue; });
                        },
                        isExpanded: true,
                      ),
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
                  onPressed: isSaving ? null : () async {
                    if (formKey.currentState!.validate()) {
                      setDialogState(() => isSaving = true);

                      final String name = nameController.text.trim();
                      final int credits = int.parse(creditsController.text.trim());
                      final String iaRule = dialogSelectedIaRule!;
                      final String finalExamRule = dialogSelectedFinalExamRule!;

                      // Recalculate max marks based on rules
                      int maxInternalTotal = 50;
                      int maxExamTotal = 50;
                      int maxSubjectTotal = 100;
                      int baseInternalMax = 40;
                      int maxProject = 0;
                      int maxAssignment = 0;
                      int maxLab = 0;
                      int maxExamInput = 100;

                      if (iaRule == 'SEM_5_6_SCHEMA') {
                        maxProject = 25;
                      } else if (iaRule == 'SEM_SPECIAL_100_MARK_SCHEMA') {
                        baseInternalMax = 30;
                        maxProject = 25;
                      } else if (iaRule == 'BEST_2_OF_3_AVG') {
                        baseInternalMax = 25;
                        maxAssignment = 10;
                        maxLab = 25;
                      }

                      if (finalExamRule == 'HUNDRED_REDUCED_TO_FIFTY') {
                        maxExamInput = 100;
                        maxExamTotal = 50;
                      } else if (finalExamRule == 'FIFTY_FIFTY_RAW') {
                        maxExamInput = 50;
                        maxExamTotal = 50;
                      } else if (finalExamRule == 'THIRTY_THIRTY_RAW') {
                        maxExamTotal = 15;
                        maxInternalTotal = 15;
                        maxSubjectTotal = 30;
                        maxExamInput = 50;
                      }

                      try {
                        await FirebaseFirestore.instance.collection('subjects').doc(subjectDocId).update({
                          'subjectName': name,
                          'credits': credits,
                          'iaCalculationRule': iaRule,
                          'finalExamRule': finalExamRule,
                          'maxSubjectTotal': maxSubjectTotal,
                          'maxInternalTotal': maxInternalTotal,
                          'maxExamTotal': maxExamTotal,
                          'baseInternalMax': baseInternalMax,
                          'maxProject': maxProject,
                          'maxAssignment': maxAssignment,
                          'maxLab': maxLab,
                          'maxExamInput': maxExamInput,
                          'updatedAt': FieldValue.serverTimestamp(),
                        });

                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Subject updated successfully.'), backgroundColor: Colors.green),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (!dialogContext.mounted) return;
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text("Save Changes"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- Delete Subject ---
  void _deleteSubject(String subjectDocId, String subjectCode) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete Subject?'),
          content: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: [
                const TextSpan(text: 'Are you sure you want to delete '),
                TextSpan(text: subjectCode, style: const TextStyle(fontWeight: FontWeight.bold)),
                const TextSpan(text: '?\n\n'),
                const TextSpan(
                  text: '⚠️ This will NOT delete any marks or final exam data already entered for this subject. Those must be cleaned up manually if needed.',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                try {
                  await FirebaseFirestore.instance.collection('subjects').doc(subjectDocId).delete();
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Subject $subjectCode deleted.'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error deleting: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  // --- Navigation and Build methods remain the same ---
  void _navigateToMarksEntry(String subjectId, String subjectCode, String subjectName, Map<String, dynamic> subjectData) {
     Navigator.push(
       context,
       MaterialPageRoute(
          builder: (context) => MarksEntryScreen(
             subjectId: subjectId, 
             subjectCode: subjectCode,
             subjectName: subjectName,
             subjectData: subjectData, 
          ),
       ),
     );
  }


  @override
  Widget build(BuildContext context) {
    // ... (rest of the UI build method remains the same) ...
     final selectedBatchName = Provider.of<AppState>(context).selectedBatchName ?? 'Subjects';

    return Scaffold(
      appBar: AppBar(
        title: Text('Subjects - $selectedBatchName'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // --- Semester Selection Row ---
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
                            _loadSubjects(); // Reload subjects for the new semester
                          });
                        }
                      },
                      selectedColor: Theme.of(context).primaryColor,
                      labelStyle: TextStyle(color: isSelected ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color),
                      backgroundColor: Theme.of(context).chipTheme.backgroundColor ?? Colors.grey[200],
                      shape: StadiumBorder(side: BorderSide(color: isSelected ? Theme.of(context).primaryColor : Colors.grey)),
                    ),
                  );
                },
              ),
            ),
          ),
          const Divider(),

          // --- Subjects List ---
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _subjectsStream,
              builder: (context, snapshot) {
                 if (_selectedBatchId == null) {
                   return const Center(child: Text("Batch information is missing."));
                 }
                 if (snapshot.connectionState == ConnectionState.waiting) {
                   return const Center(child: CircularProgressIndicator());
                 }
                 if (snapshot.hasError) {
                   print("Firestore Stream Error (Subjects): ${snapshot.error}");
                   return Center(child: Text('Error fetching subjects: ${snapshot.error}'));
                 }
                 if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                   return Center(
                     child: Padding(
                       padding: const EdgeInsets.all(20.0),
                       child: Text(
                          'No subjects added for Sem $_selectedSemester yet.\nTap the + button to add.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        ),
                     )
                    );
                 }

                 final subjects = snapshot.data!.docs;
                 return ListView.builder(
                   itemCount: subjects.length,
                   itemBuilder: (context, index) {
                     final subjectDoc = subjects[index];
                     final subjectData = subjectDoc.data() as Map<String, dynamic>? ?? {};
                     final name = subjectData['subjectName'] as String? ?? 'No Name';
                     final code = subjectData['subjectCode'] as String? ?? 'No Code';
                     final credits = (subjectData['credits'] as num?)?.toString() ?? '?';

                     return Dismissible(
                       key: Key(subjectDoc.id),
                       direction: DismissDirection.endToStart,
                       confirmDismiss: (direction) async {
                         _deleteSubject(subjectDoc.id, code);
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
                         elevation: 1.5,
                         child: ListTile(
                           leading: CircleAvatar( 
                              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                              child: Text(credits, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSecondaryContainer))
                            ),
                           title: Text(name), 
                           subtitle: Text('Code: $code | Credits: $credits'), 
                           trailing: PopupMenuButton<String>(
                             icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                             onSelected: (value) {
                               if (value == 'edit') {
                                 _showEditSubjectDialog(subjectDoc.id, subjectData);
                               } else if (value == 'delete') {
                                 _deleteSubject(subjectDoc.id, code);
                               } else if (value == 'marks') {
                                 _navigateToMarksEntry(subjectDoc.id, code, name, subjectData);
                               }
                             },
                             itemBuilder: (context) => [
                               const PopupMenuItem(value: 'marks', child: ListTile(leading: Icon(Icons.edit_note), title: Text('Enter Marks'), dense: true, contentPadding: EdgeInsets.zero)),
                               const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Edit Subject'), dense: true, contentPadding: EdgeInsets.zero)),
                               const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, color: Colors.red), title: Text('Delete', style: TextStyle(color: Colors.red)), dense: true, contentPadding: EdgeInsets.zero)),
                             ],
                           ),
                           onTap: () => _navigateToMarksEntry(subjectDoc.id, code, name, subjectData), 
                         ),
                       ),
                     );
                   },
                 );
               },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSubjectDialog,
        tooltip: 'Add New Subject',
        child: const Icon(Icons.add),
      ),
    );
  }
}