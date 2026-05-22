/// Static configuration for all departments in the college.
/// Each department has a unique [id] (used as Firestore document key),
/// and a human-readable [name].
class Department {
  final String id;
  final String name;

  const Department({required this.id, required this.name});
}

class DepartmentConfig {
  DepartmentConfig._(); // Prevent instantiation

  static const List<Department> departments = [
    Department(id: 'CV', name: 'Civil Engineering'),
    Department(id: 'CSE', name: 'Computer Science & Engineering'),
    Department(id: 'CSE_AI', name: 'CSE (Artificial Intelligence)'),
    Department(id: 'CSE_DS', name: 'CSE (Data Science)'),
    Department(id: 'CSBS', name: 'Computer Science & Business System'),
    Department(id: 'ECE', name: 'Electronics & Communication Engineering'),
    Department(id: 'ISE', name: 'Information Science & Engineering'),
    Department(id: 'ME', name: 'Mechanical Engineering'),
    Department(id: 'CE', name: 'Computer Engineering'),
    Department(id: 'CSE_AIML', name: 'CSE (AI & ML)'),
    Department(id: 'CSE_IOT_CS', name: 'CSE (IOT & Cyber Security)'),
  ];

  /// Get a department by its short ID.
  static Department? getById(String id) {
    try {
      return departments.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get a department by its full name.
  static Department? getByName(String name) {
    try {
      return departments.firstWhere((d) => d.name == name);
    } catch (_) {
      return null;
    }
  }

  /// Get department names for dropdown display.
  static List<String> get departmentNames =>
      departments.map((d) => d.name).toList();

  /// Get department IDs.
  static List<String> get departmentIds =>
      departments.map((d) => d.id).toList();
}
