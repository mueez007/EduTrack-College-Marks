import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Imports for PDF generation
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw; // Use prefix 'pw'
import 'package:printing/printing.dart';

import '../../providers/app_state.dart';
import '../../services/mark_calculation_service.dart'; // For local total calculation

// --- Models for Data Structure (Same as previous output) ---
class StudentFinalMarkModel {
  final String studentId;
  final String studentName;
  final String studentUsn;
  final Map<String, SubjectFinalMarkData> subjectMarks;

  StudentFinalMarkModel({
    required this.studentId,
    required this.studentName,
    required this.studentUsn,
    required this.subjectMarks,
  });
}

class SubjectFinalMarkData {
  final String subjectCode;
  final String subjectName;
  final double? iaFinal;
  int? examFinal;
  double? calculatedTotal;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String markDocId;
  final Map<String, dynamic> subjectDataMap;

  SubjectFinalMarkData({
    required this.subjectCode,
    required this.subjectName,
    this.iaFinal,
    this.examFinal,
    this.calculatedTotal,
    required this.controller,
    required this.focusNode,
    required this.markDocId,
    required this.subjectDataMap,
  });
}
// -----------------------------------------------------------

class FinalExamMarksScreen extends StatefulWidget {
  const FinalExamMarksScreen({super.key});

  @override
  State<FinalExamMarksScreen> createState() => _FinalExamMarksScreenState();
}

class _FinalExamMarksScreenState extends State<FinalExamMarksScreen> {
  String? _selectedBatchId;
  int _selectedSemester = 1; // Default to semester 1
  bool _isLoading = true;
  List<StudentFinalMarkModel> _studentFinalMarks = [];
  List<QueryDocumentSnapshot> _subjectsForSemester = [];

  final MarkCalculationService _markCalculator = MarkCalculationService();
  final Map<String, FocusNode> _focusNodes = {};

  @override
  void initState() {
    super.initState();
    _selectedBatchId = Provider.of<AppState>(
      context,
      listen: false,
    ).selectedBatchId;
    _loadInitialData(); // Load data for default semester
  }

