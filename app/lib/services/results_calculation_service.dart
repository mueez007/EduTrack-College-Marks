import 'dart:math'; 

// Service to handle SGPA and CGPA calculations locally (per student)
// Uses VTU (Visvesvaraya Technological University) Credit-Based SGPA Formula
//
// VTU Grade Point Mapping (CBCS Scheme):
//   O  (Outstanding)   : 90-100 → GP 10
//   A+ (Excellent)     : 80-89  → GP 9
//   A  (Very Good)     : 70-79  → GP 8
//   B+ (Good)          : 60-69  → GP 7
//   B  (Above Average) : 55-59  → GP 6
//   C  (Average)       : 50-54  → GP 5
//   P  (Pass)          : 40-49  → GP 4
//   F  (Fail)          : 0-39   → GP 0
//
// SGPA = Σ(Ci × Gi) / Σ(Ci)
// Where Ci = credits for subject i, Gi = grade point for subject i
class ResultsCalculationService {

  // Helper to strictly truncate a double to a specific number of decimals
  double _truncateToDecimal(double value, int fractionDigits) {
    final num power = pow(10, fractionDigits);
    final int intValue = (value * power).truncate();
    return intValue / power;
  }

  // --- VTU Grade Point Mapping ---
  // Maps % of marks (scaled to 100) to VTU grade points
  int getGradePoint(double marksPercentage) {
    if (marksPercentage >= 90) return 10;  // O  - Outstanding
    if (marksPercentage >= 80) return 9;   // A+ - Excellent
    if (marksPercentage >= 70) return 8;   // A  - Very Good
    if (marksPercentage >= 60) return 7;   // B+ - Good
    if (marksPercentage >= 55) return 6;   // B  - Above Average
    if (marksPercentage >= 50) return 5;   // C  - Average
    if (marksPercentage >= 40) return 4;   // P  - Pass
    return 0;                              // F  - Fail
  }

  // --- VTU Grade Letter ---
  String getGradeLetter(double marksPercentage) {
    if (marksPercentage >= 90) return 'O';
    if (marksPercentage >= 80) return 'A+';
    if (marksPercentage >= 70) return 'A';
    if (marksPercentage >= 60) return 'B+';
    if (marksPercentage >= 55) return 'B';
    if (marksPercentage >= 50) return 'C';
    if (marksPercentage >= 40) return 'P';
    return 'F';
  }

  // --- SGPA CALCULATION (VTU Credit-Based) ---
  // Formula: SGPA = Σ(Ci × Gi) / Σ(Ci)
  //
  // Each entry in subjectResults should contain:
  //   'totalMarks': double (the calculated_total from finalExamMarks)
  //   'maxSubjectTotal': int (max possible marks for the subject, e.g. 100 or 30)
  //   'credits': int (credit weight of the subject, e.g. 2, 3, 4)
  double calculateSgpa({
    required List<Map<String, dynamic>> subjectResults,
  }) {
    if (subjectResults.isEmpty) return 0.0;

    double sumCreditGradeProduct = 0.0; // Σ(Ci × Gi)
    int sumCredits = 0;                  // Σ(Ci)

    for (var subject in subjectResults) {
      final double totalMarks = (subject['totalMarks'] as num?)?.toDouble() ?? 0.0;
      final int maxSubjectTotal = (subject['maxSubjectTotal'] as num?)?.toInt() ?? 100;
      final int credits = (subject['credits'] as num?)?.toInt() ?? 0;

      if (credits <= 0) continue; // Skip subjects with no credits

      // Convert to percentage of marks (scale to 100)
      double marksPercentage = totalMarks;
      if (maxSubjectTotal != 100 && maxSubjectTotal > 0) {
        marksPercentage = (totalMarks / maxSubjectTotal) * 100.0;
      }

      // Get VTU grade point for the percentage
      final int gradePoint = getGradePoint(marksPercentage);

      // Credit Points = Credits × Grade Point
      sumCreditGradeProduct += (credits * gradePoint);
      sumCredits += credits;
    }

    if (sumCredits == 0) return 0.0;

    // SGPA = Total Credit Points / Total Credits
    final double preciseSgpa = sumCreditGradeProduct / sumCredits;

    // Apply STRICT TRUNCATION (No mathematical rounding)
    return _truncateToDecimal(preciseSgpa, 2); 
  }

  // --- CGPA CALCULATION ---
  // Average of all semester SGPAs
  double calculateCgpa({
    required double currentSgpa,
    required List<double> previousSgpas, 
  }) {
    double sgpaSum = currentSgpa;
    int semesterCount = 1;

    for (var prevSgpa in previousSgpas) {
      sgpaSum += prevSgpa;
      semesterCount++;
    }

    final double preciseCgpa = sgpaSum / semesterCount;

    // Apply STRICT TRUNCATION (No mathematical rounding)
    return _truncateToDecimal(preciseCgpa, 2);
  }
}