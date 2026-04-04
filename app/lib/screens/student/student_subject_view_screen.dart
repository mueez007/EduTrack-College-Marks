import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/mark_calculation_service.dart';

class StudentSubjectViewScreen extends StatefulWidget {
  final String studentId;
  final String subjectId;
  final String subjectName;
  final Map<String, dynamic> subjectData;

  const StudentSubjectViewScreen({
    super.key,
    required this.studentId,
    required this.subjectId,
    required this.subjectName,
    required this.subjectData,
  });

  @override
  State<StudentSubjectViewScreen> createState() => _StudentSubjectViewScreenState();
}

class _StudentSubjectViewScreenState extends State<StudentSubjectViewScreen> {
  final MarkCalculationService _markCalculator = MarkCalculationService();
  
  // Resolved data (after fetching from both collections)
  bool _isLoading = true;
  double _iaFinal = 0.0;
  double _examComponent = 0.0;
  double _subjectTotal = 0.0;
  
  // Raw IA data
  String _ia1 = '-';
  String _ia2 = '-';
  String _ia3 = '-';
  String _projAssign = '-';
  
  // Rank
  String _studentRank = 'N/A';
  int _classSize = 0;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    final markDocId = '${widget.studentId}_${widget.subjectId}';
    
    try {
      // 1. Fetch raw IA marks from 'marks' collection (source of truth for IA)
      DocumentSnapshot iaMarkSnapshot = await FirebaseFirestore.instance
          .collection('marks')
          .doc(markDocId)
          .get();
      
      double? calculatedIaFinal;
      if (iaMarkSnapshot.exists) {
        final iaData = iaMarkSnapshot.data() as Map<String, dynamic>;
        _ia1 = iaData['ia_1']?.toString() ?? '-';
        _ia2 = iaData['ia_2']?.toString() ?? '-';
        _ia3 = iaData['ia_3']?.toString() ?? '-';
        _projAssign = iaData['projectOrAssignment']?.toString() ?? '-';
        calculatedIaFinal = (iaData['calculated_iaFinal'] as num?)?.toDouble();
        
        // If calculated_iaFinal not stored, recalculate locally
        if (calculatedIaFinal == null) {
          calculatedIaFinal = _markCalculator.calculateIaFinalLocal(
            ia1: iaData['ia_1'] as int?,
            ia2: iaData['ia_2'] as int?,
            ia3: iaData['ia_3'] as int?,
            projectOrAssignment: iaData['projectOrAssignment'] as int?,
            subjectData: widget.subjectData,
          );
        }
      }
      
      _iaFinal = calculatedIaFinal ?? 0.0;
      
      // 2. Fetch final exam marks from 'finalExamMarks' collection
      DocumentSnapshot finalMarkSnapshot = await FirebaseFirestore.instance
          .collection('finalExamMarks')
          .doc(markDocId)
          .get();
      
      if (finalMarkSnapshot.exists) {
        final finalData = finalMarkSnapshot.data() as Map<String, dynamic>;
        final int? examFinal = (finalData['examFinal'] as num?)?.toInt();
        
        // Calculate total using the correct iaFinal (from marks collection)
        // NOT the potentially stale iaFinal from finalExamMarks
        _subjectTotal = _markCalculator.calculateTotalMarksLocal(
          iaFinal: _iaFinal,
          examFinal: examFinal,
          subjectData: widget.subjectData,
        );
        _examComponent = _subjectTotal - _iaFinal;
        
        // Auto-repair: If finalExamMarks has wrong iaFinal, fix it
        final storedIaFinal = (finalData['iaFinal'] as num?)?.toDouble() ?? 0.0;
        final storedTotal = (finalData['calculated_total'] as num?)?.toDouble() ?? 0.0;
        
        if ((storedIaFinal - _iaFinal).abs() > 0.01 || (storedTotal - _subjectTotal).abs() > 0.01) {
          // Fix the stale data in Firestore
          FirebaseFirestore.instance
              .collection('finalExamMarks')
              .doc(markDocId)
              .update({
            'iaFinal': _iaFinal,
            'calculated_total': _subjectTotal,
          }).catchError((e) => print('Auto-repair failed: $e'));
          print('[STUDENT VIEW AUTO-REPAIR] Fixed $markDocId: iaFinal=$_iaFinal, total=$_subjectTotal');
        }
      }
      
      // 3. Fetch rank from publicRanks
      final int semester = widget.subjectData['semester'] as int? ?? 1;
      final String batchId = widget.subjectData['batchYear'] as String? ?? 'N/A';
      
      DocumentSnapshot rankSnapshot = await FirebaseFirestore.instance
          .collection('publicRanks')
          .doc('S$semester-$batchId')
          .get();
      
      if (rankSnapshot.exists) {
        final rankData = rankSnapshot.data() as Map<String, dynamic>;
        final rankList = rankData['rankList'] as Map<String, dynamic>? ?? {};
        _studentRank = rankList['rank_of_${widget.studentId}']?.toString() ?? 'N/A';
        _classSize = (rankList.keys.length / 2).round();
      }
      
    } catch (e) {
      print('Error loading student subject data: $e');
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // Helper widget to display a single row of final marks
  Widget _buildMarkRow(BuildContext context, String title, double score, int max, Color color, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontSize: 16, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
          Text('${score.toStringAsFixed(1)} / $max', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
  
  // Helper widget to display raw input breakdown rows
  Widget _buildBreakdownRow(BuildContext context, String title, String score, int max) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 14)),
          Text('$score / $max', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int maxIA = widget.subjectData['baseInternalMax'] ?? 40; 
    final int maxProjAssign = widget.subjectData['maxProject'] ?? 25; 
    final String iaRule = widget.subjectData['iaCalculationRule'] ?? 'N/A';
    final int maxSubjectTotal = widget.subjectData['maxSubjectTotal'] ?? 100;
    final int maxExamTotal = widget.subjectData['maxExamTotal'] ?? 50;
    
    // Derive correct maxInternalTotal from the IA rule
    // (don't trust stored value as it may be stale)
    int maxInternalTotal;
    switch (iaRule) {
      case 'SEM_5_6_SCHEMA':          // reduced IA (25) + project (25) = 50
      case 'SEM_SPECIAL_100_MARK_SCHEMA': // reduced IA (25) + project (25) = 50
        maxInternalTotal = 50;
        break;
      case 'BEST_2_OF_3_AVG':         // reduced IA (15) + assignment (10) + lab (25) = 50
        maxInternalTotal = widget.subjectData['maxInternalTotal'] ?? 50;
        break;
      default:
        maxInternalTotal = widget.subjectData['maxInternalTotal'] ?? 50;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subjectName, overflow: TextOverflow.ellipsis),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              
              // --- Rank Card ---
              Card(
                elevation: 4,
                color: Theme.of(context).colorScheme.primaryContainer,
                margin: const EdgeInsets.only(bottom: 20),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  leading: Icon(Icons.star_rate_rounded, size: 40, color: Theme.of(context).primaryColor),
                  title: Text('Your Rank in Class (${widget.subjectData['subjectCode']})', style: Theme.of(context).textTheme.titleMedium),
                  trailing: Text('RANK: $_studentRank', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColorDark)),
                  subtitle: Text('Total Students: $_classSize'),
                ),
              ),

              // --- Final Mark Summary ---
              Text('Total Performance', style: Theme.of(context).textTheme.headlineSmall),
              const Divider(),
              _buildMarkRow(context, 'IA Final (Internal)', _iaFinal, maxInternalTotal, Colors.blue),
              _buildMarkRow(context, 'Exam Component', _examComponent, maxExamTotal, Colors.blue),
              _buildMarkRow(context, 'Subject Total', _subjectTotal, maxSubjectTotal, Colors.deepPurple, isTotal: true),
              
              const SizedBox(height: 30),

              // --- IA Marks Breakdown ---
              Text('Internal Assessment Breakdown (Rule: $iaRule)', style: Theme.of(context).textTheme.headlineSmall),
              const Divider(),
              _buildBreakdownRow(context, 'IA 1 (Max $maxIA)', _ia1, maxIA),
              _buildBreakdownRow(context, 'IA 2 (Max $maxIA)', _ia2, maxIA),
              _buildBreakdownRow(context, 'IA 3 (Max $maxIA)', _ia3, maxIA),
              _buildBreakdownRow(context, 'Project/Assignment (Max $maxProjAssign)', _projAssign, maxProjAssign),
            ],
          ),
        ),
    );
  }
}