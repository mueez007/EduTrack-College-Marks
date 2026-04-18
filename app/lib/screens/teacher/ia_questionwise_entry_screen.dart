import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// PDF
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../services/mark_calculation_service.dart';
import 'ia_question_config_screen.dart';

/// Screen for entering question-wise marks for a specific IA (IA1/IA2/IA3).
///
/// Displays a scrollable table with:
/// - Rows: one per student
/// - Columns: one per question (or sub-question)
/// - Auto-calculated IA total using paired-section best-pair logic
///
/// Saves detailed marks to `ia_details` collection and writes the
/// calculated total back to `marks` collection for downstream calculations.
class IAQuestionwiseEntryScreen extends StatefulWidget {
  final String iaLabel;       // "IA1", "IA2", "IA3"
  final String iaFieldKey;    // "ia_1", "ia_2", "ia_3"
  final String subjectId;
  final String subjectCode;
  final String subjectName;
  final Map<String, dynamic> subjectData;
  final String batchId;
  final Map<String, dynamic> config;

  const IAQuestionwiseEntryScreen({
    super.key,
    required this.iaLabel,
    required this.iaFieldKey,
    required this.subjectId,
    required this.subjectCode,
    required this.subjectName,
    required this.subjectData,
    required this.batchId,
    required this.config,
  });

  @override
  State<IAQuestionwiseEntryScreen> createState() =>
      _IAQuestionwiseEntryScreenState();
}

class _IAQuestionwiseEntryScreenState extends State<IAQuestionwiseEntryScreen> {
  bool _isLoading = true;
  bool _isSaving = false;

  // Student data
  List<_StudentEntry> _students = [];

  // Derived from config
  late int _numQuestions;
  late int _numSubQuestions; // 0 if none
  late int _maxMarks;        // per question or per sub-question
  late List<int> _sectionA;
  late List<int> _sectionB;
  late List<List<int>> _pairsA;
  late List<List<int>> _pairsB;

  // Column keys: e.g. "q1", "q2" or "q1a", "q1b", "q2a", "q2b"
  late List<String> _columnKeys;

  // Debounce timers per student
  final Map<String, Timer> _debounceTimers = {};

  final MarkCalculationService _markCalculator = MarkCalculationService();

  @override
  void initState() {
    super.initState();
    _parseConfig();
    _loadStudents();
  }

