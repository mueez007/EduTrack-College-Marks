import 'package:flutter/foundation.dart';

class AppState with ChangeNotifier {
  String? _selectedBatchId;
  String? _selectedBatchName;

  String? get selectedBatchId => _selectedBatchId;
  String? get selectedBatchName => _selectedBatchName;

  void setSelectedBatch(String batchId, String batchName) {
    _selectedBatchId = batchId;
    _selectedBatchName = batchName;
    notifyListeners(); // Notify widgets listening to this state
    print("AppState Updated: Batch ID = $_selectedBatchId, Name = $_selectedBatchName");
  }

  void clearSelectedBatch() {
     _selectedBatchId = null;
     _selectedBatchName = null;
     notifyListeners();
     print("AppState Cleared: Batch selection removed.");
  }
}