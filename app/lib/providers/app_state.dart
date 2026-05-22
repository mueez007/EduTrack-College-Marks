import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AppState with ChangeNotifier {
  String? _selectedBatchId;
  String? _selectedBatchName;
  String? _departmentId;
  String? _departmentName;
  bool _isAdmin = false;
  String? _userEmail;

  String? get selectedBatchId => _selectedBatchId;
  String? get selectedBatchName => _selectedBatchName;
  String? get departmentId => _departmentId;
  String? get departmentName => _departmentName;
  bool get isAdmin => _isAdmin;
  String? get userEmail => _userEmail;

  void setSelectedBatch(String batchId, String batchName) {
    _selectedBatchId = batchId;
    _selectedBatchName = batchName;
    notifyListeners(); // Notify widgets listening to this state
    print("AppState Updated: Batch ID = $_selectedBatchId, Name = $_selectedBatchName");
  }

  void setDepartment(String departmentId, String departmentName) {
    _departmentId = departmentId;
    _departmentName = departmentName;
    notifyListeners();
    print("AppState Updated: Department ID = $_departmentId, Name = $_departmentName");
  }

  void setAdminMode(bool isAdmin) {
    _isAdmin = isAdmin;
    notifyListeners();
    print("AppState Updated: Admin Mode = $_isAdmin");
  }

  void setUserEmail(String? email) {
    _userEmail = email;
    notifyListeners();
  }

  void clearSelectedBatch() {
     _selectedBatchId = null;
     _selectedBatchName = null;
     notifyListeners();
     print("AppState Cleared: Batch selection removed.");
  }

  /// Clear all state on full logout.
  void clearAll() {
    _selectedBatchId = null;
    _selectedBatchName = null;
    _departmentId = null;
    _departmentName = null;
    _isAdmin = false;
    _userEmail = null;
    notifyListeners();
    print("AppState Cleared: All state removed.");
  }

  /// Convenience: Get a department-scoped collection reference.
  /// Returns null if no department is selected.
  CollectionReference? deptCollection(String collectionName) {
    if (_departmentId == null) return null;
    return FirebaseFirestore.instance
        .collection('departments')
        .doc(_departmentId!)
        .collection(collectionName);
  }
}