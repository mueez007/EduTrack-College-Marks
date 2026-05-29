import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Imports for PDF generation/charts
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw; 
import 'package:printing/printing.dart';

import '../../providers/app_state.dart';
import '../../services/firestore_helper.dart';
import '../../services/results_update_service.dart';

// --- Data Models ---
class StudentResultModel {
  final String studentId;
  final String name;
  final String usn;
  double sgpa; 
  double cgpa; 
  int totalMarksObtained;
  int totalCredits;
  int? rank; 

  StudentResultModel({
    required this.studentId,
    required this.name,
    required this.usn,
    required this.sgpa,
    required this.cgpa,
    required this.totalMarksObtained,
    required this.totalCredits,
    this.rank,
  });

  StudentResultModel copyWith({int? rank}) {
    return StudentResultModel(
      studentId: studentId,
      name: name,
      usn: usn,
      sgpa: sgpa,
      cgpa: cgpa,
      totalMarksObtained: totalMarksObtained,
      totalCredits: totalCredits,
      rank: rank ?? this.rank,
    );
  }
}

class SgpaCgpaScreen extends StatefulWidget {
  const SgpaCgpaScreen({super.key});

  @override
  State<SgpaCgpaScreen> createState() => _SgpaCgpaScreenState();
}

class _SgpaCgpaScreenState extends State<SgpaCgpaScreen> {
  String? _selectedBatchId;
  int _selectedSemester = 1;
  bool _isLoading = true;
  List<StudentResultModel> _results = [];
  


  double _classAverageSgpa = 0.0;
  double _classAverageCgpa = 0.0;
  String _currentSortField = 'rank'; 
  bool _isAscending = true;

  @override
  void initState() {
    super.initState();
    _selectedBatchId = Provider.of<AppState>(context, listen: false).selectedBatchId;
    _loadCalculatedResults();
  }
  
  // --- Load Pre-calculated Results from Firestore directly ---
  Future<void> _loadCalculatedResults() async {
    if (_selectedBatchId == null) {
      setState(() => _isLoading = false);
      _showError("Batch ID is missing.");
      return;
    }
    setState(() => _isLoading = true);

    try {
      final deptId = Provider.of<AppState>(context, listen: false).departmentId;
      if (deptId == null) return;

      // 1. Fetch pre-calculated semesterResults from Firestore directly
      QuerySnapshot resultsSnapshot = await FirestoreHelper.deptCollection(deptId, 'semesterResults')
          .where('batchYear', isEqualTo: _selectedBatchId)
          .where('semester', isEqualTo: _selectedSemester)
          .get();

      // 1b. Fetch valid student IDs to filter out orphaned/deleted student results
      QuerySnapshot studentsSnapshot = await FirestoreHelper.deptCollection(deptId, 'students')
          .where('batchYear', isEqualTo: _selectedBatchId)
          .get();
      final Set<String> validStudentIds = studentsSnapshot.docs.map((doc) => doc.id).toSet();

      List<StudentResultModel> loadedResults = [];
      double totalSgpaSum = 0.0;
      double totalCgpaSum = 0.0;

      for (var doc in resultsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final studentId = data['studentId'] as String;

        // Skip results for deleted students
        if (!validStudentIds.contains(studentId)) continue;

        final name = data['name'] as String? ?? data['studentName'] as String? ?? 'No Name';
        final usn = data['usn'] as String? ?? 'N/A';
        final sgpa = (data['sgpa'] as num?)?.toDouble() ?? 0.0;
        final cgpa = (data['cgpa'] as num?)?.toDouble() ?? 0.0;
        final totalMarks = (data['totalMarksObtained'] as num?)?.toInt() ?? 0;
        final totalCredits = (data['totalCredits'] as num?)?.toInt() ?? 0;
        final rank = (data['rank'] as num?)?.toInt();

        loadedResults.add(StudentResultModel(
          studentId: studentId,
          name: name,
          usn: usn,
          sgpa: sgpa,
          cgpa: cgpa,
          totalMarksObtained: totalMarks,
          totalCredits: totalCredits,
          rank: rank,
        ));

        totalSgpaSum += sgpa;
        totalCgpaSum += cgpa;
      }

      // 2. Assign ranks in-memory by sorting the loaded results
      _assignRanks(loadedResults);

      _classAverageSgpa = loadedResults.isNotEmpty ? totalSgpaSum / loadedResults.length : 0.0;
      _classAverageCgpa = loadedResults.isNotEmpty ? totalCgpaSum / loadedResults.length : 0.0;

      if (mounted) {
        setState(() {
          _results = loadedResults;
          _isLoading = false;
          _sortResults(_currentSortField, _isAscending);
        });
      }
    } catch (e) {
      debugPrint("Error loading calculated results: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        _showError("Failed to load results: ${e.toString()}");
      }
    }
  }

