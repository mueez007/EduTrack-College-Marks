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
    try {
      final prefs = SharedPreferencesAsync();
      _selectedBatchId = await prefs.getString(_keyBatchId);
      _selectedBatchName = await prefs.getString(_keyBatchName);
      _departmentId = await prefs.getString(_keyDeptId);
      _departmentName = await prefs.getString(_keyDeptName);
      _isAdmin = (await prefs.getBool(_keyIsAdmin)) ?? false;
      _userEmail = await prefs.getString(_keyUserEmail);
      _userRole = await prefs.getString(_keyUserRole);
      _studentUsn = await prefs.getString(_keyStudentUsn);
      debugPrint("AppState Restored: role=$_userRole, dept=$_departmentId, batch=$_selectedBatchId");
    } catch (e) {
      debugPrint("AppState init error (starting fresh): $e");
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = SharedPreferencesAsync();
      await _setOrRemove(prefs, _keyBatchId, _selectedBatchId);
      await _setOrRemove(prefs, _keyBatchName, _selectedBatchName);
      await _setOrRemove(prefs, _keyDeptId, _departmentId);
      await _setOrRemove(prefs, _keyDeptName, _departmentName);
      await prefs.setBool(_keyIsAdmin, _isAdmin);
      await _setOrRemove(prefs, _keyUserEmail, _userEmail);
      await _setOrRemove(prefs, _keyUserRole, _userRole);
      await _setOrRemove(prefs, _keyStudentUsn, _studentUsn);
    } catch (e) {
      debugPrint("AppState save error: $e");
    }
  }

  Future<void> _setOrRemove(SharedPreferencesAsync prefs, String key, String? value) async {
    if (value != null) {
      await prefs.setString(key, value);
    } else {
      await prefs.remove(key);
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