import 'package:cloud_firestore/cloud_firestore.dart';

/// One-time migration utility to copy root-level Firestore data
/// into department-scoped subcollections.
///
/// Usage: Call `DataMigrationService.migrateToNewStructure('CSE_AIML', onProgress)`
/// from the admin screen.
class DataMigrationService {
  DataMigrationService._();

  /// Collections to migrate from root to departments/{deptId}/...
  static const List<String> _collectionsToMigrate = [
    'batches',
    'students',
    'subjects',
    'marks',
    'ia_details',
    'ia_configs',
    'finalExamMarks',
    'absentees',
    'attendanceMonthly',
    'semesterResults',
    'publicRanks',
    'users',
    'teacher_credentials',
  ];

  /// Migrate all root-level collections into departments/{departmentId}/...
  ///
  /// [departmentId] — Target department ID (e.g. 'CSE_AIML')
  /// [onProgress]   — Callback with (collectionName, docsCopied, totalDocs)
  ///
  /// Returns total documents migrated.
  static Future<int> migrateToNewStructure(
    String departmentId, {
    void Function(String collection, int copied, int total)? onProgress,
  }) async {
    final firestore = FirebaseFirestore.instance;
    int totalMigrated = 0;

    for (final collectionName in _collectionsToMigrate) {
      try {
        // Read all docs from root collection
        final QuerySnapshot snapshot = await firestore
            .collection(collectionName)
            .get();

        final totalDocs = snapshot.docs.length;
        int copiedInCollection = 0;

        if (totalDocs == 0) {
          onProgress?.call(collectionName, 0, 0);
          continue;
        }

        // Write in batches of 400 (Firestore limit is 500 per batch)
        const batchSize = 400;
        WriteBatch batch = firestore.batch();
        int batchCount = 0;

        for (final doc in snapshot.docs) {
          final targetRef = firestore
              .collection('departments')
              .doc(departmentId)
              .collection(collectionName)
              .doc(doc.id);

          // Copy the document data as-is
          final data = doc.data() as Map<String, dynamic>;

          // For documents with reference fields (studentRef, subjectRef),
          // update them to point to the new department-scoped paths
          final updatedData = _updateReferences(data, departmentId);

          batch.set(targetRef, updatedData);
          batchCount++;
          copiedInCollection++;

          // Commit batch when it reaches the limit
          if (batchCount >= batchSize) {
            await batch.commit();
            batch = firestore.batch();
            batchCount = 0;
          }

          onProgress?.call(collectionName, copiedInCollection, totalDocs);
        }

        // Commit remaining docs
        if (batchCount > 0) {
          await batch.commit();
        }

        totalMigrated += copiedInCollection;
        print('[MIGRATION] $collectionName: $copiedInCollection/$totalDocs docs migrated');
      } catch (e) {
        print('[MIGRATION ERROR] $collectionName: $e');
        onProgress?.call('ERROR: $collectionName', -1, -1);
      }
    }

    print('[MIGRATION COMPLETE] Total: $totalMigrated documents migrated to departments/$departmentId');
    return totalMigrated;
  }

  /// Update DocumentReference fields to point to department-scoped paths.
  /// e.g. /students/ABC → /departments/CSE_AIML/students/ABC
  static Map<String, dynamic> _updateReferences(
    Map<String, dynamic> data,
    String departmentId,
  ) {
    final updated = Map<String, dynamic>.from(data);
    final firestore = FirebaseFirestore.instance;

    // Fields that contain DocumentReferences to root collections
    const refFields = ['studentRef', 'subjectRef'];

    for (final field in refFields) {
      if (updated.containsKey(field) && updated[field] is DocumentReference) {
        final oldRef = updated[field] as DocumentReference;
        // Extract the collection name and doc ID from the old reference
        // Old path: "students/docId" → New path: "departments/{dept}/students/docId"
        final pathSegments = oldRef.path.split('/');
        if (pathSegments.length == 2) {
          final oldCollection = pathSegments[0];
          final docId = pathSegments[1];
          updated[field] = firestore
              .collection('departments')
              .doc(departmentId)
              .collection(oldCollection)
              .doc(docId);
        }
      }
    }

    return updated;
  }
}
