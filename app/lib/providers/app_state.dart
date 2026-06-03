import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppState with ChangeNotifier {
  String? _selectedBatchId;
  String? _selectedBatchName;
  String? _departmentId;
  String? _departmentName;
  bool _isAdmin = false;
  String? _userEmail;
  String? _userRole; // 'admin', 'teacher', 'student'
  String? _studentUsn; // Only for student login

  // SharedPreferences keys
  static const _keyBatchId = 'session_batchId';
  static const _keyBatchName = 'session_batchName';
  static const _keyDeptId = 'session_deptId';
  static const _keyDeptName = 'session_deptName';
  static const _keyIsAdmin = 'session_isAdmin';
  static const _keyUserEmail = 'session_userEmail';
  static const _keyUserRole = 'session_userRole';
  static const _keyStudentUsn = 'session_studentUsn';

  String? get selectedBatchId => _selectedBatchId;
  String? get selectedBatchName => _selectedBatchName;
  String? get departmentId => _departmentId;
  String? get departmentName => _departmentName;
  bool get isAdmin => _isAdmin;
  String? get userEmail => _userEmail;
  String? get userRole => _userRole;
  String? get studentUsn => _studentUsn;

  /// Returns true if a valid session exists (user has logged in before).
  bool get isLoggedIn => _userRole != null && _userRole!.isNotEmpty;

  /// Initialize from persisted storage. Call once on app startup.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedBatchId = prefs.getString(_keyBatchId);
    _selectedBatchName = prefs.getString(_keyBatchName);
    _departmentId = prefs.getString(_keyDeptId);
    _departmentName = prefs.getString(_keyDeptName);
    _isAdmin = prefs.getBool(_keyIsAdmin) ?? false;
    _userEmail = prefs.getString(_keyUserEmail);
    _userRole = prefs.getString(_keyUserRole);
    _studentUsn = prefs.getString(_keyStudentUsn);
    notifyListeners();
    debugPrint("AppState Restored: role=$_userRole, dept=$_departmentId, batch=$_selectedBatchId");
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    _setOrRemove(prefs, _keyBatchId, _selectedBatchId);
    _setOrRemove(prefs, _keyBatchName, _selectedBatchName);
    _setOrRemove(prefs, _keyDeptId, _departmentId);
    _setOrRemove(prefs, _keyDeptName, _departmentName);
    await prefs.setBool(_keyIsAdmin, _isAdmin);
    _setOrRemove(prefs, _keyUserEmail, _userEmail);
    _setOrRemove(prefs, _keyUserRole, _userRole);
    _setOrRemove(prefs, _keyStudentUsn, _studentUsn);
  }

  void _setOrRemove(SharedPreferences prefs, String key, String? value) {
    if (value != null) {
      prefs.setString(key, value);
    } else {
      prefs.remove(key);
    }
  }

  void setSelectedBatch(String batchId, String batchName) {
    _selectedBatchId = batchId;
    _selectedBatchName = batchName;
    notifyListeners();
    _save();
    debugPrint("AppState Updated: Batch ID = $_selectedBatchId, Name = $_selectedBatchName");
  }

  void setDepartment(String departmentId, String departmentName) {
    _departmentId = departmentId;
    _departmentName = departmentName;
    notifyListeners();
    _save();
    debugPrint("AppState Updated: Department ID = $_departmentId, Name = $_departmentName");
  }

  void setAdminMode(bool isAdmin) {
    _isAdmin = isAdmin;
    notifyListeners();
    _save();
    debugPrint("AppState Updated: Admin Mode = $_isAdmin");
  }

  void setUserEmail(String? email) {
    _userEmail = email;
    notifyListeners();
    _save();
  }

  void setUserRole(String? role) {
    _userRole = role;
    notifyListeners();
    _save();
    debugPrint("AppState Updated: User Role = $_userRole");
  }

  void setStudentUsn(String? usn) {
    _studentUsn = usn;
    notifyListeners();
    _save();
    debugPrint("AppState Updated: Student USN = $_studentUsn");
  }

  void clearSelectedBatch() {
     _selectedBatchId = null;
     _selectedBatchName = null;
     notifyListeners();
     _save();
     debugPrint("AppState Cleared: Batch selection removed.");
  }

  /// Clear all state on full logout.
  void clearAll() {
    _selectedBatchId = null;
    _selectedBatchName = null;
    _departmentId = null;
    _departmentName = null;
    _isAdmin = false;
    _userEmail = null;
    _userRole = null;
    _studentUsn = null;
    notifyListeners();
    _save();
    debugPrint("AppState Cleared: All state removed.");
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