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
 * TRIGGER 3 (CALLABLE):
 * Calculates SGPA and CGPA for all students in a semester.
 * This is triggered by the teacher pressing a button in the app.
 */
exports.calculateSemesterResults = functions.https.onCall(async (data) => {
  
  // App sends: { batchYear: "2023_Batch", semester: 5 }
  const { batchYear, semester } = data; 
  if (!batchYear || !semester) {
    throw new functions.https.HttpsError('invalid-argument', 'batchYear and semester are required.');
  }

  try {
    const students = await db.collection("students")
                            .where("batchYear", "==", batchYear).get();

    for (const studentDoc of students.docs) {
      const student = studentDoc.data();
      
      // 1. Find all their final marks for that semester
      const marksQuery = await db.collection("finalExamMarks")
                                .where("studentRef", "==", studentDoc.ref)
                                .where("semester", "==", semester).get();
      
      let totalMarksObtained = 0;
      let subjectCount = marksQuery.docs.length;
      
      for (const doc of marksQuery.docs) {
        totalMarksObtained += doc.data().calculated_total || 0;
      }
      
      // 2. --- SGPA LOGIC ---
      let sgpa = 0;
      if (subjectCount > 0) {
        // (Total / MaxTotal) * 10
        // e.g., (640 / 800) * 10 = 8.0
        const totalMaxMarks = subjectCount * 100;
        sgpa = (totalMarksObtained / totalMaxMarks) * 10;
      }
      
      // 3. --- CGPA LOGIC ---
      const prevResultsQuery = await db.collection("semesterResults")
                                      .where("studentRef", "==", studentDoc.ref)
                                      .where("semester", "<", semester).get();
                                      
      let sgpaSum = sgpa; // Start with the new, current SGPA
      let semesterCount = 1;
      
      for (const doc of prevResultsQuery.docs) {
        sgpaSum += doc.data().sgpa;
        semesterCount++;
      }
      
      // (Sem1 + Sem2 + Sem3) / 3
      const cgpa = sgpaSum / semesterCount;
      
      // 4. Save the final results
      const resultDocId = `${student.usn}_S${semester}`;
      await db.collection("semesterResults").doc(resultDocId).set({
        batchYear: batchYear,
        semester: semester,
        studentRef: studentDoc.ref,
        studentName: student.name, // Store name for easier sorting
        totalMarksObtained: totalMarksObtained,
        totalMaxMarks: subjectCount * 100,
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