  @override
  void dispose() {
    _focusNodes.forEach((_, node) => node.dispose());
    _studentFinalMarks.forEach((studentModel) {
      studentModel.subjectMarks.forEach((_, subjectData) {
        subjectData.controller.dispose();
      });
    });
    super.dispose();
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  // --- Load all necessary data (students, subjects, marks) ---
  Future<void> _loadInitialData() async {
    if (_selectedBatchId == null) {
      setState(() => _isLoading = false);
      _showError("Batch ID is missing. Please select a batch and try again.");
      return;
    }
    setState(() => _isLoading = true);

    try {
      // 1. Get Subjects for the selected semester and batch
      QuerySnapshot subjectSnapshot = await FirebaseFirestore.instance
          .collection('subjects')
          .where('batchYear', isEqualTo: _selectedBatchId)
          .where('semester', isEqualTo: _selectedSemester)
          .orderBy('subjectCode')
          .get();
      _subjectsForSemester = subjectSnapshot.docs;

      if (_subjectsForSemester.isEmpty) {
        setState(() {
          _studentFinalMarks = [];
          _isLoading = false;
        });
        return;
      }

      // 2. Get Students for the batch
      QuerySnapshot studentSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('batchYear', isEqualTo: _selectedBatchId)
          .orderBy('name')
          .get();

      List<StudentFinalMarkModel> loadedData = [];

      // 3. For each student, get IA Final and Exam Final for each subject
      for (var studentDoc in studentSnapshot.docs) {
        final studentData = studentDoc.data() as Map<String, dynamic>;
        final studentId = studentDoc.id;
        final studentUsn = studentData['usn'] ?? 'N/A';
        final studentName = studentData['name'] ?? 'No Name';

        Map<String, SubjectFinalMarkData> subjectMarksData = {};

        for (var subjectDoc in _subjectsForSemester) {
          final subjectId = subjectDoc.id;
          final subjectCode = subjectDoc['subjectCode'] ?? 'N/A';
          final subjectName = subjectDoc['subjectName'] ?? 'No Name';
          final subjectDataMap =
              subjectDoc.data() as Map<String, dynamic>? ?? {};

          // a) Get IA Final from 'marks' collection
          final iaMarkDocId = '${studentId}_${subjectId}';
          DocumentSnapshot iaMarkSnapshot = await FirebaseFirestore.instance
              .collection('marks')
              .doc(iaMarkDocId)
              .get();
          double? iaFinalMark =
              (iaMarkSnapshot.exists
                      ? (iaMarkSnapshot.data()
                                as Map<String, dynamic>)['calculated_iaFinal']
                            as num?
                      : null)
                  ?.toDouble();

          // b) Get Exam Final from 'finalExamMarks' collection
          final finalMarkDocId = '${studentId}_${subjectId}';
          DocumentSnapshot finalMarkSnapshot = await FirebaseFirestore.instance
              .collection('finalExamMarks')
              .doc(finalMarkDocId)
              .get();
          int? examFinalMark = finalMarkSnapshot.exists
              ? (finalMarkSnapshot.data() as Map<String, dynamic>)['examFinal']
                    as int?
              : null;

          // c) Calculate Total locally
          double? calculatedTotalMark = _markCalculator
              .calculateTotalMarksLocal(
                iaFinal: iaFinalMark,
                examFinal: examFinalMark,
                subjectData: subjectDataMap,
              );

          // d) Create Controller and Focus Node
          final controller = TextEditingController(
            text: examFinalMark?.toString() ?? '',
          );
          final focusNodeKey = '${studentId}_${subjectId}';
          if (!_focusNodes.containsKey(focusNodeKey)) {
            _focusNodes[focusNodeKey] = FocusNode();
          }

          subjectMarksData[subjectId] = SubjectFinalMarkData(
            subjectCode: subjectCode,
            subjectName: subjectName,
            iaFinal: iaFinalMark,
            examFinal: examFinalMark,
            calculatedTotal: calculatedTotalMark,
            controller: controller,
            focusNode: _focusNodes[focusNodeKey]!,
            markDocId: finalMarkDocId, // ID for saving finalExamMarks
            subjectDataMap: subjectDataMap,
          );
        }

        loadedData.add(
          StudentFinalMarkModel(
            studentId: studentId,
            studentName: studentName,
            studentUsn: studentUsn,
            subjectMarks: subjectMarksData,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _studentFinalMarks = loadedData;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error loading final marks data: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        _showError("Error loading data: ${e.toString()}");
      }
    }
  }

  // --- Save Final Exam Mark for one student/subject ---
  Future<void> _saveFinalMark(
    StudentFinalMarkModel studentModel,
    String subjectId,
  ) async {
    final subjectData = studentModel.subjectMarks[subjectId];
    if (subjectData == null) return;

    int? examMark = int.tryParse(subjectData.controller.text);
    int maxExamMark = subjectData.subjectDataMap['maxExamFinal'] ?? 100;

    // Validate input range
    if (examMark != null && (examMark < 0 || examMark > maxExamMark)) {
      _showError(
        "Exam mark for ${subjectData.subjectCode} must be between 0 and $maxExamMark.",
      );
      return;
    }

    try {
      // Recalculate Total locally
      double newCalculatedTotal = _markCalculator.calculateTotalMarksLocal(
        iaFinal: subjectData.iaFinal,
        examFinal: examMark,
        subjectData: subjectData.subjectDataMap,
      );

      // Prepare data for Firestore ('finalExamMarks' collection)
      Map<String, dynamic> dataToSave = {
        'iaFinal': subjectData.iaFinal,
        'examFinal': examMark,
        'calculated_total': newCalculatedTotal,

        // --- AUTOMATION FIELDS ADDED ---
        'semester': _selectedSemester, // ✅ Already exists
        'sent': false, // ✅ ADDED: Automation flag
        'markType': 'FINAL_EXAM', // ✅ ADDED: Type of mark

        // -----------------------------
        'batchYear': _selectedBatchId,
        'studentRef': FirebaseFirestore.instance.doc(
          'students/${studentModel.studentId}',
        ),
        'subjectRef': FirebaseFirestore.instance.doc('subjects/$subjectId'),
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      // Save to Firestore
      await FirebaseFirestore.instance
          .collection('finalExamMarks')
          .doc(subjectData.markDocId)
          .set(dataToSave, SetOptions(merge: true));

      // Update local state for immediate UI feedback
      if (mounted) {
        setState(() {
          subjectData.examFinal = examMark;
          subjectData.calculatedTotal = newCalculatedTotal;
        });
      }
    } catch (e) {
      print("Error saving final mark: $e");
      _showError(
        "Error saving for ${subjectData.subjectCode}: ${e.toString()}",
      );
    }
  }

  // --- Helper to build Exam Final input ---
  Widget _buildExamInput(StudentFinalMarkModel studentModel, String subjectId) {
    final subjectData = studentModel.subjectMarks[subjectId];
    if (subjectData == null) return const SizedBox(width: 60);

    int maxExamMark = subjectData.subjectDataMap['maxExamFinal'] ?? 100;

    return SizedBox(
      width: 65,
      child: TextFormField(
        controller: subjectData.controller,
        focusNode: subjectData.focusNode,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: false),
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: 'Exam',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 4,
          ),
          border: const OutlineInputBorder(),
          counterText: "",
          helperText: '/ $maxExamMark',
          helperStyle: const TextStyle(fontSize: 10, color: Colors.grey),
          errorStyle: const TextStyle(fontSize: 9, height: 0.8),
        ),
        maxLength: maxExamMark >= 100 ? 3 : 2,
        validator: (value) {
          if (value == null || value.isEmpty) return null;
          final intValue = int.tryParse(value);
          if (intValue == null) return 'Err';
          if (intValue < 0 || intValue > maxExamMark) return 'Err';
          return null;
        },
        onFieldSubmitted: (_) {
          _saveFinalMark(studentModel, subjectId);
          subjectData.focusNode.unfocus();
        },
        onEditingComplete: () {
          _saveFinalMark(studentModel, subjectId);
        },
      ),
    );
  }

  // --- Export All Final Marks to PDF ---
  Future<void> _exportFinalPdf() async {
    if (!mounted) return;
    // ... PDF generation logic (same as previous output) ...
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generating Final Marks PDF...'),
        duration: Duration(seconds: 1),
      ),
    );
    await Future.delayed(const Duration(milliseconds: 50));

