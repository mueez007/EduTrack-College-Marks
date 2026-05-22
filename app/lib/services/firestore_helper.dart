import 'package:cloud_firestore/cloud_firestore.dart';

/// Centralized Firestore accessor that scopes all queries
/// to the selected department's subcollection.
///
/// Usage:
/// ```dart
/// final studentsRef = FirestoreHelper.deptCollection(departmentId, 'students');
/// ```
///
/// This replaces all direct `FirebaseFirestore.instance.collection('students')`
/// calls with department-scoped `departments/{deptId}/students`.
class FirestoreHelper {
  FirestoreHelper._(); // Prevent instantiation

  /// Get a department-scoped collection reference.
  ///
  /// For example, `deptCollection('CSE_AIML', 'students')` returns a reference
  /// to `departments/CSE_AIML/students`.
  static CollectionReference deptCollection(
    String departmentId,
    String collectionName,
  ) {
    return FirebaseFirestore.instance
        .collection('departments')
        .doc(departmentId)
        .collection(collectionName);
  }

  /// Get a department-scoped document reference.
  ///
  /// For example, `deptDoc('CSE_AIML', 'students', '2023_USN001')` returns
  /// a reference to `departments/CSE_AIML/students/2023_USN001`.
  static DocumentReference deptDoc(
    String departmentId,
    String collectionName,
    String docId,
  ) {
    return deptCollection(departmentId, collectionName).doc(docId);
  }

  /// Alias for deptDoc — used for clarity when storing a document
  /// reference as a field value in another document.
  static DocumentReference deptDocRef(
    String departmentId,
    String collectionName,
    String docId,
  ) {
    return deptDoc(departmentId, collectionName, docId);
  }
}