  // --- Recalculate All: Client-side batch backfill (replaces Cloud Function) ---
  Future<void> _recalculateAll() async {
    if (_selectedBatchId == null) {
      _showError("Batch ID is missing.");
      return;
    }
    setState(() => _isLoading = true);

    try {
      final deptId = Provider.of<AppState>(context, listen: false).departmentId;
      if (deptId == null) return;

      _showSnackbar("Recalculating results for Sem $_selectedSemester... This may take a moment.", Colors.blue);

      final resultsUpdater = ResultsUpdateService();
      final message = await resultsUpdater.backfillBatchSemester(
        deptId: deptId,
        batchYear: _selectedBatchId!,
        semester: _selectedSemester,
      );

      _showSnackbar(message, Colors.green);

      // Reload the results after backfill
      await _loadCalculatedResults();
    } catch (e) {
      debugPrint("Error recalculating results: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        _showError("Failed to recalculate: ${e.toString()}");
      }
    }
  }

  // --- Publish in-memory calculated ranks back to Firestore in a single Batch Write ---
  Future<void> _publishRanks() async {
    if (_results.isEmpty) {
      _showError("No results to publish.");
      return;
    }
    setState(() => _isLoading = true);

    try {
      final deptId = Provider.of<AppState>(context, listen: false).departmentId;
      if (deptId == null) return;

      final batch = FirebaseFirestore.instance.batch();
      Map<String, dynamic> rankMap = {};

      for (var result in _results) {
        final resultRef = FirestoreHelper.deptDoc(deptId, 'semesterResults', '${result.studentId}_S$_selectedSemester');
        batch.update(resultRef, {'rank': result.rank});

        rankMap['rank_of_${result.studentId}'] = result.rank;
        rankMap['name_of_${result.studentId}'] = result.name;
      }

      final publicRankRef = FirestoreHelper.deptDoc(deptId, 'publicRanks', 'S$_selectedSemester-$_selectedBatchId');
      batch.set(publicRankRef, {
        'rankList': rankMap,
        'lastUpdated': FieldValue.serverTimestamp(),
        'classAverageSGPA': _classAverageSgpa,
        'classAverageCGPA': _classAverageCgpa,
      }, SetOptions(merge: true));

      await batch.commit();

      _showSnackbar("Ranks successfully published to student portal.", Colors.green);
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint("Error publishing ranks: $e");
      setState(() => _isLoading = false);
      _showError("Failed to publish ranks: ${e.toString()}");
    }
  }

  // --- Local Rank Assignment and Sorting ---
  void _assignRanks(List<StudentResultModel> list) {
    if (list.isEmpty) return;

    // 1. Sort by CGPA (Primary) and SGPA (Secondary) in descending order for ranking
    list.sort((a, b) {
      int cgpaCompare = b.cgpa.compareTo(a.cgpa); // Descending CGPA
      if (cgpaCompare != 0) return cgpaCompare;

      return b.sgpa.compareTo(a.sgpa); // Descending SGPA
    });

    // 2. Assign ranks
    int currentRank = 1;
    double? lastCgpa;
    double? lastSgpa;

    for (int i = 0; i < list.length; i++) {
      StudentResultModel current = list[i];
      // If marks/cgpa are the same as the previous student, assign the same rank
      if (i > 0 && current.cgpa == lastCgpa && current.sgpa == lastSgpa) {
        list[i].rank = list[i-1].rank;
      } else {
        list[i].rank = currentRank;
      }
      lastCgpa = current.cgpa;
      lastSgpa = current.sgpa;
      currentRank++;
    }
  }
  
  void _sortResults(String field, bool ascending) {
    setState(() {
      _currentSortField = field;
      _isAscending = ascending;

      _results.sort((a, b) {
        int comparison = 0;
        switch (field) {
          case 'name':
            comparison = a.name.compareTo(b.name);
            break;
          case 'sgpa':
            comparison = a.sgpa.compareTo(b.sgpa);
            break;
          case 'cgpa':
            comparison = a.cgpa.compareTo(b.cgpa);
            break;
          case 'rank':
          default:
            comparison = (a.rank ?? 999).compareTo(b.rank ?? 999);
            break;
        }
        return ascending ? comparison : -comparison;
      });
    });
  }

