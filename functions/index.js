const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();

// --- VTU Grade Point Mapping (CBCS Scheme) ---
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

// --- IA Internal Marks Calculation (JS Parity with Dart MarkCalculationService) ---
function calculateIaFinalLocal(ia1, ia2, ia3, projectOrAssignment, labMarks, labIaMarks, subjectData) {
  const rule = subjectData.iaCalculationRule || 'DEFAULT_RULE';
  let finalInternalTotal = 0.0;
  
  const ia_1 = ia1 !== undefined && ia1 !== null ? ia1 : 0;
  const ia_2 = ia2 !== undefined && ia2 !== null ? ia2 : 0;
  const ia_3 = ia3 !== undefined && ia3 !== null ? ia3 : 0;
  const projAssignMarks = projectOrAssignment !== undefined && projectOrAssignment !== null ? projectOrAssignment : 0;
  const lab = labMarks !== undefined && labMarks !== null ? labMarks : 0;
  const labIa = labIaMarks !== undefined && labIaMarks !== null ? labIaMarks : 0;

  switch (rule) {
    case "SEM_5_6_SCHEMA": { // IAs (40) -> 25 + Proj (25) = 50
      const internals = [ia_1, ia_2, ia_3].sort((a, b) => b - a);
      const sumBest2 = internals[0] + internals[1];
      const reducedInternalValue = (sumBest2 / 80.0) * 25.0;
      const roundedReducedIA = Math.ceil(reducedInternalValue); // Ceiling Rounding
      finalInternalTotal = roundedReducedIA + projAssignMarks;
      break;
    }
    case "SEM_SPECIAL_100_MARK_SCHEMA": { // IAs (30) -> 25 + Proj (25) = 50
      const internals = [ia_1, ia_2, ia_3].sort((a, b) => b - a);
      const sumBest2 = internals[0] + internals[1];
      const reducedInternalValue = (sumBest2 / 60.0) * 25.0;
      const roundedReducedIA = Math.ceil(reducedInternalValue); // Ceiling Rounding
      finalInternalTotal = roundedReducedIA + projAssignMarks;
      break;
    }
    case "BEST_2_OF_3_AVG": { // IAs (40) -> 15 + Assign (10) + Lab CE (15) + Lab IA (10) = 50
      const internals = [ia_1, ia_2, ia_3].sort((a, b) => b - a);
      const sumBest2 = internals[0] + internals[1];
      const reducedInternalValue = (sumBest2 / 80.0) * 15.0;
      const roundedReducedIA = Math.ceil(reducedInternalValue);
      
      const assignMax = subjectData.maxAssignment || 10;
      const assignMarks = Math.min(Math.max(projAssignMarks, 0), assignMax);
      
      const maxLab = subjectData.maxLab || 15;
      const labValue = Math.min(Math.max(lab, 0), maxLab);

      const maxLabIa = subjectData.maxLabIa || 10;
      const labIaValue = Math.min(Math.max(labIa, 0), maxLabIa);

      finalInternalTotal = roundedReducedIA + assignMarks + labValue + labIaValue;
      break;
    }
    default:
      finalInternalTotal = 0.0;
      break;
  }
  return Math.min(50.0, Math.max(0.0, finalInternalTotal));
}

