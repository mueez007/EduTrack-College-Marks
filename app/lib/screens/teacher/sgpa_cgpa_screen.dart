import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Imports for PDF generation/charts
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw; 
import 'package:printing/printing.dart';

import '../../providers/app_state.dart';
import '../../services/results_calculation_service.dart';
import '../../services/mark_calculation_service.dart';

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
  
  // Services
  final ResultsCalculationService _resultCalculator = ResultsCalculationService();

  double _classAverageSgpa = 0.0;
  double _classAverageCgpa = 0.0;
  String _currentSortField = 'rank'; 
  bool _isAscending = true;

  @override
  void initState() {
    super.initState();
    _selectedBatchId = Provider.of<AppState>(context, listen: false).selectedBatchId;
    _loadAllDataAndCalculate();
  }
  
  // --- Core Calculation and Data Loading ---
  Future<void> _loadAllDataAndCalculate() async {
    if (_selectedBatchId == null) {
      setState(() => _isLoading = false);
      _showError("Batch ID is missing.");
      return;
    }
    setState(() => _isLoading = true);

    try {
      // 1. Get Subjects to find credits and max marks per subject
      QuerySnapshot subjectSnapshot = await FirebaseFirestore.instance
          .collection('subjects')
          .where('batchYear', isEqualTo: _selectedBatchId)
          .where('semester', isEqualTo: _selectedSemester)
          .get();
      
      final int subjectCount = subjectSnapshot.docs.length;
      if (subjectCount == 0) {
        _showSnackbar("No subjects found for Sem $_selectedSemester. Cannot calculate.", Colors.orange);
        setState(() { _results = []; _isLoading = false; });
        return;
      }
      
      // Build a map of subjectId -> {credits, maxSubjectTotal} for quick lookup
      Map<String, Map<String, dynamic>> subjectInfoMap = {};
      for (var doc in subjectSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        subjectInfoMap[doc.id] = {
          'credits': data['credits'] as int? ?? 0,
          'maxSubjectTotal': data['maxSubjectTotal'] as int? ?? 100,
        };
      }
      
      // 2. Get All Students in the batch
      QuerySnapshot studentSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('batchYear', isEqualTo: _selectedBatchId)
          .get();
          
      List<StudentResultModel> calculatedResults = [];
      double totalSgpaSum = 0.0;
      double totalCgpaSum = 0.0;

      // 3. Loop through students and calculate their results
      for (var studentDoc in studentSnapshot.docs) {
        final studentData = studentDoc.data() as Map<String, dynamic>;
        final studentId = studentDoc.id; 
        final usn = studentData['usn'] ?? 'N/A';
        final name = studentData['name'] ?? 'No Name';

        // 3a. Get all final marks for this student/semester
        QuerySnapshot finalMarksSnapshot = await FirebaseFirestore.instance
            .collection('finalExamMarks')
            .where('studentRef', isEqualTo: FirebaseFirestore.instance.doc('students/$studentId'))
            .where('semester', isEqualTo: _selectedSemester)
            .get();
        
        int totalMarksObtained = 0;
        int totalCredits = 0;
        
        // Build the list of subject results for VTU SGPA calculation
        List<Map<String, dynamic>> subjectResults = [];
        final markCalc = MarkCalculationService();
        
        for (var markDoc in finalMarksSnapshot.docs) {
          final markData = markDoc.data() as Map<String, dynamic>;
          
          // Get the subject reference to find credits and maxSubjectTotal
          final DocumentReference? subjectRef = markData['subjectRef'] as DocumentReference?;
          String? subId;
          if (subjectRef != null) {
            subId = subjectRef.id;
          }
          
          // Look up credits and maxSubjectTotal from our subject map
          int credits = 0;
          int maxSubjectTotal = 100;
          if (subId != null && subjectInfoMap.containsKey(subId)) {
            credits = subjectInfoMap[subId]!['credits'] as int;
            maxSubjectTotal = subjectInfoMap[subId]!['maxSubjectTotal'] as int;
          }
          
          // === ALWAYS RECALCULATE FROM SOURCE DATA ===
          // 1. Get fresh iaFinal from marks collection (source of truth)
          final iaMarkDocId = '${studentId}_$subId';
          double freshIaFinal = 0.0;
          try {
            DocumentSnapshot iaMarkSnapshot = await FirebaseFirestore.instance
                .collection('marks')
                .doc(iaMarkDocId)
                .get();
            if (iaMarkSnapshot.exists) {
              final iaData = iaMarkSnapshot.data() as Map<String, dynamic>;
              freshIaFinal = (iaData['calculated_iaFinal'] as num?)?.toDouble() ?? 0.0;
              
              // If calculated_iaFinal not stored, recalculate from raw IA marks
              if (freshIaFinal == 0.0) {
                // Get subject data for calculation rules
                final subjectDocSnapshot = await subjectRef?.get();
                if (subjectDocSnapshot != null && subjectDocSnapshot.exists) {
                  final fullSubjectData = subjectDocSnapshot.data() as Map<String, dynamic>;
                  freshIaFinal = markCalc.calculateIaFinalLocal(
                    ia1: iaData['ia_1'] as int?,
                    ia2: iaData['ia_2'] as int?,
                    ia3: iaData['ia_3'] as int?,
                    projectOrAssignment: iaData['projectOrAssignment'] as int?,
                    subjectData: fullSubjectData,
                  );
                }
              }
            }
          } catch (e) {
            print('[SGPA] Warning: Could not fetch IA marks for $iaMarkDocId: $e');
          }
          
          // 2. Get examFinal from finalExamMarks (already have it)
          final int examFinal = (markData['examFinal'] as num?)?.toInt() ?? 0;
          
          // 3. Recalculate total from fresh source data
          double calculatedTotal = 0.0;
          try {
            final subjectDocSnapshot = await subjectRef?.get();
            if (subjectDocSnapshot != null && subjectDocSnapshot.exists) {
              final fullSubjectData = subjectDocSnapshot.data() as Map<String, dynamic>;
              calculatedTotal = markCalc.calculateTotalMarksLocal(
                iaFinal: freshIaFinal,
                examFinal: examFinal,
                subjectData: fullSubjectData,
              );
            }
          } catch (e) {
            // Fallback to stored value
            calculatedTotal = (markData['calculated_total'] as num?)?.toDouble() ?? 0.0;
            print('[SGPA] Warning: Could not recalculate total for $iaMarkDocId, using stored: $calculatedTotal');
          }
          
          // 4. Auto-repair: update finalExamMarks if stored values differ
          final storedIaFinal = (markData['iaFinal'] as num?)?.toDouble() ?? 0.0;
          final storedTotal = (markData['calculated_total'] as num?)?.toDouble() ?? 0.0;
          if ((storedIaFinal - freshIaFinal).abs() > 0.01 || (storedTotal - calculatedTotal).abs() > 0.01) {
            markDoc.reference.update({
              'iaFinal': freshIaFinal,
              'calculated_total': calculatedTotal,
            }).catchError((e) => print('[SGPA] Auto-repair failed for $iaMarkDocId: $e'));
            print('[SGPA AUTO-REPAIR] Fixed $iaMarkDocId: iaFinal=$freshIaFinal (was $storedIaFinal), total=$calculatedTotal (was $storedTotal)');
          }
          
          totalMarksObtained += calculatedTotal.round();
          totalCredits += credits;
          
          // Scale marks to 100 for grade point calculation
          double scaledMarks = calculatedTotal;
          if (maxSubjectTotal != 100 && maxSubjectTotal > 0) {
            scaledMarks = (calculatedTotal / maxSubjectTotal) * 100.0;
          }
          int gradePoint = _resultCalculator.getGradePoint(scaledMarks);
          
          print('[SGPA DEBUG] Student: $name | Subject: $subId | iaFinal=$freshIaFinal | exam=$examFinal | Total: $calculatedTotal/$maxSubjectTotal | Scaled: ${scaledMarks.toStringAsFixed(1)} | GP: $gradePoint | Credits: $credits | C×G: ${credits * gradePoint}');
          
          subjectResults.add({
            'totalMarks': calculatedTotal,
            'maxSubjectTotal': maxSubjectTotal,
            'credits': credits,
          });
        }

        // 3b. Calculate SGPA using VTU Credit-Based Formula
        // SGPA = Σ(Ci × Gi) / Σ(Ci)
        double sgpa = _resultCalculator.calculateSgpa(
          subjectResults: subjectResults,
        );
        
        print('[SGPA DEBUG] Student: $name | Total Credits: $totalCredits | SGPA: $sgpa');
        
        // 3c. Fetch previous SGPAs for CGPA
        List<double> prevSgpas = [];
        if (_selectedSemester > 1) { 
           QuerySnapshot prevResults = await FirebaseFirestore.instance
                .collection('semesterResults')
                .where('studentId', isEqualTo: studentId) 
                .where('semester', isLessThan: _selectedSemester)
                .get();

           for (var resultDoc in prevResults.docs) {
             prevSgpas.add((resultDoc['sgpa'] as num).toDouble());
           }
        }
        
        // 3d. Calculate CGPA (average of all semester SGPAs)
        double cgpa = _resultCalculator.calculateCgpa(
          currentSgpa: sgpa, 
          previousSgpas: prevSgpas,
        );
        
        // Add to list and running totals
        calculatedResults.add(StudentResultModel(
          studentId: studentId,
          name: name,
          usn: usn,
          sgpa: sgpa,
          cgpa: cgpa,
          totalMarksObtained: totalMarksObtained,
          totalCredits: totalCredits,
        ));

        totalSgpaSum += sgpa;
        totalCgpaSum += cgpa;

        // 3e. Save result to Firestore for persistence
        await FirebaseFirestore.instance.collection('semesterResults').doc('${studentId}_S$_selectedSemester').set({
          'studentId': studentId,
          'name': name,
          'usn': usn,
          'batchYear': _selectedBatchId,
          'semester': _selectedSemester,
          'sgpa': sgpa,
          'cgpa': cgpa,
          'totalMarksObtained': totalMarksObtained,
          'totalCredits': totalCredits,
          'rank': 0, 
          'lastCalculated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

      } // End student loop

      // 4. Calculate Class Averages and Assign Ranks
      _classAverageSgpa = calculatedResults.isNotEmpty ? totalSgpaSum / calculatedResults.length : 0.0;
      _classAverageCgpa = calculatedResults.isNotEmpty ? totalCgpaSum / calculatedResults.length : 0.0;
      
      _assignRanks(calculatedResults); // Assigns rank property
      
      // 5. Update Ranks in Firestore (PublicRanks & semesterResults)
      Map<String, dynamic> rankMap = {};
      for (var result in calculatedResults) {
          // Update individual semesterResults document with final rank
          FirebaseFirestore.instance.collection('semesterResults').doc('${result.studentId}_S$_selectedSemester').update({
              'rank': result.rank,
          });
          // Save rank and name to the public map (for student comparison)
          rankMap['rank_of_${result.studentId}'] = result.rank; 
          rankMap['name_of_${result.studentId}'] = result.name; 
      }
      
      // Save the single public document containing all rank data
      await FirebaseFirestore.instance.collection('publicRanks').doc('S$_selectedSemester-$_selectedBatchId').set({
          'rankList': rankMap,
          'lastUpdated': FieldValue.serverTimestamp(),
          'classAverageSGPA': _classAverageSgpa,
          'classAverageCGPA': _classAverageCgpa,
      }, SetOptions(merge: true));
      
      // 6. Update UI
      if(mounted) {
        setState(() {
          _results = calculatedResults;
          _isLoading = false;
          _sortResults(_currentSortField, _isAscending); 
        });
        _showSnackbar("Results for Sem $_selectedSemester calculated and saved.", Colors.green);
      }

    } catch (e) {
      print("Error during calculation: $e");
      if(mounted) {
        setState(() => _isLoading = false);
        _showError("Calculation Failed: ${e.toString()}");
      }
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
            icon: const Icon(Icons.refresh),
            tooltip: 'Recalculate Results',
            onPressed: _isLoading ? null : _loadAllDataAndCalculate,
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
                          _loadAllDataAndCalculate(); // Recalculate/load data for the new semester
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