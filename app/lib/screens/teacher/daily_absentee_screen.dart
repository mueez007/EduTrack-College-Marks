import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

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
  Map<String, int> _absentClassCounts = {};
  int _classCount = 1;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isExporting = false;
  bool _isExportingDatewise = false;

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
    _absentClassCounts.clear();
    _classCount = 1;

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
        final Map<String, int> absentCounts =
            _parseAbsentClassCountsFromDoc(data);
        final int classCount = (data['classCount'] is int)
            ? data['classCount'] as int
            : 1;
        setState(() {
          _absentClassCounts = absentCounts;
          _classCount = classCount < 1 ? 1 : classCount;
        });
      } else {
        setState(() {
          _absentClassCounts.clear();
          _classCount = 1;
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

    setState(() => _isSaving = true);

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final absenteeDocId = '${_selectedBatchId}_${_selectedSubjectId}_$dateStr';
    final subject = _subjects.firstWhere((s) => s.id == _selectedSubjectId);

    try {
      final absentStudentIds = _absentClassCounts.entries
          .where((entry) => entry.value > 0)
          .map((entry) => entry.key)
          .toList();

      // Prepare absent student details
      List<Map<String, dynamic>> absentDetails = [];
      for (var studentId in absentStudentIds) {
        final student = _students.firstWhere((s) => s.id == studentId);
        absentDetails.add({
          'studentId': studentId,
          'usn': student.usn,
          'name': student.name,
          'absentClasses': _absentClassCounts[studentId] ?? 0,
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
        'absentStudents': absentStudentIds,
        'absentClassCounts': _absentClassCounts,
        'absentDetails': absentDetails,
        'absentCount': absentStudentIds.length,
        'classCount': _classCount,
        'sent': false, // For automation
        'sentAt': null,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _refreshMonthlyAttendanceSummary();

      if (!mounted) return;
      setState(() => _isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved $_classCount class(es), ${_getAbsentStudentCount()} absent student(s)',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() => _isSaving = false);
      _showError('Failed to save: $e');
    }
  }

  Future<void> _refreshMonthlyAttendanceSummary() async {
    if (_selectedBatchId == null || _selectedSubjectId == null) return;
    final int month = _selectedDate.month;
    final int year = _selectedDate.year;
    final List<QueryDocumentSnapshot> absenteeDocs =
        await _loadMonthlyAbsenteeDocs(month: month, year: year);

    int totalClasses = 0;
    final Map<String, int> absentCounts = <String, int>{};

    for (final doc in absenteeDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final int classCount = (data['classCount'] is int)
          ? data['classCount'] as int
          : 1;
      final int normalizedClassCount = classCount < 1 ? 1 : classCount;
      totalClasses += normalizedClassCount;
      final Map<String, int> dayAbsentCounts = _parseAbsentClassCountsFromDoc(
        data,
        defaultClassCount: normalizedClassCount,
      );
      for (final entry in dayAbsentCounts.entries) {
        if (entry.value > 0) {
          absentCounts[entry.key] = (absentCounts[entry.key] ?? 0) + entry.value;
        }
      }
    }

    final subject = _subjects.firstWhere((s) => s.id == _selectedSubjectId);
    final WriteBatch batch = FirebaseFirestore.instance.batch();
    for (final student in _students) {
      final int absents = absentCounts[student.id] ?? 0;
      final int presents = totalClasses - absents;
      final double percentage =
          totalClasses == 0 ? 100 : (presents / totalClasses) * 100;
      final String attendanceDocId =
          '${student.id}_${_selectedSubjectId}_S${_selectedSemester}_M$month'
          '_Y$year';
      final docRef = FirebaseFirestore.instance
          .collection('attendanceMonthly')
          .doc(attendanceDocId);
      batch.set(docRef, {
        'studentId': student.id,
        'usn': student.usn,
        'name': student.name,
        'batchYear': _selectedBatchId,
        'semester': _selectedSemester,
        'subjectId': _selectedSubjectId,
        'subjectName': subject.name,
        'subjectCode': subject.code,
        'month': month,
        'year': year,
        'totalClasses': totalClasses,
        'attendedClasses': presents,
        'absentClasses': absents,
        'percentage': double.parse(percentage.toStringAsFixed(2)),
        'sent': false,
        'sentAt': null,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<List<AttendanceReportRow>> _buildMonthlyAttendanceRows() async {
    if (_selectedBatchId == null || _selectedSubjectId == null) {
      return <AttendanceReportRow>[];
    }
    final int month = _selectedDate.month;
    final int year = _selectedDate.year;
    final List<QueryDocumentSnapshot> absenteeDocs =
        await _loadMonthlyAbsenteeDocs(month: month, year: year);

    int totalClasses = 0;
    final Map<String, int> absentCounts = <String, int>{};
    for (final doc in absenteeDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final int classCount = (data['classCount'] is int)
          ? data['classCount'] as int
          : 1;
      final int normalizedClassCount = classCount < 1 ? 1 : classCount;
      totalClasses += normalizedClassCount;
      final Map<String, int> dayAbsentCounts = _parseAbsentClassCountsFromDoc(
        data,
        defaultClassCount: normalizedClassCount,
      );
      for (final entry in dayAbsentCounts.entries) {
        if (entry.value > 0) {
          absentCounts[entry.key] = (absentCounts[entry.key] ?? 0) + entry.value;
        }
      }
    }

    return _students.map((student) {
      final int absentClasses = absentCounts[student.id] ?? 0;
      final int attendedClasses = totalClasses - absentClasses;
      final double percentage =
          totalClasses == 0 ? 100 : (attendedClasses / totalClasses) * 100;
      return AttendanceReportRow(
        usn: student.usn,
        name: student.name,
        attendedClasses: attendedClasses,
        totalClasses: totalClasses,
        percentage: double.parse(percentage.toStringAsFixed(2)),
      );
    }).toList();
  }

  Future<List<QueryDocumentSnapshot>> _loadMonthlyAbsenteeDocs({
    required int month,
    required int year,
  }) async {
    final DateTime monthStart = DateTime(year, month, 1);
    final DateTime monthEnd = DateTime(year, month + 1, 1);

    // Keep Firestore query index-free: filter by date range only, then apply
    // batch/semester/subject filters in Dart.
    final QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('absentees')
        .where(
          'dateTimestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart),
        )
        .where('dateTimestamp', isLessThan: Timestamp.fromDate(monthEnd))
        .get();

    return snapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return data['batchYear'] == _selectedBatchId &&
          data['semester'] == _selectedSemester &&
          data['subjectId'] == _selectedSubjectId;
    }).toList();
  }

  Future<void> _exportAttendanceReport() async {
    if (_selectedSubjectId == null || _students.isEmpty) {
      _showError('No data available to export');
      return;
    }
    setState(() => _isExporting = true);
    try {
      final batchName =
          Provider.of<AppState>(context, listen: false).selectedBatchName ?? '';
      final subject = _subjects.firstWhere((s) => s.id == _selectedSubjectId);
      final rows = await _buildMonthlyAttendanceRows();
      final monthLabel = DateFormat('MMMM yyyy').format(_selectedDate);

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          header: (_) => pw.Text(
            'Attendance Report - ${subject.code} (${subject.name})',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          footer: (ctx) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
          build: (_) => [
            pw.Text('Batch: $batchName | Semester: $_selectedSemester'),
            pw.Text('Month: $monthLabel'),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: const <String>[
                'USN',
                'Student Name',
                'Attended',
                'Total',
                'Attendance %'
              ],
              data: rows
                  .map(
                    (r) => <String>[
                      r.usn,
                      r.name,
                      r.attendedClasses.toString(),
                      r.totalClasses.toString(),
                      '${r.percentage.toStringAsFixed(2)}%',
                    ],
                  )
                  .toList(),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
      );

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final csvFile = File(
        '${tempDir.path}/attendance_${subject.code}_$timestamp.csv',
      );
      final csvContent = _buildCsv(rows);
      await csvFile.writeAsString(csvContent);
      await Share.shareXFiles(
        [XFile(csvFile.path)],
        text:
            'Attendance report (${subject.code}) for $monthLabel. CSV is Excel-compatible.',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Export started: PDF dialog + CSV share'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _showError('Failed to export report: $e');
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  /// --------------- MONTHLY DATE-WISE REPORT ---------------

  Future<void> _exportMonthlyDatewiseReport() async {
    if (_selectedSubjectId == null || _students.isEmpty) {
      _showError('No data available to export');
      return;
    }
    setState(() => _isExportingDatewise = true);

    try {
      final batchName =
          Provider.of<AppState>(context, listen: false).selectedBatchName ?? '';
      final subject = _subjects.firstWhere((s) => s.id == _selectedSubjectId);
      final int month = _selectedDate.month;
      final int year = _selectedDate.year;
      final monthLabel = DateFormat('MMMM yyyy').format(_selectedDate);

      // 1. Load all absentee docs for the month
      final absenteeDocs =
          await _loadMonthlyAbsenteeDocs(month: month, year: year);

      // 2. Build a map:  date-string -> { classCount, absentCounts }
      final Map<String, _DayRecord> dayRecords = {};
      for (final doc in absenteeDocs) {
        final data = doc.data() as Map<String, dynamic>;
        final String dateStr = data['date'] ?? '';
        if (dateStr.isEmpty) continue;
        final int classCount =
            (data['classCount'] is int) ? data['classCount'] as int : 1;
        final int normalizedCC = classCount < 1 ? 1 : classCount;
        final Map<String, int> dayAbsentCounts =
            _parseAbsentClassCountsFromDoc(data,
                defaultClassCount: normalizedCC);
        dayRecords[dateStr] = _DayRecord(
          classCount: normalizedCC,
          absentCounts: dayAbsentCounts,
        );
      }

      // 3. Build sorted list of dates in the month that had classes
      final List<String> sortedDates = dayRecords.keys.toList()
        ..sort();

      if (sortedDates.isEmpty) {
        _showError('No attendance data found for $monthLabel');
        setState(() => _isExportingDatewise = false);
        return;
      }

      // 4. Expand each date into individual class-slot columns.
      //    If April 14 had 2 classes → two columns "14/4 C1", "14/4 C2".
      //    If a date had 1 class → single column "14/4".
      final List<_ClassSlot> classSlots = [];
      for (final dateStr in sortedDates) {
        final dayRec = dayRecords[dateStr]!;
        final parts = dateStr.split('-'); // yyyy-MM-dd
        final String shortDate = (parts.length == 3)
            ? '${int.parse(parts[2])}/${int.parse(parts[1])}'
            : dateStr;
        if (dayRec.classCount == 1) {
          classSlots.add(_ClassSlot(
            dateStr: dateStr,
            classIndex: 0,
            label: shortDate,
          ));
        } else {
          for (int c = 0; c < dayRec.classCount; c++) {
            classSlots.add(_ClassSlot(
              dateStr: dateStr,
              classIndex: c,
              label: '$shortDate C${c + 1}',
            ));
          }
        }
      }

      // 5. Build the data grid
      //    Each row: [Sl, USN, Name, slot1, slot2, ..., TotalClasses, Attended, %]
      final List<List<String>> dataRows = [];
      int grandTotalClasses = 0;
      for (final dr in dayRecords.values) {
        grandTotalClasses += dr.classCount;
      }

      for (int i = 0; i < _students.length; i++) {
        final student = _students[i];
        final List<String> row = [
          '${i + 1}',
          student.usn,
          student.name,
        ];
        int totalAbsent = 0;
        for (final slot in classSlots) {
          final dayRec = dayRecords[slot.dateStr]!;
          final int absentCount = dayRec.absentCounts[student.id] ?? 0;
          final int presentCount = dayRec.classCount - absentCount;
          // Distribute: first presentCount slots are P, rest are A.
          // e.g., 2 classes, 1 absent → slot 0 (C1) = P, slot 1 (C2) = A
          if (slot.classIndex < presentCount) {
            row.add('P');
          } else {
            row.add('A');
            totalAbsent += 1;
          }
        }
        final int attended = grandTotalClasses - totalAbsent;
        final double pct = grandTotalClasses == 0
            ? 100
            : (attended / grandTotalClasses) * 100;
        row.addAll([
          grandTotalClasses.toString(),
          attended.toString(),
          '${pct.toStringAsFixed(1)}%',
        ]);
        dataRows.add(row);
      }

      final List<String> slotLabels =
          classSlots.map((s) => s.label).toList();

      final List<String> headers = [
        'Sl',
        'USN',
        'Student Name',
        ...slotLabels,
        'Total',
        'Attended',
        '%',
      ];

      // 6. Determine page format based on column count
      //    Use landscape; pick A3 or larger to fit all class slots.
      final int columnCount = headers.length;
      PdfPageFormat pageFormat;
      if (columnCount <= 20) {
        pageFormat = PdfPageFormat.a4.landscape;
      } else if (columnCount <= 30) {
        pageFormat = PdfPageFormat.a3.landscape;
      } else {
        // For very wide tables, use a custom wide format
        final double w = 297 + (columnCount - 30) * 10.0;
        pageFormat = PdfPageFormat(
          w * PdfPageFormat.mm,
          297 * PdfPageFormat.mm,
          marginAll: 10 * PdfPageFormat.mm,
        );
      }

      // 7. Compute column widths
      //    Fixed widths for Sl, USN, Name, Total, Attended, %; narrow for class slots
      final Map<int, pw.TableColumnWidth> columnWidths = {};
      columnWidths[0] = const pw.FixedColumnWidth(24);  // Sl
      columnWidths[1] = const pw.FixedColumnWidth(80);  // USN
      columnWidths[2] = const pw.FixedColumnWidth(100); // Name
      for (int c = 3; c < 3 + classSlots.length; c++) {
        // Wider columns for multi-class labels like "14/4 C1"
        columnWidths[c] = const pw.FixedColumnWidth(32);
      }
      final int totalColIdx = 3 + classSlots.length;
      columnWidths[totalColIdx] = const pw.FixedColumnWidth(32);     // Total
      columnWidths[totalColIdx + 1] = const pw.FixedColumnWidth(38); // Attended
      columnWidths[totalColIdx + 2] = const pw.FixedColumnWidth(36); // %

      // 8. Build PDF
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(16),
          header: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Monthly Datewise Attendance',
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                '${subject.code} - ${subject.name}  |  Batch: $batchName  |  '
                'Sem: $_selectedSemester  |  Month: $monthLabel',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'P = Present  |  A = Absent  |  '
                'Dates with multiple classes show C1, C2, etc.',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 6),
            ],
          ),
          footer: (ctx) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
          build: (_) => [
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: dataRows,
              columnWidths: columnWidths,
              cellStyle: const pw.TextStyle(fontSize: 7),
              headerStyle: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
              ),
              cellAlignment: pw.Alignment.center,
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              headerAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
              },
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
              },
            ),
          ],
        ),
      );

      // 9. Show print / share dialog
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );

      // 10. Also share as CSV
      final csvBuf = StringBuffer();
      csvBuf.writeln(headers.map(_csvField).join(','));
      for (final row in dataRows) {
        csvBuf.writeln(row.map(_csvField).join(','));
      }

      final tempDir = await getTemporaryDirectory();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final csvFile = File(
        '${tempDir.path}/datewise_${subject.code}_$ts.csv',
      );
      await csvFile.writeAsString(csvBuf.toString());
      await Share.shareXFiles(
        [XFile(csvFile.path)],
        text:
            'Monthly datewise attendance (${subject.code}) $monthLabel. Open in Excel.',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Datewise report: PDF dialog + CSV share'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _showError('Failed to export datewise report: $e');
    } finally {
      if (mounted) {
        setState(() => _isExportingDatewise = false);
      }
    }
  }

  String _buildCsv(List<AttendanceReportRow> rows) {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('USN,Student Name,Attended Classes,Total Classes,Attendance %');
    for (final row in rows) {
      buffer.writeln(
        '${_csvField(row.usn)},${_csvField(row.name)},${row.attendedClasses},'
        '${row.totalClasses},${row.percentage.toStringAsFixed(2)}',
      );
    }
    return buffer.toString();
  }

  String _csvField(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  int _getAbsentClassesForStudent(String studentId) {
    return _absentClassCounts[studentId] ?? 0;
  }

  int _getAbsentStudentCount() {
    return _absentClassCounts.values.where((absentValue) => absentValue > 0).length;
  }

  void _setAbsentClassesForStudent(String studentId, int count) {
    final int normalized = count.clamp(0, _classCount);
    setState(() {
      if (normalized == 0) {
        _absentClassCounts.remove(studentId);
      } else {
        _absentClassCounts[studentId] = normalized;
      }
    });
  }

  Map<String, int> _parseAbsentClassCountsFromDoc(
    Map<String, dynamic> data, {
    int defaultClassCount = 1,
  }) {
    final Map<String, int> result = <String, int>{};
    final dynamic absentClassCountsRaw = data['absentClassCounts'];

    if (absentClassCountsRaw is Map) {
      absentClassCountsRaw.forEach((key, value) {
        if (key is String && value is num) {
          final int normalized = value.toInt().clamp(0, defaultClassCount);
          if (normalized > 0) {
            result[key] = normalized;
          }
        }
      });
      return result;
    }

    // Backward compatibility for older records that only stored absentStudents.
    final List<dynamic> absentStudents = data['absentStudents'] ?? <dynamic>[];
    for (final studentId in absentStudents) {
      if (studentId is String) {
        result[studentId] = defaultClassCount;
      }
    }
    return result;
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
        _absentClassCounts.clear();
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
                          onPressed: _isSaving ? null : _saveAbsentees,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Classes held today: $_classCount',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Decrease class count',
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: _isSaving || _classCount <= 1
                                  ? null
                                  : () {
                                      setState(() {
                                        _classCount -= 1;
                                        _absentClassCounts.updateAll((_, absentValue) {
                                          return absentValue > _classCount
                                              ? _classCount
                                              : absentValue;
                                        });
                                      });
                                    },
                            ),
                            IconButton(
                              tooltip: 'Increase class count',
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: _isSaving
                                  ? null
                                  : () {
                                      setState(() {
                                        _classCount += 1;
                                        _absentClassCounts.updateAll((_, absentValue) {
                                          return absentValue > _classCount
                                              ? _classCount
                                              : absentValue;
                                        });
                                      });
                                    },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: _isExporting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.download, size: 18),
                          label: Text(
                            _isExporting ? 'Exporting...' : 'Overall Report',
                          ),
                          onPressed: _isExporting || _isLoading
                              ? null
                              : _exportAttendanceReport,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: _isExportingDatewise
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.calendar_month, size: 18),
                          label: Text(
                            _isExportingDatewise
                                ? 'Exporting...'
                                : 'Monthly Datewise',
                          ),
                          onPressed: _isExportingDatewise || _isLoading
                              ? null
                              : _exportMonthlyDatewiseReport,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            backgroundColor:
                                Theme.of(context).colorScheme.secondary,
                            foregroundColor:
                                Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_getAbsentStudentCount() > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        '${_getAbsentStudentCount()} student(s) absent '
                        '($_classCount class(es) today)',
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
                          final absentClasses =
                              _getAbsentClassesForStudent(student.id);
                          final isAbsent = absentClasses > 0;

                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            color: isAbsent ? Colors.red.shade50 : null,
                            child: ListTile(
                              leading: SizedBox(
                                width: 105,
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline),
                                      splashRadius: 18,
                                      onPressed: () => _setAbsentClassesForStudent(
                                        student.id,
                                        absentClasses - 1,
                                      ),
                                    ),
                                    Text(
                                      '$absentClasses/$_classCount',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isAbsent ? Colors.red : Colors.green,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline),
                                      splashRadius: 18,
                                      onPressed: () => _setAbsentClassesForStudent(
                                        student.id,
                                        absentClasses + 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              title: Text(
                                student.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: isAbsent ? Colors.red : null,
                                ),
                              ),
                              subtitle: Text(
                                'USN: ${student.usn} | Absent: $absentClasses of $_classCount',
                              ),
                              trailing: isAbsent
                                  ? const Icon(Icons.person_off,
                                      color: Colors.red)
                                  : const Icon(Icons.person,
                                      color: Colors.green),
                              onTap: () {
                                final int next =
                                    absentClasses >= _classCount ? 0 : absentClasses + 1;
                                _setAbsentClassesForStudent(student.id, next);
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

class AttendanceReportRow {
  final String usn;
  final String name;
  final int attendedClasses;
  final int totalClasses;
  final double percentage;

  AttendanceReportRow({
    required this.usn,
    required this.name,
    required this.attendedClasses,
    required this.totalClasses,
    required this.percentage,
  });
}

/// Helper class to hold per-day attendance data for datewise report.
class _DayRecord {
  final int classCount;
  final Map<String, int> absentCounts;

  _DayRecord({required this.classCount, required this.absentCounts});
}

/// Helper class representing a single class slot (one column in datewise report).
class _ClassSlot {
  final String dateStr;
  final int classIndex; // 0-based index within the day
  final String label;   // e.g. "14/4" or "14/4 C1"

  _ClassSlot({
    required this.dateStr,
    required this.classIndex,
    required this.label,
  });
}