// --- Total Final Marks Calculation (JS Parity with Dart MarkCalculationService) ---
function calculateTotalMarksLocal(iaFinal, examFinal, subjectData) {
  const rule = subjectData.finalExamRule || 'DEFAULT_RULE';
  let calculatedTotal = 0.0;
  const finalIA = iaFinal !== undefined && iaFinal !== null ? iaFinal : 0.0;
  const finalExam = examFinal !== undefined && examFinal !== null ? examFinal : 0;

  switch (rule) {
    case "HUNDRED_REDUCED_TO_FIFTY": {
      const reducedExamValue = finalExam / 2.0;
      const roundedReducedExam = Math.ceil(reducedExamValue); // Ceiling Rounding
      calculatedTotal = finalIA + roundedReducedExam;
      break;
    }
    case "THIRTY_THIRTY_RAW": {
      const maxExamTotal = subjectData.maxExamTotal || 50;
      const maxExamInput = subjectData.maxExamInput || 50;
      const reducedExamValue = (finalExam / maxExamInput) * maxExamTotal;
      const roundedReducedExam = Math.ceil(reducedExamValue);
      calculatedTotal = finalIA + roundedReducedExam;
      break;
    }
    case "FIFTY_FIFTY_RAW":
      calculatedTotal = finalIA + finalExam;
      break;
    default:
      calculatedTotal = 0.0;
      break;
  }
  return Math.min(100.0, Math.max(0.0, calculatedTotal));
}

// --- Truncate Double strictly to decimal points ---
function truncateToDecimal(value, fractionDigits) {
  const power = Math.pow(10, fractionDigits);
  return Math.floor(value * power) / power;
}

/**
 * TRIGGER 1:
 * Calculates IA Final marks when IA 1, 2, 3, or project marks are entered.
 * Listens to department-scoped collections.
 */
exports.calculateInternalMarks = functions.firestore
  .document("departments/{deptId}/marks/{markId}")
  .onWrite(async (change, context) => {
    const afterData = change.after.data();
    if (!afterData) return null; // Exit if document was deleted

    const beforeData = change.before.exists ? change.before.data() : null;
    const { deptId, markId } = context.params;

    // Fetch the subject's calculation rules from its document
    if (!afterData.subjectRef) {
      console.log(`No subjectRef in marks/${markId}. Skipping.`);
      return null;
    }
    const subjectDoc = await afterData.subjectRef.get();
    if (!subjectDoc.exists) {
      console.log(`Subject document ${afterData.subjectRef.path} does not exist.`);
      return null;
    }
    const subjectData = subjectDoc.data();

    // Check if any IA input fields actually changed (avoid re-triggering on calculated_iaFinal write)
    if (beforeData) {
      const iaFieldsSame = (
        beforeData.ia_1 === afterData.ia_1 &&
        beforeData.ia_2 === afterData.ia_2 &&
        beforeData.ia_3 === afterData.ia_3 &&
        beforeData.projectOrAssignment === afterData.projectOrAssignment &&
        beforeData.labMarks === afterData.labMarks &&
        beforeData.labIaMarks === afterData.labIaMarks
      );
      if (iaFieldsSame) {
        console.log(`IA input fields unchanged for ${markId}. Skipping recalculation.`);
        return null;
      }
    }

    // Perform local calculation with complete parity
    const finalInternalTotal = calculateIaFinalLocal(
      afterData.ia_1,
      afterData.ia_2,
      afterData.ia_3,
      afterData.projectOrAssignment,
      afterData.labMarks,
      afterData.labIaMarks,
      subjectData
    );

    console.log(`Recalculating IA Final for ${markId}: ${finalInternalTotal}`);

    // 1. Write the final calculated data back to the marks doc
    await change.after.ref.set(
      {
        calculated_iaFinal: finalInternalTotal,
      },
      { merge: true }
    );

    // 2. Propagate to the corresponding finalExamMarks document under the department
    const finalExamRef = db.collection("departments")
      .doc(deptId)
      .collection("finalExamMarks")
      .doc(markId);

    // Read the existing finalExamMarks doc to check if examFinal exists
    const existingFinalExamDoc = await finalExamRef.get();
    const existingFinalExamData = existingFinalExamDoc.exists ? existingFinalExamDoc.data() : {};

    const updatePayload = {
      iaFinal: finalInternalTotal,
      semester: afterData.semester,
      batchYear: afterData.batchYear,
      studentRef: afterData.studentRef,
      subjectRef: afterData.subjectRef,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp()
    };

    // Only recalculate total if examFinal has been entered
    const existingExamFinal = existingFinalExamData.examFinal;
    if (existingExamFinal !== undefined && existingExamFinal !== null) {
      const newTotal = calculateTotalMarksLocal(finalInternalTotal, existingExamFinal, subjectData);
      updatePayload.calculated_total = newTotal;
      console.log(`Also updating calculated_total for ${markId}: ${newTotal} (examFinal=${existingExamFinal})`);
    }

    await finalExamRef.set(updatePayload, { merge: true });

    // If we updated the total, also trigger SGPA/CGPA recalculation
    if (updatePayload.calculated_total !== undefined) {
      const oldTotal = existingFinalExamData.calculated_total;
      if (oldTotal === undefined || Math.abs(oldTotal - updatePayload.calculated_total) >= 0.01) {
        const pathSegments = afterData.studentRef.path.split('/');
        const studentId = pathSegments[pathSegments.length - 1];
        await recalculateStudentResults(db, deptId, studentId, afterData.semester, afterData.batchYear, afterData.studentRef);
      }
    }

    return null;
  });

