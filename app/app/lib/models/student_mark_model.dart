import 'package:flutter/material.dart';

// Data model to hold student info, marks, and controllers for the entry screen
class StudentMarkModel {
  final String studentId; // Firestore document ID for the student
  final String usn;
  final String name;
  final int? ia1;
  final int? ia2;
  final int? ia3;
  final int? projectOrAssignment;
  final double? calculatedIaFinal; // Store the calculated result
  final Map<String, TextEditingController> controllers; // Controllers for input
  final Map<String, dynamic> subjectData; // Rules and max marks for calculation
  final String markDocId; // Firestore doc ID for the mark entry (e.g., studentId_subjectId)

  StudentMarkModel({
    required this.studentId,
    required this.usn,
    required this.name,
    this.ia1,
    this.ia2,
    this.ia3,
    this.projectOrAssignment,
    this.calculatedIaFinal,
    required this.controllers,
    required this.subjectData,
    required this.markDocId,
  });

  // Helper method to create a copy with updated values (useful for setState)
  StudentMarkModel copyWith({
    int? ia1,
    int? ia2,
    int? ia3,
    int? projectOrAssignment,
    double? calculatedIaFinal,
  }) {
    return StudentMarkModel(
      studentId: studentId,
      usn: usn,
      name: name,
      ia1: ia1 ?? this.ia1,
      ia2: ia2 ?? this.ia2,
      ia3: ia3 ?? this.ia3,
      projectOrAssignment: projectOrAssignment ?? this.projectOrAssignment,
      calculatedIaFinal: calculatedIaFinal ?? this.calculatedIaFinal,
      controllers: controllers, // Controllers are mutable, reference stays same
      subjectData: subjectData,
      markDocId: markDocId,
    );
  }
}