import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Imports for PDF generation
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../providers/app_state.dart';
import '../../models/student_mark_model.dart';
import '../../services/mark_calculation_service.dart';
import 'ia_question_config_screen.dart';

class MarksEntryScreen extends StatefulWidget {
  final String subjectId;
  final String subjectCode;
  final String subjectName;
  final Map<String, dynamic> subjectData;

  const MarksEntryScreen({
    super.key,
    required this.subjectId,
    required this.subjectCode,
    required this.subjectName,
    required this.subjectData,
  });

  @override
  State<MarksEntryScreen> createState() => _MarksEntryScreenState();
}

class _MarksEntryScreenState extends State<MarksEntryScreen> {
  String? _selectedBatchId;
  List<StudentMarkModel> _studentMarks = [];
  bool _isLoading = true;
  final Map<String, FocusNode> _focusNodes = {};
  // Debounce timers for auto-save (one per student)
  final Map<String, Timer> _debounceTimers = {};

  final MarkCalculationService _markCalculator = MarkCalculationService();

  /// Whether this is a 30-mark objective subject (direct IA entry, no question-wise).
  bool get _isObjectiveSubject => (widget.subjectData['baseInternalMax'] ?? 40) == 30;

  /// Track which IAs have question-wise data entered (for button indicators)
  final Map<String, bool> _iaHasData = {'ia_1': false, 'ia_2': false, 'ia_3': false};

  // --- New State Variables for Averages ---
  Map<String, double> _classAverages = {
    'ia_1': 0.0,
    'ia_2': 0.0,
    'ia_3': 0.0,
    'projectOrAssignment': 0.0,
    'iaFinal': 0.0,
  };
  // ----------------------------------------

  @override
  void initState() {
    super.initState();
    _selectedBatchId = Provider.of<AppState>(
      context,
      listen: false,
    ).selectedBatchId;
    _loadStudentMarks();
    if (!_isObjectiveSubject) {
      _checkIaDataExists();
    }
  }

  /// Check if question-wise data exists for each IA (for button indicators).
  Future<void> _checkIaDataExists() async {
    if (_selectedBatchId == null) return;
    try {
      // Just check if any ia_details doc exists for this subject
      QuerySnapshot studentSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('batchYear', isEqualTo: _selectedBatchId)
          .limit(1)
          .get();
      if (studentSnapshot.docs.isEmpty) return;

      final firstStudentId = studentSnapshot.docs.first.id;
      final detailDocId = '${firstStudentId}_${widget.subjectId}';
      DocumentSnapshot detailSnap = await FirebaseFirestore.instance
          .collection('ia_details')
          .doc(detailDocId)
          .get();

      if (detailSnap.exists && mounted) {
        final data = detailSnap.data() as Map<String, dynamic>? ?? {};
        setState(() {
          _iaHasData['ia_1'] = data.containsKey('ia_1');
          _iaHasData['ia_2'] = data.containsKey('ia_2');
          _iaHasData['ia_3'] = data.containsKey('ia_3');
        });
      }
    } catch (e) {
      print('Error checking IA data: $e');
    }
  }