/**
 * TRIGGER 2:
 * Calculates Total marks when Final Exam mark is entered.
 * Listens to department-scoped collections.
 * 
 * CRITICAL FIX: Uses before/after comparison to detect real changes.
 * Only recalculates when examFinal or iaFinal actually changed.
 */
exports.calculateFinalGrade = functions.firestore
  .document("departments/{deptId}/finalExamMarks/{markId}")
  .onWrite(async (change, context) => {
    const afterData = change.after.data();
    if (!afterData) return null; // Exit if document was deleted

    const beforeData = change.before.exists ? change.before.data() : null;
    const { deptId, markId } = context.params;

    // GUARD: Skip if examFinal hasn't been entered yet
    // This prevents premature calculations when only iaFinal is propagated from marks
    if (afterData.examFinal === undefined || afterData.examFinal === null) {
      console.log(`No examFinal for ${markId}. Skipping total calculation.`);
      return null;
    }

    // GUARD: Check if the fields that affect total actually changed
    if (beforeData) {
      const relevantFieldsSame = (
        beforeData.iaFinal === afterData.iaFinal &&
        beforeData.examFinal === afterData.examFinal
      );
      if (relevantFieldsSame) {
        console.log(`iaFinal and examFinal unchanged for ${markId}. Skipping.`);
        return null;
      }
    }

    if (!afterData.subjectRef) {
      console.log(`No subjectRef in finalExamMarks/${markId}. Skipping.`);
      return null;
    }
    const subjectDoc = await afterData.subjectRef.get();
    if (!subjectDoc.exists) {
      console.log(`Subject document ${afterData.subjectRef.path} does not exist.`);
      return null;
    }
    const subjectData = subjectDoc.data();

    const iaFinal = afterData.iaFinal || 0.0;
    const examFinal = afterData.examFinal || 0;

    // Calculate dynamic total marks using exact rules
    const calculated_total = calculateTotalMarksLocal(iaFinal, examFinal, subjectData);

    // GUARD: Skip if calculated_total hasn't actually changed
    const oldTotal = beforeData ? beforeData.calculated_total : undefined;
    if (oldTotal !== undefined && oldTotal !== null && Math.abs(oldTotal - calculated_total) < 0.01) {
      console.log(`Total for ${markId} unchanged at ${calculated_total}. Skipping.`);
      return null;
    }

    console.log(`Recalculating Final Grade for ${markId}: Total = ${calculated_total}`);

    // 1. Write calculated total back
    await change.after.ref.set(
      {
        calculated_total: calculated_total,
      },
      { merge: true }
    );

    // 2. Perform selective results recalculation for ONLY this student and semester
    if (!afterData.studentRef) {
      console.log(`No studentRef in finalExamMarks/${markId}. Skipping GPA recalculation.`);
      return null;
    }
    const pathSegments = afterData.studentRef.path.split('/');
    const studentId = pathSegments[pathSegments.length - 1];

    await recalculateStudentResults(db, deptId, studentId, afterData.semester, afterData.batchYear, afterData.studentRef);
    return null;
  });