    final pdf = pw.Document();
    final batchName =
        Provider.of<AppState>(context, listen: false).selectedBatchName ??
        'Batch';

    // --- Prepare Headers ---
    final List<String> fixedHeaders = ['SL', 'Name', 'USN'];
    final List<String> subjectHeaders = _subjectsForSemester.expand((subjDoc) {
      final code = subjDoc['subjectCode'] ?? 'N/A';
      return ['${code}\nIA', '${code}\nExam', '${code}\nTotal'];
    }).toList();
    final List<String> allHeaders = [...fixedHeaders, ...subjectHeaders];

    // --- Prepare Data ---
    final List<List<String>> data = _studentFinalMarks.map((studentModel) {
      int index = _studentFinalMarks.indexOf(studentModel);
      List<String> rowData = [
        (index + 1).toString(),
        studentModel.studentName,
        studentModel.studentUsn,
      ];

      for (var subjDoc in _subjectsForSemester) {
        final subjectId = subjDoc.id;
        final subjectMarkData = studentModel.subjectMarks[subjectId];
        final iaFinalStr = subjectMarkData?.iaFinal?.toStringAsFixed(1) ?? '-';
        final examFinalStr = subjectMarkData?.examFinal?.toString() ?? '-';
        final totalStr =
            subjectMarkData?.calculatedTotal?.toStringAsFixed(1) ?? '-';
        rowData.addAll([iaFinalStr, examFinalStr, totalStr]);
      }
      return rowData;
    }).toList();

