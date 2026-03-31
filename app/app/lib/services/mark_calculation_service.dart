import 'dart:math'; 

class MarkCalculationService {

  // --- IA FINAL CALCULATION (LOCAL) ---
  double calculateIaFinalLocal({
      required int? ia1,
      required int? ia2,
      required int? ia3,
      required int? projectOrAssignment,
      required Map<String, dynamic> subjectData,
  }) {
    final String rule = subjectData['iaCalculationRule'] ?? 'DEFAULT_RULE';
    double finalInternalTotal = 0.0;
    
    int roundedReducedIA = 0;
    double reducedInternalValue = 0.0;
    int projAssignMarks = projectOrAssignment ?? 0;

    switch (rule) {
      case "SEM_5_6_SCHEMA": // IAs (40) -> 25 + Proj (25) = 50
        final internals = [ia1 ?? 0, ia2 ?? 0, ia3 ?? 0];
        internals.sort((a, b) => b - a); 
        final int sumBest2 = internals[0] + internals[1];
        reducedInternalValue = (sumBest2 / 80.0) * 25.0; 
        roundedReducedIA = reducedInternalValue.ceil(); // Ceiling Rounding
        finalInternalTotal = (roundedReducedIA + projAssignMarks).toDouble();
        break;

      case "SEM_SPECIAL_100_MARK_SCHEMA": // IAs (30) -> 25 + Proj (25) = 50
        final internals = [ia1 ?? 0, ia2 ?? 0, ia3 ?? 0];
        internals.sort((a, b) => b - a); 
        final int sumBest2 = internals[0] + internals[1];
        
        reducedInternalValue = (sumBest2 / 60.0) * 25.0; 

        roundedReducedIA = reducedInternalValue.ceil(); // Ceiling Rounding
        
        finalInternalTotal = (roundedReducedIA + projAssignMarks).toDouble();
        break;

      case "BEST_2_OF_3_AVG": // IAs (25) -> 15 + Assign (10) + Lab (25) = 50
        final internals = [ia1 ?? 0, ia2 ?? 0, ia3 ?? 0];
        internals.sort((a, b) => b - a); 
        final double best_2_avg = (internals[0] + internals[1]) / 2.0;

        final int baseMax = subjectData['baseInternalMax'] ?? 25;
        final int targetMax = subjectData['maxInternalTotal'] ?? 15; 
        final int assignMax = subjectData['maxAssignment'] ?? 10;
        
        reducedInternalValue = (best_2_avg / baseMax) * targetMax;
        final int assignMarks = (projAssignMarks).clamp(0, assignMax);
        final int labMarks = 0; 

        finalInternalTotal = reducedInternalValue + assignMarks + labMarks; 
        break;

      default:
        finalInternalTotal = 0.0;
        break;
    }

    return finalInternalTotal.clamp(0.0, 50.0);
  }

  // --- TOTAL MARKS CALCULATION (LOCAL) ---
  double calculateTotalMarksLocal({
    required double? iaFinal, 
    required int? examFinal, 
    required Map<String, dynamic> subjectData,
  }) {
     final String rule = subjectData['finalExamRule'] ?? 'DEFAULT_RULE';
     double calculatedTotal = 0.0; 
     final double finalIA = iaFinal ?? 0.0; 
     final int finalExam = examFinal ?? 0;
     int roundedReducedExam = 0;
     double reducedExamValue = 0.0;

     switch (rule) {
      case "HUNDRED_REDUCED_TO_FIFTY":
        reducedExamValue = finalExam / 2.0;
        roundedReducedExam = reducedExamValue.ceil(); // Ceiling Rounding
        calculatedTotal = finalIA + roundedReducedExam; 
        break;
      
      case "THIRTY_THIRTY_RAW": 
        final int maxExamTotal = subjectData['maxExamTotal'] ?? 50;
        final int maxExamInput = subjectData['maxExamInput'] ?? 50; 

        reducedExamValue = (finalExam / maxExamInput) * maxExamTotal;
        roundedReducedExam = reducedExamValue.ceil();
        
        calculatedTotal = finalIA + roundedReducedExam; 
        break;

      case "FIFTY_FIFTY_RAW":
         calculatedTotal = finalIA + finalExam;
         break;

      default:
        calculatedTotal = 0.0;
        break;
     }

     return calculatedTotal.clamp(0.0, 100.0);
  } 

}