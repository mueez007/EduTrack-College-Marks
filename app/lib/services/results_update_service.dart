import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_helper.dart';
import 'results_calculation_service.dart';
import 'mark_calculation_service.dart';

/// Service for client-side selective SGPA/CGPA recalculation.
///
/// This replaces Cloud Functions triggers entirely. Recalculation is called
/// ONLY when a teacher saves marks — never on login, screen open, or build().
///
/// Two main operations:
/// 1. [recalculateStudentSemester] — selective: 1 student, 1 semester, propagates CGPA forward
/// 2. [backfillBatchSemester] — batch: all students in a batch for 1 semester (one-time migration)
class ResultsUpdateService {
  final ResultsCalculationService _resultsCalc = ResultsCalculationService();
  final MarkCalculationService _markCalc = MarkCalculationService();

  /// Truncate a double to specific decimal places (VTU truncation rule)
  double _truncateToDecimal(double value, int fractionDigits) {
    int factor = 1;
    for (int i = 0; i < fractionDigits; i++) {
      factor *= 10;
    }
    return (value * factor).floor() / factor;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SELECTIVE RECALCULATION: 1 student, 1 semester
  // ─────────────────────────────────────────────────────────────────────────

  /// Recalculates SGPA for [studentId] in [semester], then propagates CGPA
  /// forward from [semester] to semester 8.
  ///
  /// Called after a teacher saves marks (IA or exam). Total cost: ~4 reads + ~1-8 writes.
  Future<void> recalculateStudentSemester({
    required String deptId,
    required String studentId,
    required int semester,
    required String batchYear,
  }) async {
    try {
      // 1. Fetch student details
      final studentDoc = await FirestoreHelper.deptDoc(deptId, 'students', studentId).get();
      if (!studentDoc.exists) return;
      final studentData = studentDoc.data() as Map<String, dynamic>;

      // 2. Fetch all subjects for this semester (for credits and maxSubjectTotal)
      final subjectsSnapshot = await FirestoreHelper.deptCollection(deptId, 'subjects')
          .where('batchYear', isEqualTo: batchYear)
          .where('semester', isEqualTo: semester)
          .get();

      final Map<String, Map<String, dynamic>> subjectInfoMap = {};
      for (final subDoc in subjectsSnapshot.docs) {
        final subData = subDoc.data() as Map<String, dynamic>;
        subjectInfoMap[subDoc.reference.path] = {
          'credits': subData['credits'] ?? 0,
          'maxSubjectTotal': subData['maxSubjectTotal'] ?? 100,
        };
      }

      // 3. Fetch all finalExamMarks for this student + semester
      final studentRef = FirestoreHelper.deptDocRef(deptId, 'students', studentId);
      final marksSnapshot = await FirestoreHelper.deptCollection(deptId, 'finalExamMarks')
          .where('studentRef', isEqualTo: studentRef)
          .where('semester', isEqualTo: semester)
          .get();

      // 4. Calculate SGPA
      int totalMarksObtained = 0;
      double sumCreditGradeProduct = 0;
      int sumCredits = 0;

      for (final doc in marksSnapshot.docs) {
        final markData = doc.data() as Map<String, dynamic>;
        final double calculatedTotal = (markData['calculated_total'] as num?)?.toDouble() ?? 0.0;
        totalMarksObtained += calculatedTotal.round();

        int credits = 0;
        int maxSubjectTotal = 100;

        if (markData['subjectRef'] != null) {
          final subjectPath = (markData['subjectRef'] as DocumentReference).path;
          if (subjectInfoMap.containsKey(subjectPath)) {
            credits = subjectInfoMap[subjectPath]!['credits'] as int;
            maxSubjectTotal = subjectInfoMap[subjectPath]!['maxSubjectTotal'] as int;
          }
        }

        double scaledMarks = calculatedTotal;
        if (maxSubjectTotal != 100 && maxSubjectTotal > 0) {
          scaledMarks = (calculatedTotal / maxSubjectTotal) * 100.0;
        }

        final int gradePoint = _resultsCalc.getGradePoint(scaledMarks);
        sumCreditGradeProduct += (credits * gradePoint);
        sumCredits += credits;
      }

      double sgpa = 0.0;
      if (sumCredits > 0) {
        sgpa = sumCreditGradeProduct / sumCredits;
        sgpa = _truncateToDecimal(sgpa, 2);
      }

      // 5. Fetch ALL existing semester results for this student (for CGPA propagation)
      final prevResultsSnapshot = await FirestoreHelper.deptCollection(deptId, 'semesterResults')
          .where('studentId', isEqualTo: studentId)
          .get();

      final Map<int, Map<String, dynamic>> resultsMap = {};
      for (final doc in prevResultsSnapshot.docs) {
        final rData = doc.data() as Map<String, dynamic>;
        final int sem = (rData['semester'] as num).toInt();
        resultsMap[sem] = rData;
      }

      // 6. Propagate CGPA from affected semester forward to semester 8
      double sgpaSum = 0;
      int semesterCount = 0;

      for (int s = 1; s <= 8; s++) {
        double currentSemSgpa = 0.0;
        int currentSemTotalMarks = 0;
        int currentSemCredits = 0;

        if (s == semester) {
          currentSemSgpa = sgpa;
          currentSemTotalMarks = totalMarksObtained;
          currentSemCredits = sumCredits;
        } else if (resultsMap.containsKey(s)) {
          currentSemSgpa = (resultsMap[s]!['sgpa'] as num?)?.toDouble() ?? 0.0;
          currentSemTotalMarks = (resultsMap[s]!['totalMarksObtained'] as num?)?.toInt() ?? 0;
          currentSemCredits = (resultsMap[s]!['totalCredits'] as num?)?.toInt() ?? 0;
        } else {
          if (s > semester) break; // Stop at future semesters with no data
          continue; // Skip earlier semesters with no data
        }

        sgpaSum += currentSemSgpa;
        semesterCount++;

        double cgpa = sgpaSum / semesterCount;
        cgpa = _truncateToDecimal(cgpa, 2);

        final resultDocId = '${studentId}_S$s';
        await FirestoreHelper.deptDoc(deptId, 'semesterResults', resultDocId).set({
          'batchYear': batchYear,
          'semester': s,
          'studentId': studentId,
          'studentName': studentData['name'],
          'usn': studentData['usn'],
          'totalMarksObtained': currentSemTotalMarks,
          'totalCredits': currentSemCredits,
          'sgpa': currentSemSgpa,
          'cgpa': cgpa,
          'lastCalculated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      print('[ResultsUpdateService] Error recalculating student $studentId semester $semester: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BATCH BACKFILL: All students in a batch for 1 semester
  // ─────────────────────────────────────────────────────────────────────────

  /// Recalculates SGPA/CGPA for ALL students in a batch for one semester.
  /// Used for one-time migration / "Recalculate All" button.
  ///
  /// Uses bulk queries + in-memory processing + WriteBatch for efficiency.
  /// Returns a status message string.
  Future<String> backfillBatchSemester({
    required String deptId,
    required String batchYear,
    required int semester,
  }) async {
    try {
      // 1. Fetch all students for this batch
      final studentsSnapshot = await FirestoreHelper.deptCollection(deptId, 'students')
          .where('batchYear', isEqualTo: batchYear)
          .get();

      if (studentsSnapshot.docs.isEmpty) {
        return 'No students found for this batch.';
      }

      // 2. Fetch all subjects for this semester
      final subjectsSnapshot = await FirestoreHelper.deptCollection(deptId, 'subjects')
          .where('batchYear', isEqualTo: batchYear)
          .where('semester', isEqualTo: semester)
          .get();

      final Map<String, Map<String, dynamic>> subjectInfoMap = {};
      for (final subDoc in subjectsSnapshot.docs) {
        final subData = subDoc.data() as Map<String, dynamic>;
        subjectInfoMap[subDoc.reference.path] = {
          'credits': subData['credits'] ?? 0,
          'maxSubjectTotal': subData['maxSubjectTotal'] ?? 100,
          'subjectData': subData,
        };
      }

      // 3. Fetch ALL finalExamMarks for this batch + semester (single query)
      final allFinalMarksSnapshot = await FirestoreHelper.deptCollection(deptId, 'finalExamMarks')
          .where('batchYear', isEqualTo: batchYear)
          .where('semester', isEqualTo: semester)
          .get();

      // 4. Fetch ALL internal marks for this batch + semester (for auto-repair)
      final allInternalMarksSnapshot = await FirestoreHelper.deptCollection(deptId, 'marks')
          .where('batchYear', isEqualTo: batchYear)
          .where('semester', isEqualTo: semester)
          .get();

      // Index internal marks by doc ID
      final Map<String, Map<String, dynamic>> internalMarksMap = {};
      for (final doc in allInternalMarksSnapshot.docs) {
        internalMarksMap[doc.id] = doc.data() as Map<String, dynamic>;
      }

      // Index final marks by student ref path
      final Map<String, List<Map<String, dynamic>>> finalMarksPerStudent = {};
      for (final doc in allFinalMarksSnapshot.docs) {
        final markData = doc.data() as Map<String, dynamic>;
        if (markData['studentRef'] != null) {
          final studentPath = (markData['studentRef'] as DocumentReference).path;
          finalMarksPerStudent.putIfAbsent(studentPath, () => []);
          finalMarksPerStudent[studentPath]!.add({
            'id': doc.id,
            ...markData,
          });
        }
      }

      int processedCount = 0;
      int skippedCount = 0;
      final writeBatch = FirebaseFirestore.instance.batch();

      // 5. Process each student
      for (final studentDoc in studentsSnapshot.docs) {
        final studentData = studentDoc.data() as Map<String, dynamic>;
        final studentId = studentDoc.id;
        final studentPath = studentDoc.reference.path;

        final studentFinalMarks = finalMarksPerStudent[studentPath] ?? [];

        if (studentFinalMarks.isEmpty) {
          skippedCount++;
          continue;
        }

        int totalMarksObtained = 0;
        double sumCreditGradeProduct = 0;
        int sumCredits = 0;

        for (final markData in studentFinalMarks) {
          double? calculatedTotal = (markData['calculated_total'] as num?)?.toDouble();

          // AUTO-REPAIR: If calculated_total is missing but we have iaFinal + examFinal, compute it
          if (calculatedTotal == null &&
              markData['examFinal'] != null &&
              markData['subjectRef'] != null) {
            final subjectPath = (markData['subjectRef'] as DocumentReference).path;
            final subInfo = subjectInfoMap[subjectPath];
            if (subInfo != null) {
              final iaFinal = (markData['iaFinal'] as num?)?.toDouble() ?? 0.0;
              final examFinal = (markData['examFinal'] as num?)?.toInt() ?? 0;
              calculatedTotal = _markCalc.calculateTotalMarksLocal(
                iaFinal: iaFinal,
                examFinal: examFinal,
                subjectData: subInfo['subjectData'] as Map<String, dynamic>,
              );
              // Stage repair write
              final repairRef = FirestoreHelper.deptDoc(deptId, 'finalExamMarks', markData['id'] as String);
              writeBatch.update(repairRef, {'calculated_total': calculatedTotal});
            }
          }

          calculatedTotal ??= 0.0;
          totalMarksObtained += calculatedTotal.round();

          int credits = 0;
          int maxSubjectTotal = 100;

          if (markData['subjectRef'] != null) {
            final subjectPath = (markData['subjectRef'] as DocumentReference).path;
            if (subjectInfoMap.containsKey(subjectPath)) {
              credits = subjectInfoMap[subjectPath]!['credits'] as int;
              maxSubjectTotal = subjectInfoMap[subjectPath]!['maxSubjectTotal'] as int;
            }
          }

          double scaledMarks = calculatedTotal;
          if (maxSubjectTotal != 100 && maxSubjectTotal > 0) {
            scaledMarks = (calculatedTotal / maxSubjectTotal) * 100.0;
          }

          final int gradePoint = _resultsCalc.getGradePoint(scaledMarks);
          sumCreditGradeProduct += (credits * gradePoint);
          sumCredits += credits;
        }

        // Calculate SGPA
        double sgpa = 0.0;
        if (sumCredits > 0) {
          sgpa = sumCreditGradeProduct / sumCredits;
          sgpa = _truncateToDecimal(sgpa, 2);
        }

        // For CGPA, fetch existing results for this student
        final prevResultsSnapshot = await FirestoreHelper.deptCollection(deptId, 'semesterResults')
            .where('studentId', isEqualTo: studentId)
            .get();

        final Map<int, Map<String, dynamic>> resultsMap = {};
        for (final doc in prevResultsSnapshot.docs) {
          final rData = doc.data() as Map<String, dynamic>;
          final int sem = (rData['semester'] as num).toInt();
          resultsMap[sem] = rData;
        }

        // Calculate CGPA by averaging all known SGPAs up to this semester
        double sgpaSum = 0;
        int semesterCount = 0;

        for (int s = 1; s <= semester; s++) {
          double currentSemSgpa = 0.0;

          if (s == semester) {
            currentSemSgpa = sgpa;
          } else if (resultsMap.containsKey(s)) {
            currentSemSgpa = (resultsMap[s]!['sgpa'] as num?)?.toDouble() ?? 0.0;
          } else {
            continue;
          }

          sgpaSum += currentSemSgpa;
          semesterCount++;
        }

        double cgpa = 0.0;
        if (semesterCount > 0) {
          cgpa = sgpaSum / semesterCount;
          cgpa = _truncateToDecimal(cgpa, 2);
        }

        // Write to semesterResults via batch
        final resultDocId = '${studentId}_S$semester';
        final resultRef = FirestoreHelper.deptDoc(deptId, 'semesterResults', resultDocId);
        writeBatch.set(resultRef, {
          'batchYear': batchYear,
          'semester': semester,
          'studentId': studentId,
          'studentName': studentData['name'],
          'usn': studentData['usn'],
          'totalMarksObtained': totalMarksObtained,
          'totalCredits': sumCredits,
          'sgpa': sgpa,
          'cgpa': cgpa,
          'lastCalculated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        processedCount++;
      }

      // Commit all writes atomically
      await writeBatch.commit();

      return 'Results calculated for $processedCount students ($skippedCount skipped — no exam marks).';
    } catch (e) {
      print('[ResultsUpdateService] Backfill error: $e');
      return 'Error: ${e.toString()}';
    }
  }
}