  /// Navigate to the IA question config screen for a specific IA.
  void _navigateToIAConfig(String iaLabel, String iaFieldKey) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IAQuestionConfigScreen(
          iaLabel: iaLabel,
          iaFieldKey: iaFieldKey,
          subjectId: widget.subjectId,
          subjectCode: widget.subjectCode,
          subjectName: widget.subjectName,
          subjectData: widget.subjectData,
          batchId: _selectedBatchId!,
        ),
      ),
    ).then((_) {
      // Reload marks after returning from question-wise entry
      _loadStudentMarks();
      _checkIaDataExists();
    });
  }

  @override
  void dispose() {
    _debounceTimers.forEach((_, timer) => timer.cancel());
    _focusNodes.forEach((_, node) => node.dispose());
    _studentMarks.forEach((sm) {
      sm.controllers.forEach((_, controller) => controller.dispose());
    });
    super.dispose();
  }

  // --- Calculation of Class Averages ---
  void _calculateClassAverages(List<StudentMarkModel> marks) {
    if (marks.isEmpty) return;

    double sumIa1 = 0;
    double sumIa2 = 0;
    double sumIa3 = 0;
    double sumProjAssign = 0;
    double sumIaFinal = 0;
    int validStudentCount = 0;

    for (var mark in marks) {
      // Only include students where data has been attempted (e.g., has a name)
      if (mark.name.isNotEmpty) {
        validStudentCount++;
        if (mark.ia1 != null) sumIa1 += mark.ia1!;
        if (mark.ia2 != null) sumIa2 += mark.ia2!;
        if (mark.ia3 != null) sumIa3 += mark.ia3!;
        if (mark.projectOrAssignment != null)
          sumProjAssign += mark.projectOrAssignment!;
        if (mark.calculatedIaFinal != null)
          sumIaFinal += mark.calculatedIaFinal!;
      }
    }

    if (validStudentCount > 0 && mounted) {
      setState(() {
        _classAverages = {
          'ia_1': sumIa1 / validStudentCount,
          'ia_2': sumIa2 / validStudentCount,
          'ia_3': sumIa3 / validStudentCount,
          'projectOrAssignment': sumProjAssign / validStudentCount,
          'iaFinal': sumIaFinal / validStudentCount,
        };
      });
    }
  }

  // --- Load Students and their existing marks for this subject ---
  Future<void> _loadStudentMarks() async {
    if (_selectedBatchId == null) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Batch ID missing.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      QuerySnapshot studentSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('batchYear', isEqualTo: _selectedBatchId)
          .orderBy('name')
          .get();

      List<StudentMarkModel> loadedMarks = [];

      for (var studentDoc in studentSnapshot.docs) {
        final studentData = studentDoc.data() as Map<String, dynamic>;
        final studentId = studentDoc.id;
        final usn = studentData['usn'] ?? 'N/A';
        final studentName = studentData['name'] ?? 'No Name';
        final markDocId = '${studentId}_${widget.subjectId}';

        DocumentSnapshot markSnapshot = await FirebaseFirestore.instance
            .collection('marks')
            .doc(markDocId)
            .get();

        Map<String, dynamic>? markData = markSnapshot.exists
            ? markSnapshot.data() as Map<String, dynamic>
            : null;

        // Safely extract numeric values for initial calculation
        int? ia1 = markData?['ia_1'] as int?;
        int? ia2 = markData?['ia_2'] as int?;
        int? ia3 = markData?['ia_3'] as int?;
        int? projAssign = markData?['projectOrAssignment'] as int?;

        final controllers = {
          'ia_1': TextEditingController(text: ia1?.toString() ?? ''),
          'ia_2': TextEditingController(text: ia2?.toString() ?? ''),
          'ia_3': TextEditingController(text: ia3?.toString() ?? ''),
          'projectOrAssignment': TextEditingController(
            text: projAssign?.toString() ?? '',
          ),
        };

        // Create FocusNodes for input fields if they don't exist
        if (!_focusNodes.containsKey(studentId + '_ia_1')) {
          _focusNodes[studentId + '_ia_1'] = FocusNode();
          _focusNodes[studentId + '_ia_2'] = FocusNode();
          _focusNodes[studentId + '_ia_3'] = FocusNode();
          _focusNodes[studentId + '_projectOrAssignment'] = FocusNode();
        }

        // Calculate initial IA Final
        double initialCalculatedFinal = _markCalculator.calculateIaFinalLocal(
          ia1: ia1,
          ia2: ia2,
          ia3: ia3,
          projectOrAssignment: projAssign,
          subjectData: widget.subjectData,
        );

        loadedMarks.add(
          StudentMarkModel(
            studentId: studentId,
            usn: usn,
            name: studentName,
            ia1: ia1,
            ia2: ia2,
            ia3: ia3,
            projectOrAssignment: projAssign,
            calculatedIaFinal: initialCalculatedFinal,
            controllers: controllers,
            subjectData: widget.subjectData,
            markDocId: markDocId,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _studentMarks = loadedMarks;
          _isLoading = false;
        });
        // Calculate averages right after loading data
        _calculateClassAverages(loadedMarks);
      }
    } catch (e) {
      print("Error loading student marks: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- Save Marks for a specific student ---
  Future<void> _saveMarks(StudentMarkModel studentMark) async {
    // Get numeric values from controllers
    int? ia1 = int.tryParse(studentMark.controllers['ia_1']!.text);
    int? ia2 = int.tryParse(studentMark.controllers['ia_2']!.text);
    int? ia3 = int.tryParse(studentMark.controllers['ia_3']!.text);
    int? projAssign = int.tryParse(
      studentMark.controllers['projectOrAssignment']!.text,
    );

    // Quick validation check before saving
    if ((ia1 != null &&
            (ia1 < 0 || ia1 > (widget.subjectData['baseInternalMax'] ?? 40))) ||
        (ia2 != null &&
            (ia2 < 0 || ia2 > (widget.subjectData['baseInternalMax'] ?? 40))) ||
        (ia3 != null &&
            (ia3 < 0 || ia3 > (widget.subjectData['baseInternalMax'] ?? 40))) ||
        (projAssign != null &&
            (projAssign < 0 ||
                projAssign > (widget.subjectData['maxProject'] ?? 25)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Mark is outside the allowed range.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // --- Perform LOCAL Calculation ---
      double calculatedFinal = _markCalculator.calculateIaFinalLocal(
        ia1: ia1,
        ia2: ia2,
        ia3: ia3,
        projectOrAssignment: projAssign,
        subjectData: widget.subjectData, // Use subject-specific rules
      );

      // Prepare data to save
      Map<String, dynamic> dataToSave = {
        'ia_1': ia1,
        'ia_2': ia2,
        'ia_3': ia3,
        'projectOrAssignment': projAssign,
        'calculated_iaFinal':
            calculatedFinal, // Store the locally calculated result
        // --- AUTOMATION FIELDS ADDED ---
        'semester':
            widget.subjectData['semester'], // ✅ ADDED: Semester for filtering
        'sent': false, // ✅ ADDED: Automation flag (not sent yet)
        'iaType': 'IA1', // ✅ ADDED: Type of assessment

        // -----------------------------
        'batchYear': _selectedBatchId,
        'studentRef': FirebaseFirestore.instance.doc(
          'students/${studentMark.studentId}',
        ),
        'subjectRef': FirebaseFirestore.instance.doc(
          'subjects/${widget.subjectId}',
        ),
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      // Save to Firestore
      await FirebaseFirestore.instance
          .collection('marks')
          .doc(studentMark.markDocId)
          .set(dataToSave, SetOptions(merge: true));

      // Update local state and recalculate averages immediately
      if (mounted) {
        setState(() {
          final index = _studentMarks.indexWhere(
            (sm) => sm.studentId == studentMark.studentId,
          );
          if (index != -1) {
            _studentMarks[index] = studentMark.copyWith(
              ia1: ia1,
              ia2: ia2,
              ia3: ia3,
              projectOrAssignment: projAssign,
              calculatedIaFinal: calculatedFinal, // Update displayed final
            );
          }
        });
        // Recalculate class averages after a successful save
        _calculateClassAverages(_studentMarks);
        // Show subtle save indicator
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${studentMark.name} marks saved.'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      print("Error saving marks for ${studentMark.name}: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error saving marks for ${studentMark.name}: ${e.toString()}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- Helper to build input fields ---
  Widget _buildMarkInput(
    StudentMarkModel studentMark,
    String fieldKey,
    int maxMark,
  ) {
    String label;
    TextInputAction action;
    FocusNode currentFocusNode =
        _focusNodes[studentMark.studentId + '_' + fieldKey]!;
    FocusNode? nextFocusNode;

    switch (fieldKey) {
      case 'ia_1':
        label = 'IA 1';
        action = TextInputAction.next;
        nextFocusNode = _focusNodes[studentMark.studentId + '_ia_2'];
        break;
      case 'ia_2':
        label = 'IA 2';
        action = TextInputAction.next;
        nextFocusNode = _focusNodes[studentMark.studentId + '_ia_3'];
        break;
      case 'ia_3':
        label = 'IA 3';
        action = TextInputAction.next;
        nextFocusNode =
            _focusNodes[studentMark.studentId + '_projectOrAssignment'];
        break;
      case 'projectOrAssignment':
        label = widget.subjectData['iaCalculationRule'] == 'SEM_5_6_SCHEMA'
            ? 'Proj'
            : 'Asgn';
        action = TextInputAction.done;
        break;
      default:
        label = '?';
        action = TextInputAction.done;
    }

    return SizedBox(
      width: 70,
      child: TextFormField(
        controller: studentMark.controllers[fieldKey],
        focusNode: currentFocusNode,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: false),
        textInputAction: action,
        decoration: InputDecoration(
          hintText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 4,
          ),
          border: const OutlineInputBorder(),
          counterText: "",
          helperText: '/ $maxMark',
          helperStyle: const TextStyle(fontSize: 10, color: Colors.grey),
          errorStyle: const TextStyle(fontSize: 9, height: 0.8),
        ),
        maxLength: maxMark >= 100 ? 3 : 2,
        validator: (value) {
          if (value == null || value.isEmpty) return null;
          final intValue = int.tryParse(value);
          if (intValue == null) return 'Err';
          if (intValue < 0 || intValue > maxMark) return 'Err';
          return null;
        },
        onChanged: (value) {
          // Trigger a preview calculation on every change
          setState(() {
            double previewFinal = _markCalculator.calculateIaFinalLocal(
              ia1: int.tryParse(studentMark.controllers['ia_1']!.text),
              ia2: int.tryParse(studentMark.controllers['ia_2']!.text),
              ia3: int.tryParse(studentMark.controllers['ia_3']!.text),
              projectOrAssignment: int.tryParse(
                studentMark.controllers['projectOrAssignment']!.text,
              ),
              subjectData: widget.subjectData,
            );
            final index = _studentMarks.indexWhere(
              (sm) => sm.studentId == studentMark.studentId,
            );
            if (index != -1) {
              _studentMarks[index] = _studentMarks[index].copyWith(
                calculatedIaFinal: previewFinal,
                ia1: int.tryParse(studentMark.controllers['ia_1']!.text),
                ia2: int.tryParse(studentMark.controllers['ia_2']!.text),
                ia3: int.tryParse(studentMark.controllers['ia_3']!.text),
                projectOrAssignment: int.tryParse(
                  studentMark.controllers['projectOrAssignment']!.text,
                ),
              );
            }
            _calculateClassAverages(_studentMarks);
          });
          
          // Auto-save with debounce (1.5 seconds after last keystroke)
          _debounceTimers[studentMark.studentId]?.cancel();
          _debounceTimers[studentMark.studentId] = Timer(
            const Duration(milliseconds: 1500),
            () => _saveMarks(studentMark),
          );
        },
        onFieldSubmitted: (_) {
          // Cancel pending debounce and save immediately
          _debounceTimers[studentMark.studentId]?.cancel();
          _saveMarks(studentMark);
          if (action == TextInputAction.done) {
            currentFocusNode.unfocus();
          } else if (nextFocusNode != null) {
            FocusScope.of(context).requestFocus(nextFocusNode);
          }
        },
      ),
    );
  }

  /// Read-only display for IA1/IA2/IA3 when using question-wise entry.
  Widget _buildReadOnlyIaCell(StudentMarkModel studentMark, String fieldKey) {
    final value = studentMark.controllers[fieldKey]?.text ?? '';
    return SizedBox(
      width: 70,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: value.isNotEmpty ? Colors.green.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: value.isNotEmpty ? Colors.green.shade300 : Colors.grey.shade300,
          ),
        ),
        child: Text(
          value.isNotEmpty ? value : '-',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: value.isNotEmpty ? FontWeight.bold : FontWeight.normal,
            color: value.isNotEmpty ? Colors.green.shade700 : Colors.grey,
          ),
        ),
      ),
    );
  }

  /// Build the IA1/IA2/IA3 button bar for question-wise entry.
  Widget _buildIaButtonBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        children: [
          const Text(
            'Enter Detailed Marks: ',
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
          const SizedBox(width: 8),
          _buildIaButton('IA1', 'ia_1'),
          const SizedBox(width: 8),
          _buildIaButton('IA2', 'ia_2'),
          const SizedBox(width: 8),
          _buildIaButton('IA3', 'ia_3'),
        ],
      ),
    );
  }

  Widget _buildIaButton(String label, String fieldKey) {
    final hasData = _iaHasData[fieldKey] ?? false;
    return FilledButton.icon(
      onPressed: () => _navigateToIAConfig(label, fieldKey),
      icon: Icon(
        hasData ? Icons.check_circle : Icons.edit_note,
        size: 18,
      ),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: hasData
            ? Colors.green.shade600
            : Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
  }

  // --- Export All Student Marks to PDF ---
  Future<void> _exportPdf() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generating PDF...'),
        duration: Duration(seconds: 1),
      ),
    );
    await Future.delayed(const Duration(milliseconds: 50));

    final pdf = pw.Document();
    final batchName =
        Provider.of<AppState>(context, listen: false).selectedBatchName ??
        'Unknown Batch';
    final semester = widget.subjectData['semester'] ?? '?';

    // --- Define Table Headers ---
    final String iaRule = widget.subjectData['iaCalculationRule'] ?? 'DEFAULT';
    final int maxIA = widget.subjectData['baseInternalMax'] ?? 25;
    int maxProjAssign = 0;
    String projAssignHeader = 'Assign';

    if (iaRule == 'SEM_5_6_SCHEMA') {
      maxProjAssign = widget.subjectData['maxProject'] ?? 25;
      projAssignHeader = 'Project';
    } else if (iaRule == 'SEM_SPECIAL_100_MARK_SCHEMA') {
      maxProjAssign = widget.subjectData['maxProject'] ?? 25;
      projAssignHeader = 'Project';
    } else if (iaRule == 'BEST_2_OF_3_AVG') {
      maxProjAssign = widget.subjectData['maxAssignment'] ?? 10;
      projAssignHeader = 'Assign';
    }

    final List<String> headers = [
      'SL',
      'Name',
      'USN',
      'IA 1\n(/$maxIA)',
      'IA 2\n(/$maxIA)',
      'IA 3\n(/$maxIA)',
      '$projAssignHeader\n(/$maxProjAssign)',
      'IA Final\n(/50)',
    ];

    // --- Prepare Table Data ---
    final List<List<String>> data = _studentMarks.map((studentMark) {
      int index = _studentMarks.indexOf(studentMark);
      String ia1Text = studentMark.controllers['ia_1']!.text;
      String ia2Text = studentMark.controllers['ia_2']!.text;
      String ia3Text = studentMark.controllers['ia_3']!.text;
      String projText = studentMark.controllers['projectOrAssignment']!.text;

      return [
        (index + 1).toString(),
        studentMark.name,
        studentMark.usn,
        ia1Text.isEmpty ? '-' : ia1Text,
        ia2Text.isEmpty ? '-' : ia2Text,
        ia3Text.isEmpty ? '-' : ia3Text,
        projText.isEmpty ? '-' : projText,
        studentMark.calculatedIaFinal?.toStringAsFixed(1) ?? '-',
      ];
    }).toList();

    // --- Build PDF Document ---
    try {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
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
                      '${widget.subjectCode} - ${widget.subjectName}',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    pw.Text(
                      'Batch: $batchName | Semester: ${widget.subjectData['semester']}',
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                pw.Text('IA Marks Report', style: pw.TextStyle(fontSize: 14)),
              ],
            ),
            pw.Divider(height: 20),

            // Table
            pw.Table.fromTextArray(
              headers: headers,
              data: data,
              border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7),
              cellHeight: 18,
              cellAlignments: {
                0: pw.Alignment.center,
                3: pw.Alignment.center,
                4: pw.Alignment.center,
                5: pw.Alignment.center,
                6: pw.Alignment.center,
                7: pw.Alignment.center,
              },
              columnWidths: {
                0: const pw.FixedColumnWidth(25),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FixedColumnWidth(75),
                3: const pw.FixedColumnWidth(45),
                4: const pw.FixedColumnWidth(45),
                5: const pw.FixedColumnWidth(45),
                6: const pw.FixedColumnWidth(55),
                7: const pw.FixedColumnWidth(55),
              },
            ),
            pw.SizedBox(height: 30),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text(
                  'Generated on: ${DateTime.now().toString().substring(0, 16)}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          ],
        ),
      );

      // --- Save or Share ---
      final pdfFileName =
          '${widget.subjectCode}_${batchName}_Sem${widget.subjectData['semester']}_IA_Marks.pdf';
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: pdfFileName,
      );
    } catch (e) {
      print("Error generating PDF: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating PDF: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine max marks from subjectData based on rules
    final String iaRule =
        widget.subjectData['iaCalculationRule'] ?? 'DEFAULT_RULE';
    final int maxIA = widget.subjectData['baseInternalMax'] ?? 40;
    int maxProjAssign = 0;
    String projAssignLabel = 'Assign';

    if (iaRule == 'SEM_5_6_SCHEMA') {
      maxProjAssign = widget.subjectData['maxProject'] ?? 25;
      projAssignLabel = 'Project';
    } else if (iaRule == 'SEM_SPECIAL_100_MARK_SCHEMA') {
      maxProjAssign = widget.subjectData['maxProject'] ?? 25;
      projAssignLabel = 'Project';
    } else if (iaRule == 'BEST_2_OF_3_AVG') {
      maxProjAssign = widget.subjectData['maxAssignment'] ?? 10;
      projAssignLabel = 'Assign';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.subjectCode} - Marks Entry',
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export as PDF',
            onPressed: _isLoading || _studentMarks.isEmpty ? null : _exportPdf,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _studentMarks.isEmpty
          ? const Center(child: Text('No students found for this batch.'))
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(8.0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- IA BUTTON BAR (for non-objective subjects) ---
                      if (!_isObjectiveSubject) _buildIaButtonBar(),

                      // --- STATS ROW (The New Feature) ---
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4.0,
                          vertical: 8.0,
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 150),
                            _buildAveragePill(
                              'IA 1 Avg',
                              _classAverages['ia_1']!,
                            ),
                            _buildAveragePill(
                              'IA 2 Avg',
                              _classAverages['ia_2']!,
                            ),
                            _buildAveragePill(
                              'IA 3 Avg',
                              _classAverages['ia_3']!,
                            ),
                            _buildAveragePill(
                              '$projAssignLabel Avg',
                              _classAverages['projectOrAssignment']!,
                            ),
                            _buildAveragePill(
                              'IA Final Avg',
                              _classAverages['iaFinal']!,
                            ),
                          ],
                        ),
                      ),

                      // ------------------------------------
                      DataTable(
                        columnSpacing: 12,
                        headingRowHeight: 50,
                        dataRowMinHeight: 48,
                        dataRowMaxHeight: 52,
                        border: TableBorder.all(
                          color: Colors.grey.shade400,
                          width: 1,
                        ),
                        columns: [
                          const DataColumn(
                            label: Text(
                              ' Name',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              ' IA 1\n (/$maxIA)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              ' IA 2\n (/$maxIA)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              ' IA 3\n (/$maxIA)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              ' $projAssignLabel\n (/$maxProjAssign)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const DataColumn(
                            label: Text(
                              ' IA Final\n (/50)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                        rows: _studentMarks.map((studentMark) {
                          return DataRow(
                            cells: [
                              DataCell(
                                SizedBox(
                                  width: 150,
                                  child: Text(
                                    studentMark.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              // IA1/IA2/IA3: read-only for question-wise, editable for objective
                              DataCell(
                                _isObjectiveSubject
                                    ? _buildMarkInput(studentMark, 'ia_1', maxIA)
                                    : _buildReadOnlyIaCell(studentMark, 'ia_1'),
                              ),
                              DataCell(
                                _isObjectiveSubject
                                    ? _buildMarkInput(studentMark, 'ia_2', maxIA)
                                    : _buildReadOnlyIaCell(studentMark, 'ia_2'),
                              ),
                              DataCell(
                                _isObjectiveSubject
                                    ? _buildMarkInput(studentMark, 'ia_3', maxIA)
                                    : _buildReadOnlyIaCell(studentMark, 'ia_3'),
                              ),
                              DataCell(
                                _buildMarkInput(
                                  studentMark,
                                  'projectOrAssignment',
                                  maxProjAssign,
                                ),
                              ),
                              DataCell(
                                Center(
                                  child: Text(
                                    studentMark.calculatedIaFinal
                                            ?.toStringAsFixed(1) ??
                                        '-',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // --- New Widget for Average Display ---
  Widget _buildAveragePill(String title, double average) {
    return Container(
      width: 70, // Matches input column width
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Tooltip(
        message: title,
        child: Text(
          average.toStringAsFixed(1), // Show average to 1 decimal place
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade800,
          ),
        ),
      ),
    );
  }
}
