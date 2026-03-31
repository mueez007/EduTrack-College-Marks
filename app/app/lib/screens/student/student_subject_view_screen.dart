import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StudentSubjectViewScreen extends StatelessWidget {
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

  // Helper widget to display a single row of final marks
  Widget _buildMarkRow(BuildContext context, String title, double score, int max, Color color, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontSize: 16, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
          Text('${score.toStringAsFixed(1)} / ${max}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
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
          Text('$score / ${max}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    // Document ID for IA Marks and Final Marks (they share the same ID structure)
    final markDocId = '${studentId}_${subjectId}';

    // Retrieve max marks and rule details from the subjectData map
    final int maxIA = subjectData['baseInternalMax'] ?? 40; 
    final int maxProjAssign = subjectData['maxProject'] ?? 25; 
    final int semester = subjectData['semester'] as int? ?? 1;
    final String batchId = subjectData['batchYear'] as String? ?? 'N/A';
    final String iaRule = subjectData['iaCalculationRule'] ?? 'N/A';

    // Stream the finalExamMarks document, as it contains all final totals
    final finalMarksStream = FirebaseFirestore.instance
        .collection('finalExamMarks')
        .doc(markDocId)
        .snapshots();
        
    // Stream for the raw IA marks 
     final iaMarksStream = FirebaseFirestore.instance
        .collection('marks')
        .doc(markDocId)
        .snapshots();
        
    // Public Rank Stream (from the public collection)
    final publicRankStream = FirebaseFirestore.instance
        .collection('publicRanks')
        .doc('S$semester-$batchId') // Doc ID: S{Sem}-{Batch}
        .snapshots();


    return Scaffold(
      appBar: AppBar(
        title: Text(subjectName, overflow: TextOverflow.ellipsis),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            
            // --- Rank Card (Using Public Data for Class Size/Rank) ---
            StreamBuilder<DocumentSnapshot>(
              stream: publicRankStream,
              builder: (context, snapshot) {
                 final data = snapshot.data?.data() as Map<String, dynamic>?;
                 final rankList = data?['rankList'] as Map<String, dynamic>? ?? {};
                 final studentRank = rankList['rank_of_$studentId']?.toString() ?? 'N/A';
                 
                 // Class Size is calculated from the length of the rankList map
                 // We stored rank_of_UID and name_of_UID, so divide by 2
                 final classSize = rankList.keys.length / 2;

                 return Card(
                   elevation: 4,
                   color: Theme.of(context).colorScheme.primaryContainer,
                   margin: const EdgeInsets.only(bottom: 20),
                   child: ListTile(
                     contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                     leading: Icon(Icons.star_rate_rounded, size: 40, color: Theme.of(context).primaryColor),
                     title: Text('Your Rank in Class (${subjectData['subjectCode']})', style: Theme.of(context).textTheme.titleMedium),
                     trailing: Text('RANK: ${studentRank}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColorDark)),
                     subtitle: Text('Total Students: ${classSize.round()}'), // Show class size
                   ),
                 );
              }
            ),


            // --- Final Mark Summary ---
            StreamBuilder<DocumentSnapshot>(
              stream: finalMarksStream,
              builder: (context, snapshot) {
                 if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator.adaptive());
                }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(child: Text("Final results are not yet published."));
                }
                final data = snapshot.data!.data() as Map<String, dynamic>;
                
                final iaFinal = (data['iaFinal'] as num?)?.toDouble() ?? 0.0;
                final total = (data['calculated_total'] as num?)?.toDouble() ?? 0.0;
                final examComponent = total - iaFinal; 
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Performance', style: Theme.of(context).textTheme.headlineSmall),
                    const Divider(),
                    _buildMarkRow(context, 'IA Final (Internal)', iaFinal, 50, Colors.blue),
                    _buildMarkRow(context, 'Exam Component', examComponent, 50, Colors.blue),
                    _buildMarkRow(context, 'Subject Total', total, 100, Colors.deepPurple, isTotal: true),
                  ],
                );
              },
            ),
            
            const SizedBox(height: 30),

            // --- IA Marks Breakdown ---
             Text('Internal Assessment Breakdown (Rule: $iaRule)', style: Theme.of(context).textTheme.headlineSmall),
             const Divider(),
             
             StreamBuilder<DocumentSnapshot>(
              stream: iaMarksStream,
              builder: (context, snapshot) {
                 if (snapshot.connectionState == ConnectionState.waiting) {
                   return const Center(child: CircularProgressIndicator.adaptive());
                 }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(child: Text("Raw IA marks not found."));
                }
                final data = snapshot.data!.data() as Map<String, dynamic>;
                
                // Get raw input marks
                final ia1 = data['ia_1']?.toString() ?? '-';
                final ia2 = data['ia_2']?.toString() ?? '-';
                final ia3 = data['ia_3']?.toString() ?? '-';
                final projAssign = data['projectOrAssignment']?.toString() ?? '-';
                
                return Column(
                  children: [
                    _buildBreakdownRow(context, 'IA 1 (Max $maxIA)', ia1, maxIA),
                    _buildBreakdownRow(context, 'IA 2 (Max $maxIA)', ia2, maxIA),
                    _buildBreakdownRow(context, 'IA 3 (Max $maxIA)', ia3, maxIA),
                    _buildBreakdownRow(context, 'Project/Assignment (Max $maxProjAssign)', projAssign, maxProjAssign),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}