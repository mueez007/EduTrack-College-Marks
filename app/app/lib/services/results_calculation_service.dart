import 'dart:math'; 

// Service to handle SGPA and CGPA calculations locally (per student)
class ResultsCalculationService {

  // Helper to strictly truncate a double to a specific number of decimals
  double _truncateToDecimal(double value, int fractionDigits) {
    final num power = pow(10, fractionDigits);
    final int intValue = (value * power).truncate();
    return intValue / power;
  }

  // --- SGPA CALCULATION (FIXED SIGNATURE) ---
  // Formula: (Total Marks Obtained / Actual Max Marks Sum) * 10
  double calculateSgpa({
    required int totalMarksObtained, 
    required int actualMaxMarksSum, // <-- THIS IS THE REQUIRED NAMED PARAMETER
  }) {
    if (actualMaxMarksSum == 0) return 0.0;
    
    final double preciseSgpa = (totalMarksObtained / actualMaxMarksSum) * 10.0;

    // Apply STRICT TRUNCATION (No mathematical rounding)
    return _truncateToDecimal(preciseSgpa, 2); 
  }

  // --- CGPA CALCULATION ---
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