// --- High Performance Selective Student GPA Calculation & Forward Propagation ---
async function recalculateStudentResults(db, deptId, studentId, semester, batchYear, studentRef) {
  console.log(`[GPA Trigger] Recalculating GPA for student ${studentId}, Semester ${semester}`);
  const deptRef = db.collection("departments").doc(deptId);

  // 1. Fetch Student Details
  const studentDoc = await studentRef.get();
  if (!studentDoc.exists) {
    console.error(`Student document ${studentRef.path} not found.`);
    return;
  }
  const studentData = studentDoc.data();

  // 2. Fetch all subjects for this semester (to read credit allocations)
  const subjectsSnapshot = await deptRef.collection("subjects")
    .where("batchYear", "==", batchYear)
    .where("semester", "==", semester)
    .get();

  const subjectInfoMap = {};
  for (const subDoc of subjectsSnapshot.docs) {
    const subData = subDoc.data();
    subjectInfoMap[subDoc.ref.path] = {
      credits: subData.credits || 0,
      maxSubjectTotal: subData.maxSubjectTotal || 100,
    };
  }

  // 3. Fetch all final exam marks for this student and semester
  const marksSnapshot = await deptRef.collection("finalExamMarks")
    .where("studentRef", "==", studentRef)
    .where("semester", "==", semester)
    .get();

  let totalMarksObtained = 0;
  let sumCreditGradeProduct = 0;
  let sumCredits = 0;

  for (const doc of marksSnapshot.docs) {
    const markData = doc.data();
    const calculatedTotal = markData.calculated_total || 0;
    totalMarksObtained += calculatedTotal;

    let credits = 0;
    let maxSubjectTotal = 100;

    if (markData.subjectRef) {
      const subjectPath = markData.subjectRef.path;
      if (subjectInfoMap[subjectPath]) {
        credits = subjectInfoMap[subjectPath].credits;
        maxSubjectTotal = subjectInfoMap[subjectPath].maxSubjectTotal;
      }
    }

    let scaledMarks = calculatedTotal;
    if (maxSubjectTotal !== 100 && maxSubjectTotal > 0) {
      scaledMarks = (calculatedTotal / maxSubjectTotal) * 100.0;
    }

    const gradePoint = getVtuGradePoint(scaledMarks);
    sumCreditGradeProduct += (credits * gradePoint);
    sumCredits += credits;
  }

  // 4. Calculate SGPA with Strict VTU Truncation to 2 decimals
  let sgpa = 0.0;
  if (sumCredits > 0) {
    sgpa = sumCreditGradeProduct / sumCredits;
    sgpa = truncateToDecimal(sgpa, 2);
  }

  console.log(`[GPA Trigger] Student: ${studentData.name} | Semester: ${semester} | Total Marks: ${totalMarksObtained} | Credits: ${sumCredits} | SGPA: ${sgpa}`);

  // 5. Query ALL results for this student to rebuild and propagate CGPA forward sequentially
  const prevResultsSnapshot = await deptRef.collection("semesterResults")
    .where("studentId", "==", studentId)
    .get();

  const resultsMap = {};
  for (const doc of prevResultsSnapshot.docs) {
    const rData = doc.data();
    resultsMap[rData.semester] = rData;
  }

  // 6. Propagate CGPA from the affected semester up to Semester 8 for this student
  let sgpaSum = 0;
  let semesterCount = 0;

  for (let s = 1; s <= 8; s++) {
    let currentSemSgpa = 0.0;
    let currentSemTotalMarks = 0;
    let currentSemCredits = 0;

    if (s === semester) {
      currentSemSgpa = sgpa;
      currentSemTotalMarks = totalMarksObtained;
      currentSemCredits = sumCredits;
    } else if (resultsMap[s]) {
      currentSemSgpa = resultsMap[s].sgpa || 0.0;
      currentSemTotalMarks = resultsMap[s].totalMarksObtained || 0;
      currentSemCredits = resultsMap[s].totalCredits || 0;
    } else {
      // If we are checking future semesters and no results exist yet, we stop propagating
      if (s > semester) break;
      continue;
    }

    sgpaSum += currentSemSgpa;
    semesterCount++;

    let cgpa = sgpaSum / semesterCount;
    cgpa = truncateToDecimal(cgpa, 2);

    const resultDocId = `${studentId}_S${s}`;
    await deptRef.collection("semesterResults").doc(resultDocId).set(
      {
        batchYear: batchYear,
        semester: s,
        studentId: studentId,
        studentName: studentData.name,
        usn: studentData.usn,
        totalMarksObtained: currentSemTotalMarks,
        totalCredits: currentSemCredits,
        sgpa: currentSemSgpa,
        cgpa: cgpa,
        lastCalculated: admin.firestore.FieldValue.serverTimestamp()
      },
      { merge: true }
    );
  }
}