    // --- Build PDF Document ---
    try {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a3.landscape,
          margin: const pw.EdgeInsets.all(24),
          header: (pw.Context pdfContext) => pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(bottom: 10.0),
            child: pw.Text(
              'Page ${pdfContext.pageNumber} of ${pdfContext.pagesCount}',
              style: pw.Theme.of(
                pdfContext,
              ).defaultTextStyle.copyWith(color: PdfColors.grey),
            ),
          ),
          build: (pw.Context pdfContext) => [
            // Title Section
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Final Marks Report - Sem $_selectedSemester',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    pw.Text('Batch: $batchName'),
                  ],
                ),
                pw.Text(
                  'Generated on: ${DateTime.now().toString().substring(0, 16)}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
            pw.Divider(height: 20),

            // Table
            pw.Table.fromTextArray(
              headers: allHeaders,
              data: data,
              border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 8,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7),
              cellHeight: 16,
              cellAlignments: {
                0: pw.Alignment.center,
                for (int i = 3; i < allHeaders.length; i++)
                  i: pw.Alignment.center,
              },
              columnWidths: {
                0: const pw.FixedColumnWidth(25),
                1: const pw.FlexColumnWidth(2.5),
                2: const pw.FixedColumnWidth(65),
                for (int i = 3; i < allHeaders.length; i++)
                  i: const pw.FlexColumnWidth(1),
              },
            ),
          ],
        ),
      );

      // --- Save or Share ---
      final pdfFileName =
          '${batchName}_Sem${_selectedSemester}_Final_Marks.pdf';
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: pdfFileName,
      );
    } catch (e) {
      print("Error generating Final PDF: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating Final PDF: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedBatchName =
        Provider.of<AppState>(context).selectedBatchName ?? 'Final Marks';

    return Scaffold(
      appBar: AppBar(
        title: Text('Final Marks - $selectedBatchName'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export Final Marks PDF',
            onPressed: _isLoading || _studentFinalMarks.isEmpty
                ? null
                : _exportFinalPdf,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // --- Semester Selection (CORRECTED) ---
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SizedBox(
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 8, // Semesters 1 to 8
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
                          _loadInitialData(); // Reload data for the new semester
                        }
                      },
                      selectedColor: Theme.of(context).primaryColor,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                      backgroundColor:
                          Theme.of(context).chipTheme.backgroundColor ??
                          Colors.grey[200],
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: isSelected
                              ? Theme.of(context).primaryColor
                              : Colors.grey,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const Divider(),
          // --- End Semester Selection ---

          // --- Marks Table ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _subjectsForSemester.isEmpty
                ? Center(
                    child: Text(
                      'No subjects found for Sem $_selectedSemester in this batch.',
                    ),
                  )
                : _studentFinalMarks.isEmpty
                ? Center(child: Text('No students found for this batch.'))
                : GestureDetector(
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(8.0),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: DataTable(
                          columnSpacing: 10,
                          headingRowHeight: 55,
                          dataRowMinHeight: 48,
                          dataRowMaxHeight: 52,
                          border: TableBorder.all(
                            color: Colors.grey.shade300,
                            width: 1,
                          ),
                          // --- Dynamic Columns ---
                          columns: [
                            const DataColumn(
                              label: Text(
                                ' Name',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const DataColumn(
                              label: Text(
                                ' USN',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            // Generate columns for each subject
                            ..._subjectsForSemester.expand((subjDoc) {
                              final code = subjDoc['subjectCode'] ?? 'N/A';
                              return [
                                DataColumn(
                                  label: Text(
                                    ' ${code}\n (IA)',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    ' ${code}\n (Exam)',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    ' ${code}\n (Total)',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ];
                            }).toList(),
                          ],
                          // --- Dynamic Rows ---
                          rows: _studentFinalMarks.map((studentModel) {
                            return DataRow(
                              cells: [
                                DataCell(
                                  SizedBox(
                                    width: 130,
                                    child: Text(
                                      studentModel.studentName,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 90,
                                    child: Text(studentModel.studentUsn),
                                  ),
                                ),
                                // Generate cells for each subject for this student
                                ..._subjectsForSemester.expand((subjDoc) {
                                  final subjectId = subjDoc.id;
                                  final subjectMarkData =
                                      studentModel.subjectMarks[subjectId];
                                  return [
                                    // IA Final (Read Only)
                                    DataCell(
                                      Center(
                                        child: Text(
                                          subjectMarkData?.iaFinal
                                                  ?.toStringAsFixed(1) ??
                                              '-',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Exam Final (Input)
                                    DataCell(
                                      _buildExamInput(studentModel, subjectId),
                                    ),
                                    // Calculated Total (Read Only)
                                    DataCell(
                                      Center(
                                        child: Text(
                                          subjectMarkData?.calculatedTotal
                                                  ?.toStringAsFixed(1) ??
                                              '-',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ];
                                }).toList(),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