  // --- Helper Functions ---
  void _showError(String message) {
     if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
     }
  }
  void _showSnackbar(String message, Color color) {
     if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(message), backgroundColor: color),
        );
     }
  }

  // --- UI Elements ---

  @override
  Widget build(BuildContext context) {
    final selectedBatchName = Provider.of<AppState>(context).selectedBatchName ?? 'Results';
    final int studentCount = _results.length;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Results - Sem $_selectedSemester ($selectedBatchName)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.calculate_outlined),
            tooltip: 'Recalculate All Results',
            onPressed: _isLoading ? null : _recalculateAll,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload Results',
            onPressed: _isLoading ? null : _loadCalculatedResults,
          ),
          IconButton(
            icon: const Icon(Icons.publish_rounded),
            tooltip: 'Publish Ranks to Students',
            onPressed: _isLoading || _results.isEmpty ? null : _publishRanks,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export Results PDF',
            onPressed: _isLoading || _results.isEmpty ? null : () => _exportPdf(selectedBatchName),
          ),
        ],
      ),
      body: Column(
        children: [
          // --- Semester Selection ---
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
                          _loadCalculatedResults(); // Load pre-calculated results instantly!
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

          // --- Analytics Cards ---
          if (!_isLoading && _results.isNotEmpty) 
             Padding(
               padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Text('Result Summary (Total Students: $studentCount)', style: Theme.of(context).textTheme.titleMedium),
                   const SizedBox(height: 4),
                   Text('Formula: SGPA = Σ(Credits × Grade Point) / Σ(Credits)', 
                     style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic)),
                   const SizedBox(height: 10),
                   Row(
                     children: [
                       Expanded(child: _buildStatCard('Avg SGPA', _classAverageSgpa.toStringAsFixed(2), Colors.blue)),
                       const SizedBox(width: 10),
                       Expanded(child: _buildStatCard('Avg CGPA', _classAverageCgpa.toStringAsFixed(2), Colors.purple)),
                     ],
                   ),
                 ],
               ),
             ),


          // --- Results Table ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty 
                    ? Center(child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Text('No results for Sem $_selectedSemester. Please ensure all subject marks are entered.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ))
                    : SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: DataTable(
                          columnSpacing: 10,
                          headingRowHeight: 40,
                          dataRowMinHeight: 40,
                          dataRowMaxHeight: 40,
                          sortColumnIndex: _currentSortField == 'rank' ? 0 : (_currentSortField == 'name' ? 1 : (_currentSortField == 'sgpa' ? 2 : 3)),
                          sortAscending: _isAscending,
                          columns: [
                            DataColumn(
                              label: const Text('Rank', style: TextStyle(fontWeight: FontWeight.bold)),
                              onSort: (columnIndex, ascending) => _sortResults('rank', ascending),
                            ),
                            DataColumn(
                              label: const Text('Student Name', style: TextStyle(fontWeight: FontWeight.bold)),
                              onSort: (columnIndex, ascending) => _sortResults('name', ascending),
                            ),
                            DataColumn(
                              label: const Text('SGPA', style: TextStyle(fontWeight: FontWeight.bold)),
                              onSort: (columnIndex, ascending) => _sortResults('sgpa', ascending),
                            ),
                            DataColumn(
                              label: const Text('CGPA', style: TextStyle(fontWeight: FontWeight.bold)),
                              onSort: (columnIndex, ascending) => _sortResults('cgpa', ascending),
                            ),
                          ],
                          rows: _results.map((result) {
                            return DataRow(cells: [
                              DataCell(Text(result.rank?.toString() ?? '-')),
                              DataCell(Text(result.name)),
                              DataCell(Text(result.sgpa.toStringAsFixed(2))),
                              DataCell(Text(result.cgpa.toStringAsFixed(2))),
                            ]);
                          }).toList(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: color, fontSize: 14)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: color)),
          ],
        ),
      ),
    );
  }

  // --- PDF Export Implementation ---
  Future<void> _exportPdf(String batchName) async {
     if(!mounted) return;
     _showSnackbar("Generating Results PDF...", Colors.blue);
     await Future.delayed(const Duration(milliseconds: 50));

     final pdf = pw.Document();
     final semester = _selectedSemester;
     
     final List<String> headers = ['Rank', 'Name', 'USN', 'SGPA', 'CGPA', 'Total Marks', 'Credits'];
     final List<List<String>> data = _results.map((result) {
       return [
         result.rank?.toString() ?? '-',
         result.name,
         result.usn,
         result.sgpa.toStringAsFixed(2),
         result.cgpa.toStringAsFixed(2),
         result.totalMarksObtained.toString(),
         result.totalCredits.toString(),
       ];
     }).toList();

     // Build PDF
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context pdfContext) => [
            pw.Header(
              level: 0,
              child: pw.Text('Academic Results Report', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 20)),
            ),
            pw.Text('Batch: $batchName | Semester: $semester', style: const pw.TextStyle(fontSize: 14)),
            pw.Text('SGPA Formula: VTU Credit-Based — Σ(Credits × Grade Point) / Σ(Credits)', style: const pw.TextStyle(fontSize: 10)),
            pw.Divider(),
            
            // Analytics Summary
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey)),
              child: pw.Text('Class Average SGPA: ${_classAverageSgpa.toStringAsFixed(2)} | Average CGPA: ${_classAverageCgpa.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 15),

            // Results Table
            pw.Table.fromTextArray(
              headers: headers,
              data: data,
              border: pw.TableBorder.all(color: PdfColors.grey),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignments: {
                  0: pw.Alignment.center, // Rank
                  3: pw.Alignment.center, // SGPA
                  4: pw.Alignment.center, // CGPA
                  5: pw.Alignment.center, // Total Marks
                  6: pw.Alignment.center, // Credits
              },
            ),
          ],
        ),
      );

      // Save/Share
      await Printing.layoutPdf(
         onLayout: (PdfPageFormat format) async => pdf.save(),
         name: '${batchName}_Sem${semester}_Results.pdf',
       );
  }
}