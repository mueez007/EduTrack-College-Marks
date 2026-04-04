const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();

/**
 * TRIGGER 1:
 * Calculates IA Final marks when IA 1, 2, 3, or project marks are entered.
 * Uses the SEM_5_6_SCHEMA logic with correct rounding.
 */
exports.calculateInternalMarks = functions.firestore
  .document("marks/{markId}")
  .onWrite(async (change, context) => {
    const data = change.after.data();
    if (!data) return null; // Exit if document was deleted

    // Get the subject's calculation rules from its document
    const subjectDoc = await data.subjectRef.get();
    if (!subjectDoc.exists) {
      console.log("Subject document does not exist.");
      return null;
    }
    const subjectData = subjectDoc.data();
    const rule = subjectData.iaCalculationRule;

    let finalInternalTotal = 0;

    // --- LOGIC SWITCH ---
    // This is where we will add more rules for other sems later
    switch (rule) {
      case "SEM_5_6_SCHEMA":
        const internals = [data.ia_1 || 0, data.ia_2 || 0, data.ia_3 || 0];
        internals.sort((a, b) => b - a); // Sort descending [38, 35, 30]

        // 1. Get Sum of Best 2 (e.g., 35 + 38 = 73)
        const sumBest2 = internals[0] + internals[1];
        
        // 2. Reduce. Base is 80 (40+40), Target is 25.
        // (73 / 80) * 25 = 22.8125
        const reducedIA = (sumBest2 / 80) * 25;
        
        // 3. Round to nearest whole number (e.g., 22.8125 -> 23)
        const roundedReducedIA = Math.round(reducedIA);

        // 4. Add project marks (e.g., 22)
        const projectMarks = data.projectOrAssignment || 0;
        finalInternalTotal = roundedReducedIA + projectMarks; // e.g., 23 + 22 = 45

        // 5. Write the final calculated data back
        return change.after.ref.set(
          {
            calculated_iaFinal: finalInternalTotal,
          },
          { merge: true }
        );
      
      // We will add more "case" statements here for your other semester rules
      // case "SEM_1_2_LOGIC":
      //   ...
      //   break;

      default:
        console.log(`No matching IA rule found for: ${rule}. Skipping.`);
        return null;
    }
  });

/**
 * TRIGGER 2:
 * Calculates Total marks when Final Exam mark is entered.
 * Uses the HUNDRED_REDUCED_TO_FIFTY logic with rounding.
 */
exports.calculateFinalGrade = functions.firestore
  .document("finalExamMarks/{markId}")
  .onWrite(async (change, context) => {
    const data = change.after.data();
    if (!data) return null;

    // Get the subject's rule for final exam
    const subjectDoc = await data.subjectRef.get();
    if (!subjectDoc.exists) {
      console.log("Subject document does not exist.");
      return null;
    }
    const subjectData = subjectDoc.data();
    const rule = subjectData.finalExamRule;

    let calculated_total = 0;
    const iaFinal = data.iaFinal || 0;     // e.g., 48
    const examFinal = data.examFinal || 0; // e.g., 99 (out of 100)

    switch (rule) {
      case "HUNDRED_REDUCED_TO_FIFTY":
        // 1. Divide by 2 (e.g., 99 / 2 = 49.5)
        const reducedExam = examFinal / 2;

        // 2. Round to nearest whole number (e.g., 49.5 -> 50)
        const roundedReducedExam = Math.round(reducedExam);

        // 3. Add to iaFinal (e.g., 48 + 50 = 98)
        calculated_total = iaFinal + roundedReducedExam;

        return change.after.ref.set(
          {
            calculated_total: calculated_total,
          },
          { merge: true }
        );

      // We can add other final exam rules here if needed
      
      default:
        console.log(`No matching exam rule found for: ${rule}. Skipping.`);
        return null;
    }
  });


/**
 * VTU Grade Point Mapping (CBCS scheme for engineering students in Karnataka)
 * Maps % of marks (scaled to 100) to grade points
 *
 *   O  (Outstanding)   : 90-100 → GP 10
 *   A+ (Excellent)     : 80-89  → GP 9
 *   A  (Very Good)     : 70-79  → GP 8
 *   B+ (Good)          : 60-69  → GP 7
 *   B  (Above Average) : 55-59  → GP 6
 *   C  (Average)       : 50-54  → GP 5
 *   P  (Pass)          : 40-49  → GP 4
 *   F  (Fail)          : 0-39   → GP 0
 */
function getVtuGradePoint(marksPercentage) {
  if (marksPercentage >= 90) return 10;  // O  - Outstanding
  if (marksPercentage >= 80) return 9;   // A+ - Excellent
  if (marksPercentage >= 70) return 8;   // A  - Very Good
  if (marksPercentage >= 60) return 7;   // B+ - Good
  if (marksPercentage >= 55) return 6;   // B  - Above Average
  if (marksPercentage >= 50) return 5;   // C  - Average
  if (marksPercentage >= 40) return 4;   // P  - Pass
  return 0;                              // F  - Fail
}