/**
 * TRIGGER 3 (CALLABLE):
 * Optimized callable function to recalculate class ranks in the background.
 * Fetches semester results for the batch, sorts in-memory, assigns ranks, and saves.
 */
exports.calculateSemesterRanks = functions.https.onCall(async (data, context) => {
  const { deptId, batchYear, semester } = data;
  if (!deptId || !batchYear || !semester) {
    throw new functions.https.HttpsError('invalid-argument', 'deptId, batchYear and semester are required.');
  }

  try {
    const deptRef = db.collection("departments").doc(deptId);

    // Fetch all semesterResults for this batch and semester
    const resultsSnapshot = await deptRef.collection("semesterResults")
      .where("batchYear", "==", batchYear)
      .where("semester", "==", semester)
      .get();

    if (resultsSnapshot.empty) {
      return { status: "empty", message: "No semester results found to rank." };
    }

    const results = resultsSnapshot.docs.map(doc => ({
      id: doc.id,
      ref: doc.ref,
      ...doc.data()
    }));

    // Sort descending by CGPA primary and SGPA secondary
    results.sort((a, b) => {
      const cgpaDiff = (b.cgpa || 0) - (a.cgpa || 0);
      if (Math.abs(cgpaDiff) > 0.001) return cgpaDiff;
      return (b.sgpa || 0) - (a.sgpa || 0);
    });

    // Assign Ranks
    const batch = db.batch();
    const rankMap = {};
    let currentRank = 1;
    let lastCgpa = null;
    let lastSgpa = null;

    for (let i = 0; i < results.length; i++) {
      const current = results[i];
      let assignedRank = currentRank;

      if (i > 0 && Math.abs(current.cgpa - lastCgpa) < 0.001 && Math.abs(current.sgpa - lastSgpa) < 0.001) {
        assignedRank = results[i - 1].rank;
      } else {
        assignedRank = currentRank;
      }

      current.rank = assignedRank;
      lastCgpa = current.cgpa;
      lastSgpa = current.sgpa;
      currentRank++;

      // Stage database update in batch
      batch.update(current.ref, { rank: assignedRank });

      rankMap[`rank_of_${current.studentId}`] = assignedRank;
      rankMap[`name_of_${current.studentId}`] = current.studentName;
    }

    await batch.commit();

    // Write a public ranking aggregate summary doc
    const classAvgSgpa = results.reduce((acc, r) => acc + (r.sgpa || 0), 0) / results.length;
    const classAvgCgpa = results.reduce((acc, r) => acc + (r.cgpa || 0), 0) / results.length;

    const publicRankId = `S${semester}-${batchYear}`;
    await deptRef.collection("publicRanks").doc(publicRankId).set({
      rankList: rankMap,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      classAverageSGPA: truncateToDecimal(classAvgSgpa, 2),
      classAverageCGPA: truncateToDecimal(classAvgCgpa, 2),
    }, { merge: true });

    return { status: "success", message: `Ranks updated for ${results.length} students.` };

  } catch (error) {
    console.error("Error calculating ranks:", error);
    throw new functions.https.HttpsError('unknown', 'Failed to calculate ranks.', error);
  }
});