  @override
  void dispose() {
    _debounceTimers.forEach((_, t) => t.cancel());
    for (var student in _students) {
      for (var controller in student.controllers.values) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  void _parseConfig() {
    _numQuestions = widget.config['numQuestions'] as int;
    _numSubQuestions = widget.config['numSubQuestions'] as int;
    _maxMarks = widget.config['maxMarksPerQuestion'] as int;

    _sectionA = List<int>.from(widget.config['sectionA'] as List);
    _sectionB = List<int>.from(widget.config['sectionB'] as List);
    _pairsA = (widget.config['pairsA'] as List)
        .map((p) => List<int>.from(p as List))
        .toList();
    _pairsB = (widget.config['pairsB'] as List)
        .map((p) => List<int>.from(p as List))
        .toList();

    // Build column keys
    _columnKeys = [];
    for (int q = 1; q <= _numQuestions; q++) {
      if (_numSubQuestions > 0) {
        for (int s = 0; s < _numSubQuestions; s++) {
          _columnKeys.add('q$q${String.fromCharCode(97 + s)}');
        }
      } else {
        _columnKeys.add('q$q');
      }
    }
  }

  Future<void> _loadStudents() async {
    setState(() => _isLoading = true);
    try {
      QuerySnapshot studentSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('batchYear', isEqualTo: widget.batchId)
          .orderBy('name')
          .get();

      List<_StudentEntry> entries = [];

      for (var doc in studentSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final studentId = doc.id;
        final name = data['name'] ?? 'No Name';
        final usn = data['usn'] ?? 'N/A';

        // Check for existing detailed marks
        final detailDocId = '${studentId}_${widget.subjectId}';
        DocumentSnapshot detailSnapshot = await FirebaseFirestore.instance
            .collection('ia_details')
            .doc(detailDocId)
            .get();

        Map<String, dynamic>? existingMarks;
        if (detailSnapshot.exists) {
          final detailData = detailSnapshot.data() as Map<String, dynamic>?;
          final iaData = detailData?[widget.iaFieldKey] as Map<String, dynamic>?;
          existingMarks = iaData?['marks'] as Map<String, dynamic>?;
        }

        // Build controllers
        Map<String, TextEditingController> controllers = {};
        for (var key in _columnKeys) {
          final existingVal = existingMarks?[key];
          controllers[key] = TextEditingController(
            text: existingVal?.toString() ?? '',
          );
        }

        entries.add(_StudentEntry(
          studentId: studentId,
          name: name,
          usn: usn,
          controllers: controllers,
          calculatedTotal: 0,
        ));
      }

      // Calculate initial totals
      for (var student in entries) {
        student.calculatedTotal = _calculateStudentTotal(student);
      }

      if (mounted) {
        setState(() {
          _students = entries;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading students for question-wise entry: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading students: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Calculate the IA total for a student using paired-section best-pair logic.
  int _calculateStudentTotal(_StudentEntry student) {
    Map<int, int> questionMarks = {};
    for (int q = 1; q <= _numQuestions; q++) {
      int total = 0;
      if (_numSubQuestions > 0) {
        for (int s = 0; s < _numSubQuestions; s++) {
          final key = 'q$q${String.fromCharCode(97 + s)}';
          total += int.tryParse(student.controllers[key]?.text ?? '') ?? 0;
        }
      } else {
        final key = 'q$q';
        total = int.tryParse(student.controllers[key]?.text ?? '') ?? 0;
      }
      questionMarks[q] = total;
    }

    int bestA = _findBestPairTotal(_pairsA, questionMarks);
    int bestB = _findBestPairTotal(_pairsB, questionMarks);

    return bestA + bestB;
  }

  int _findBestPairTotal(List<List<int>> pairs, Map<int, int> questionMarks) {
    int best = 0;
    for (var pair in pairs) {
      int pairTotal = 0;
      for (var q in pair) {
        pairTotal += questionMarks[q] ?? 0;
      }
      if (pairTotal > best) {
        best = pairTotal;
      }
    }
    return best;
  }

  /// Save marks for a single student — NO nested arrays in Firestore.
  Future<void> _saveStudentMarks(_StudentEntry student) async {
    final detailDocId = '${student.studentId}_${widget.subjectId}';

    // Build marks map (flat: key -> int)
    Map<String, dynamic> marks = {};
    for (var key in _columnKeys) {
      final val = int.tryParse(student.controllers[key]?.text ?? '');
      if (val != null) {
        marks[key] = val;
      }
    }

    final int calculatedTotal = _calculateStudentTotal(student);

    try {
      // Save detailed marks to ia_details — flat structure, no nested arrays
      await FirebaseFirestore.instance
          .collection('ia_details')
          .doc(detailDocId)
          .set({
        widget.iaFieldKey: {
          'numQuestions': _numQuestions,
          'numSubQuestions': _numSubQuestions,
          'maxMarksPerQuestion': _maxMarks,
          'marks': marks,
          'calculatedTotal': calculatedTotal,
          'lastUpdated': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      // Write calculated total to main marks collection
      final markDocId = '${student.studentId}_${widget.subjectId}';

      // First read existing marks to recalculate IA final
      DocumentSnapshot existingMarkSnap = await FirebaseFirestore.instance
          .collection('marks')
          .doc(markDocId)
          .get();

      Map<String, dynamic> existingData = existingMarkSnap.exists
          ? (existingMarkSnap.data() as Map<String, dynamic>? ?? {})
          : {};

      // Update the specific IA field
      existingData[widget.iaFieldKey] = calculatedTotal;

      // Recalculate IA final with the new value
      int? ia1 = widget.iaFieldKey == 'ia_1' ? calculatedTotal : (existingData['ia_1'] as int?);
      int? ia2 = widget.iaFieldKey == 'ia_2' ? calculatedTotal : (existingData['ia_2'] as int?);
      int? ia3 = widget.iaFieldKey == 'ia_3' ? calculatedTotal : (existingData['ia_3'] as int?);
      int? projAssign = existingData['projectOrAssignment'] as int?;

      double calculatedFinal = _markCalculator.calculateIaFinalLocal(
        ia1: ia1,
        ia2: ia2,
        ia3: ia3,
        projectOrAssignment: projAssign,
        subjectData: widget.subjectData,
      );

      await FirebaseFirestore.instance
          .collection('marks')
          .doc(markDocId)
          .set({
        widget.iaFieldKey: calculatedTotal,
        'calculated_iaFinal': calculatedFinal,
        'batchYear': widget.batchId,
        'studentRef': FirebaseFirestore.instance.doc('students/${student.studentId}'),
        'subjectRef': FirebaseFirestore.instance.doc('subjects/${widget.subjectId}'),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error saving question-wise marks for ${student.name}: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving ${student.name}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Save all students' marks at once.
  Future<void> _saveAllMarks() async {
    setState(() => _isSaving = true);
    int savedCount = 0;

    for (var student in _students) {
      bool hasData = student.controllers.values.any((c) => c.text.isNotEmpty);
      if (hasData) {
        await _saveStudentMarks(student);
        savedCount++;
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved $savedCount student(s) marks for ${widget.iaLabel}.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  String _getSection(int questionNum) {
    if (_sectionA.contains(questionNum)) return 'A';
    return 'B';
  }

  List<int>? _findBestPair(List<List<int>> pairs, _StudentEntry student) {
    Map<int, int> questionMarks = {};
    for (int q = 1; q <= _numQuestions; q++) {
      int total = 0;
      if (_numSubQuestions > 0) {
        for (int s = 0; s < _numSubQuestions; s++) {
          final key = 'q$q${String.fromCharCode(97 + s)}';
          total += int.tryParse(student.controllers[key]?.text ?? '') ?? 0;
        }
      } else {
        total = int.tryParse(student.controllers['q$q']?.text ?? '') ?? 0;
      }
      questionMarks[q] = total;
    }

    List<int>? bestPair;
    int bestTotal = -1;
    for (var pair in pairs) {
      int pairTotal = 0;
      for (var q in pair) {
        pairTotal += questionMarks[q] ?? 0;
      }
      if (pairTotal > bestTotal) {
        bestTotal = pairTotal;
        bestPair = pair;
      }
    }
    return bestPair;
  }

  // ======================== RECONFIGURE ========================

  /// Delete the saved config and go back to the config wizard.
  Future<void> _reconfigure() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reconfigure Questions?'),
        content: const Text(
          'This will reset the question paper setup for this IA. '
          'Existing marks will be kept but the pairing structure will change.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reconfigure'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Delete the saved config from Firestore
    try {
      await FirebaseFirestore.instance
          .collection('ia_configs')
          .doc('${widget.subjectId}_${widget.iaFieldKey}')
          .delete();
    } catch (e) {
      print('Error deleting config: $e');
    }

    if (!mounted) return;

    // Navigate to config screen (replacing this screen)
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => IAQuestionConfigScreen(
          iaLabel: widget.iaLabel,
          iaFieldKey: widget.iaFieldKey,
          subjectId: widget.subjectId,
          subjectCode: widget.subjectCode,
          subjectName: widget.subjectName,
          subjectData: widget.subjectData,
          batchId: widget.batchId,
        ),
      ),
    );
  }

  // ======================== PDF EXPORT ========================

  Future<void> _exportPdf() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating PDF...'), duration: Duration(seconds: 1)),
    );
    await Future.delayed(const Duration(milliseconds: 50));

    final pdf = pw.Document();
    final semester = widget.subjectData['semester'] ?? '?';

    // Build headers
    List<String> headers = ['SL', 'Name', 'USN'];
    for (int q = 1; q <= _numQuestions; q++) {
      if (_numSubQuestions > 0) {
        for (int s = 0; s < _numSubQuestions; s++) {
          headers.add('Q$q${String.fromCharCode(97 + s)}');
        }
      } else {
        headers.add('Q$q');
      }
    }
    headers.add('Total');

    // Build data
    List<List<String>> data = [];
    for (int i = 0; i < _students.length; i++) {
      final student = _students[i];
      List<String> row = [
        '${i + 1}',
        student.name,
        student.usn,
      ];
      for (var key in _columnKeys) {
        final text = student.controllers[key]?.text ?? '';
        row.add(text.isEmpty ? '-' : text);
      }
      row.add('${student.calculatedTotal}');
      data.add(row);
    }

    try {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          header: (pw.Context ctx) => pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(
              'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: pw.Theme.of(ctx).defaultTextStyle.copyWith(color: PdfColors.grey),
            ),
          ),
          build: (pw.Context ctx) => [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${widget.subjectCode} - ${widget.subjectName}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
                ),
                pw.Text('${widget.iaLabel} Question-wise Marks | Semester: $semester'),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Questions: $_numQuestions | Sub-Qs: ${_numSubQuestions > 0 ? _numSubQuestions : "None"} | Max marks: $_maxMarks',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
            pw.Divider(height: 16),
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: data,
              border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellStyle: const pw.TextStyle(fontSize: 6),
              cellHeight: 16,
              cellAlignments: {
                for (int i = 0; i < headers.length; i++)
                  i: i <= 2 ? pw.Alignment.centerLeft : pw.Alignment.center,
              },
            ),
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text(
                  'Generated on: ${DateTime.now().toString().substring(0, 16)}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
          ],
        ),
      );

      final pdfFileName = '${widget.subjectCode}_${widget.iaLabel}_QuestionWise_Marks.pdf';
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: pdfFileName,
      );
    } catch (e) {
      print('Error generating PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating PDF: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ======================== BUILD ========================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.iaLabel} — ${widget.subjectCode}',
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: theme.colorScheme.inversePrimary,
        actions: [
          if (!_isLoading && _students.isNotEmpty) ...[
            // Reconfigure button
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'reconfigure') {
                  _reconfigure();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'reconfigure',
                  child: ListTile(
                    leading: Icon(Icons.settings, size: 20),
                    title: Text('Reconfigure Questions'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            // PDF export button
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Export PDF',
              onPressed: _isSaving ? null : _exportPdf,
            ),
            // Save all button
            _isSaving
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: _saveAllMarks,
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('Save All'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _students.isEmpty
              ? const Center(child: Text('No students found for this batch.'))
              : GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: Column(
                    children: [
                      _buildConfigBar(theme),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            padding: const EdgeInsets.all(8),
                            child: _buildMarksTable(theme),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildConfigBar(ThemeData theme) {
    final subQText = _numSubQuestions > 0
        ? '$_numSubQuestions sub-Qs each'
        : 'No sub-questions';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          _configChip(Icons.quiz, '$_numQuestions Questions'),
          _configChip(Icons.list, subQText),
          _configChip(Icons.star, 'Max $_maxMarks marks'),
          _configChip(Icons.view_column, 'Sec A: Q${_sectionA.first}–Q${_sectionA.last}'),
          _configChip(Icons.view_column, 'Sec B: Q${_sectionB.first}–Q${_sectionB.last}'),
        ],
      ),
    );
  }

  Widget _configChip(IconData icon, String text) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildMarksTable(ThemeData theme) {
    List<DataColumn> columns = [
      const DataColumn(
        label: SizedBox(
          width: 140,
          child: Text('Student', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    ];

    for (int q = 1; q <= _numQuestions; q++) {
      if (_numSubQuestions > 0) {
        for (int s = 0; s < _numSubQuestions; s++) {
          final subLabel = String.fromCharCode(97 + s);
          final section = _getSection(q);
          columns.add(DataColumn(
            label: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sec $section',
                  style: TextStyle(
                    fontSize: 9,
                    color: section == 'A' ? Colors.blue : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Q$q$subLabel',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                Text(
                  '/$_maxMarks',
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                ),
              ],
            ),
          ));
        }
      } else {
        final section = _getSection(q);
        columns.add(DataColumn(
          label: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sec $section',
                style: TextStyle(
                  fontSize: 9,
                  color: section == 'A' ? Colors.blue : Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Q$q',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              Text(
                '/$_maxMarks',
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
            ],
          ),
        ));
      }
    }

    columns.add(const DataColumn(
      label: Text(
        'Total',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      ),
    ));

    List<DataRow> rows = _students.asMap().entries.map((entry) {
      final int idx = entry.key;
      final student = entry.value;
      List<DataCell> cells = [];

      cells.add(DataCell(
        SizedBox(
          width: 140,
          child: Text(
            student.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ));

      final bestPairA = _findBestPair(_pairsA, student);
      final bestPairB = _findBestPair(_pairsB, student);

      for (int q = 1; q <= _numQuestions; q++) {
        final bool isInBestPair =
            (bestPairA?.contains(q) ?? false) ||
            (bestPairB?.contains(q) ?? false);

        if (_numSubQuestions > 0) {
          for (int s = 0; s < _numSubQuestions; s++) {
            final key = 'q$q${String.fromCharCode(97 + s)}';
            cells.add(DataCell(
              _buildMarkInput(student, key, isInBestPair),
            ));
          }
        } else {
          final key = 'q$q';
          cells.add(DataCell(
            _buildMarkInput(student, key, isInBestPair),
          ));
        }
      }

      cells.add(DataCell(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${student.calculatedTotal}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ));

      return DataRow(
        color: WidgetStatePropertyAll(
          idx.isEven ? Colors.transparent : Colors.grey.withValues(alpha: 0.05),
        ),
        cells: cells,
      );
    }).toList();

    return DataTable(
      columnSpacing: 4,
      horizontalMargin: 8,
      headingRowHeight: 56,
      dataRowMinHeight: 40,
      dataRowMaxHeight: 44,
      border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
      columns: columns,
      rows: rows,
    );
  }

  Widget _buildMarkInput(
    _StudentEntry student,
    String key,
    bool isInBestPair,
  ) {
    return SizedBox(
      width: 48,
      child: TextField(
        controller: student.controllers[key],
        keyboardType: const TextInputType.numberWithOptions(decimal: false),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isInBestPair ? FontWeight.bold : FontWeight.normal,
          color: isInBestPair ? Colors.green.shade700 : null,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(
              color: isInBestPair ? Colors.green.shade300 : Colors.grey.shade400,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(
              color: isInBestPair ? Colors.green.shade300 : Colors.grey.shade300,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          filled: isInBestPair,
          fillColor: isInBestPair ? Colors.green.withValues(alpha: 0.08) : null,
          counterText: '',
        ),
        maxLength: _maxMarks >= 10 ? 2 : 1,
        onChanged: (value) {
          final intVal = int.tryParse(value);
          if (value.isNotEmpty && (intVal == null || intVal < 0 || intVal > _maxMarks)) {
            return;
          }

          // Recalculate total
          setState(() {
            student.calculatedTotal = _calculateStudentTotal(student);
          });

          // Debounce auto-save (1.5s after last keystroke)
          _debounceTimers[student.studentId]?.cancel();
          _debounceTimers[student.studentId] = Timer(
            const Duration(milliseconds: 1500),
            () => _saveStudentMarks(student),
          );
        },
      ),
    );
  }
}

/// Internal model for student entry in the question-wise table.
class _StudentEntry {
  final String studentId;
  final String name;
  final String usn;
  final Map<String, TextEditingController> controllers;
  int calculatedTotal;

  _StudentEntry({
    required this.studentId,
    required this.name,
    required this.usn,
    required this.controllers,
    required this.calculatedTotal,
  });
}