/**
 * TRIGGER 3 (CALLABLE):
 * Calculates SGPA and CGPA for all students in a semester.
 * Uses VTU Credit-Based SGPA Formula: SGPA = Σ(Ci × Gi) / Σ(Ci)
 * This is triggered by the teacher pressing a button in the app.
 */
exports.calculateSemesterResults = functions.https.onCall(async (data) => {
  
  // App sends: { batchYear: "2023_Batch", semester: 5 }
  const { batchYear, semester } = data; 
  if (!batchYear || !semester) {
    throw new functions.https.HttpsError('invalid-argument', 'batchYear and semester are required.');
  }

  try {
    // 1. Fetch all subjects for this batch/semester to get credits and maxSubjectTotal
    const subjectsSnapshot = await db.collection("subjects")
                                    .where("batchYear", "==", batchYear)
                                    .where("semester", "==", semester).get();
    
    // Build a map: subjectDocRef.path -> { credits, maxSubjectTotal }
    const subjectInfoMap = {};
    for (const subDoc of subjectsSnapshot.docs) {
      const subData = subDoc.data();
      subjectInfoMap[subDoc.ref.path] = {
        credits: subData.credits || 0,
        maxSubjectTotal: subData.maxSubjectTotal || 100,
      };
    }

    // 2. Get all students in the batch
    const students = await db.collection("students")
                            .where("batchYear", "==", batchYear).get();

    for (const studentDoc of students.docs) {
      const student = studentDoc.data();
      
      // 3. Find all their final marks for that semester
      const marksQuery = await db.collection("finalExamMarks")
                                .where("studentRef", "==", studentDoc.ref)
                                .where("semester", "==", semester).get();
      
      let totalMarksObtained = 0;
      let sumCreditGradeProduct = 0; // Σ(Ci × Gi)
      let sumCredits = 0;             // Σ(Ci)
      
      for (const doc of marksQuery.docs) {
        const markData = doc.data();
        const calculatedTotal = markData.calculated_total || 0;
        totalMarksObtained += calculatedTotal;
        
        // Get subject info (credits and maxSubjectTotal)
        let credits = 0;
        let maxSubjectTotal = 100;
        
        if (markData.subjectRef) {
          const subjectPath = markData.subjectRef.path;
          if (subjectInfoMap[subjectPath]) {
            credits = subjectInfoMap[subjectPath].credits;
            maxSubjectTotal = subjectInfoMap[subjectPath].maxSubjectTotal;
          }
        }
        
        // Scale marks to 100 if maxSubjectTotal is not 100
        let scaledMarks = calculatedTotal;
        if (maxSubjectTotal !== 100 && maxSubjectTotal > 0) {
          scaledMarks = (calculatedTotal / maxSubjectTotal) * 100;
        }
        
        // Get VTU grade point and accumulate
        const gradePoint = getVtuGradePoint(scaledMarks);
        sumCreditGradeProduct += (credits * gradePoint);
        sumCredits += credits;
      }
      
      // 4. --- SGPA LOGIC (VTU Credit-Based) ---
      // SGPA = Σ(Ci × Gi) / Σ(Ci)
      let sgpa = 0;
      if (sumCredits > 0) {
        sgpa = sumCreditGradeProduct / sumCredits;
        // Truncate to 2 decimal places (no rounding)
        sgpa = Math.floor(sgpa * 100) / 100;
      }
      
      // 5. --- CGPA LOGIC ---
      const prevResultsQuery = await db.collection("semesterResults")
                                      .where("studentId", "==", studentDoc.id)
                                      .where("semester", "<", semester).get();
                                      
      let sgpaSum = sgpa; // Start with the new, current SGPA
      let semesterCount = 1;
      
      for (const doc of prevResultsQuery.docs) {
        sgpaSum += doc.data().sgpa;
        semesterCount++;
      }
      
      // (Sem1 + Sem2 + Sem3) / 3
      let cgpa = sgpaSum / semesterCount;
      // Truncate to 2 decimal places
      cgpa = Math.floor(cgpa * 100) / 100;
      
      // 6. Save the final results
      const resultDocId = `${studentDoc.id}_S${semester}`;
      await db.collection("semesterResults").doc(resultDocId).set({
        batchYear: batchYear,
        semester: semester,
        studentId: studentDoc.id,
        studentName: student.name, // Store name for easier sorting
        usn: student.usn,
        totalMarksObtained: totalMarksObtained,
        totalCredits: sumCredits,
        sgpa: sgpa,
        cgpa: cgpa
      });
    }
    
    return { status: "success", message: `Results calculated for ${students.docs.length} students.` };

  } catch (error) {
    console.error("Error calculating semester results:", error);
    throw new functions.https.HttpsError('unknown', 'Failed to calculate results.', error);
  }
});