/**
 * CALLABLE FUNCTION 4:
 * One-time backfill function to populate `semesterResults` from existing data.
 * Teachers call this from the SGPA/CGPA screen to migrate existing marks data.
 * 
 * This recalculates SGPA/CGPA for ALL students in a batch for a specific semester
 * using the existing `finalExamMarks` and `subjects` data.
 */
exports.backfillSemesterResults = functions.https.onCall(async (data, context) => {
  const { deptId, batchYear, semester } = data;
  if (!deptId || !batchYear || semester === undefined || semester === null) {
    throw new functions.https.HttpsError('invalid-argument', 'deptId, batchYear and semester are required.');
  }

  try {
    const deptRef = db.collection("departments").doc(deptId);
    console.log(`[Backfill] Starting for dept=${deptId}, batch=${batchYear}, sem=${semester}`);

    // 1. Fetch all students for this batch
    const studentsSnapshot = await deptRef.collection("students")
      .where("batchYear", "==", batchYear)
      .get();

    if (studentsSnapshot.empty) {
      return { status: "empty", message: "No students found for this batch." };
    }

    // 2. Fetch all subjects for this semester
    const subjectsSnapshot = await deptRef.collection("subjects")
      .where("batchYear", "==", batchYear)
      .where("semester", "==", semester)
      .get();

    const subjectInfoMap = {};
    for (const subDoc of subjectsSnapshot.docs) {
      const subData = subDoc.data();
      subjectInfoMap[subDoc.ref.path] = {
        credits: subData.credits || 0,
        maxSubjectTotal: subData.maxSubjectTotal || 100,
        subjectData: subData,
      };
    }

    // 3. Fetch ALL finalExamMarks for this batch and semester
    const allFinalMarksSnapshot = await deptRef.collection("finalExamMarks")
      .where("batchYear", "==", batchYear)
      .where("semester", "==", semester)
      .get();

    // 4. Also fetch ALL internal marks for this batch and semester (to auto-calculate totals if missing)
    const allInternalMarksSnapshot = await deptRef.collection("marks")
      .where("batchYear", "==", batchYear)
      .where("semester", "==", semester)
      .get();

    // Index internal marks by doc ID
    const internalMarksMap = {};
    for (const doc of allInternalMarksSnapshot.docs) {
      internalMarksMap[doc.id] = doc.data();
    }

    // Index final marks by studentRef path
    const finalMarksPerStudent = {};
    for (const doc of allFinalMarksSnapshot.docs) {
      const markData = doc.data();
      if (markData.studentRef) {
        const studentPath = markData.studentRef.path;
        if (!finalMarksPerStudent[studentPath]) {
          finalMarksPerStudent[studentPath] = [];
        }
        finalMarksPerStudent[studentPath].push({ id: doc.id, ...markData });
      }
    }

    let processedCount = 0;
    let skippedCount = 0;
    const writeBatch = db.batch();

    // 5. Process each student
    for (const studentDoc of studentsSnapshot.docs) {
      const studentData = studentDoc.data();
      const studentId = studentDoc.id;
      const studentPath = studentDoc.ref.path;

      const studentFinalMarks = finalMarksPerStudent[studentPath] || [];

      // Skip students with no final marks for this semester
      if (studentFinalMarks.length === 0) {
        skippedCount++;
        continue;
      }

      let totalMarksObtained = 0;
      let sumCreditGradeProduct = 0;
      let sumCredits = 0;
      let needsRepair = false;

      for (const markData of studentFinalMarks) {
        let calculatedTotal = markData.calculated_total;

        // AUTO-REPAIR: If calculated_total is missing but we have iaFinal and examFinal,
        // calculate it and stage a fix write
        if ((calculatedTotal === undefined || calculatedTotal === null) && 
            markData.examFinal !== undefined && markData.examFinal !== null &&
            markData.subjectRef) {
          const subjectPath = markData.subjectRef.path;
          const subInfo = subjectInfoMap[subjectPath];
          if (subInfo) {
            const iaFinal = markData.iaFinal || 0;
            calculatedTotal = calculateTotalMarksLocal(iaFinal, markData.examFinal, subInfo.subjectData);
            // Stage a repair write to fix the finalExamMarks doc
            const repairRef = deptRef.collection("finalExamMarks").doc(markData.id);
            writeBatch.update(repairRef, { calculated_total: calculatedTotal });
            needsRepair = true;
            console.log(`[Backfill] Auto-repaired calculated_total for ${markData.id}: ${calculatedTotal}`);
          }
        }

        if (calculatedTotal === undefined || calculatedTotal === null) {
          calculatedTotal = 0;
        }

        totalMarksObtained += calculatedTotal;

        let credits = 0;
        let maxSubjectTotal = 100;

        if (markData.subjectRef) {
          const subjectPath = markData.subjectRef.path;
          if (subjectInfoMap[subjectPath]) {
            credits = subjectInfoMap[subjectPath].credits;
            maxSubjectTotal = subjectInfoMap[subjectPath].maxSubjectTotal;
          }
        }

        let scaledMarks = calculatedTotal;
        if (maxSubjectTotal !== 100 && maxSubjectTotal > 0) {
          scaledMarks = (calculatedTotal / maxSubjectTotal) * 100.0;
        }

        const gradePoint = getVtuGradePoint(scaledMarks);
        sumCreditGradeProduct += (credits * gradePoint);
        sumCredits += credits;
      }

      // Calculate SGPA
      let sgpa = 0.0;
      if (sumCredits > 0) {
        sgpa = sumCreditGradeProduct / sumCredits;
        sgpa = truncateToDecimal(sgpa, 2);
      }

      // For CGPA, fetch all existing semester results for this student
      const prevResultsSnapshot = await deptRef.collection("semesterResults")
        .where("studentId", "==", studentId)
        .get();

      const resultsMap = {};
      for (const doc of prevResultsSnapshot.docs) {
        const rData = doc.data();
        resultsMap[rData.semester] = rData;
      }

      // Calculate CGPA by averaging all known SGPAs up to this semester
      let sgpaSum = 0;
      let semesterCount = 0;

      for (let s = 1; s <= semester; s++) {
        let currentSemSgpa = 0.0;

        if (s === semester) {
          currentSemSgpa = sgpa;
        } else if (resultsMap[s]) {
          currentSemSgpa = resultsMap[s].sgpa || 0.0;
        } else {
          continue; // No data for this earlier semester
        }

        sgpaSum += currentSemSgpa;
        semesterCount++;
      }

      let cgpa = 0.0;
      if (semesterCount > 0) {
        cgpa = sgpaSum / semesterCount;
        cgpa = truncateToDecimal(cgpa, 2);
      }

      // Write to semesterResults
      const resultDocId = `${studentId}_S${semester}`;
      const resultRef = deptRef.collection("semesterResults").doc(resultDocId);
      writeBatch.set(resultRef, {
        batchYear: batchYear,
        semester: semester,
        studentId: studentId,
        studentName: studentData.name,
        usn: studentData.usn,
        totalMarksObtained: totalMarksObtained,
        totalCredits: sumCredits,
        sgpa: sgpa,
        cgpa: cgpa,
        lastCalculated: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });

      processedCount++;
    }

    // Commit all writes in a single atomic batch
    await writeBatch.commit();

    console.log(`[Backfill] Complete. Processed: ${processedCount}, Skipped: ${skippedCount}`);
    return {
      status: "success",
      message: `Results calculated for ${processedCount} students (${skippedCount} skipped - no exam marks).`
    };

  } catch (error) {
    console.error("[Backfill] Error:", error);
    throw new functions.https.HttpsError('unknown', 'Failed to backfill results.', error);
  }
});