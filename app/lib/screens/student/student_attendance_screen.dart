import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Screen showing subject-wise attendance for a student.
/// Reads from the `attendanceMonthly` collection which is updated
/// by the teacher's daily absentee system.
class StudentAttendanceScreen extends StatefulWidget {
  final String studentId;    // e.g. "2023_4MH23CI002"
  final String? batchId;
  final int semester;

  const StudentAttendanceScreen({
    super.key,
    required this.studentId,
    required this.batchId,
    required this.semester,
  });

  @override
  State<StudentAttendanceScreen> createState() => _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  bool _isLoading = true;
  List<_SubjectAttendance> _attendanceData = [];

  // Overall totals
  int _overallTotal = 0;
  int _overallAttended = 0;

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    setState(() => _isLoading = true);

    try {
      // First load all subjects for this semester
      QuerySnapshot subjectSnap = await FirebaseFirestore.instance
          .collection('subjects')
          .where('batchYear', isEqualTo: widget.batchId)
          .where('semester', isEqualTo: widget.semester)
          .orderBy('subjectCode')
          .get();

      List<_SubjectAttendance> results = [];
      int overallTotal = 0;
      int overallAttended = 0;

      for (var subDoc in subjectSnap.docs) {
        final subData = subDoc.data() as Map<String, dynamic>;
        final subjectName = subData['subjectName'] ?? 'Unknown';
        final subjectCode = subData['subjectCode'] ?? '???';
        final subjectId = subDoc.id;

        // Query all monthly records for this student + subject
        QuerySnapshot monthlySnap = await FirebaseFirestore.instance
            .collection('attendanceMonthly')
            .where('studentId', isEqualTo: widget.studentId)
            .where('subjectId', isEqualTo: subjectId)
            .where('semester', isEqualTo: widget.semester)
            .get();

        int totalClasses = 0;
        int attendedClasses = 0;

        // Aggregate across all months
        for (var monthDoc in monthlySnap.docs) {
          final monthData = monthDoc.data() as Map<String, dynamic>;
          totalClasses += (monthData['totalClasses'] as num?)?.toInt() ?? 0;
          attendedClasses += (monthData['attendedClasses'] as num?)?.toInt() ?? 0;
        }

        double percentage = totalClasses > 0
            ? (attendedClasses / totalClasses) * 100
            : 0;

        results.add(_SubjectAttendance(
          subjectName: subjectName,
          subjectCode: subjectCode,
          totalClasses: totalClasses,
          attendedClasses: attendedClasses,
          percentage: percentage,
        ));

        overallTotal += totalClasses;
        overallAttended += attendedClasses;
      }

      if (mounted) {
        setState(() {
          _attendanceData = results;
          _overallTotal = overallTotal;
          _overallAttended = overallAttended;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading student attendance: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading attendance: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _getPercentageColor(double percentage) {
    if (percentage >= 85) return Colors.green;
    if (percentage >= 75) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double overallPercentage = _overallTotal > 0
        ? (_overallAttended / _overallTotal) * 100
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Attendance — Sem ${widget.semester}'),
        backgroundColor: theme.colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _attendanceData.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No attendance data recorded yet.\nAttendance will appear here once your teacher starts marking it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAttendance,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // --- Overall Attendance Card ---
                      _buildOverallCard(theme, overallPercentage),
                      const SizedBox(height: 20),

                      // --- Section Title ---
                      Text(
                        'Subject-wise Breakdown',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // --- Subject Cards ---
                      ..._attendanceData.map(
                        (data) => _buildSubjectCard(theme, data),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildOverallCard(ThemeData theme, double percentage) {

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'OVERALL ATTENDANCE',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1,
                ),
              ),
              Icon(
                percentage >= 75
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                color: Colors.white70,
                size: 24,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${percentage.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$_overallAttended / $_overallTotal classes',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              // Circular progress indicator
              SizedBox(
                width: 60,
                height: 60,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: percentage / 100,
                      strokeWidth: 6,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    ),
                    Center(
                      child: Text(
                        '${_attendanceData.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Status text
          if (percentage < 75)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '⚠️ Below 75% — Attendance shortage!',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubjectCard(ThemeData theme, _SubjectAttendance data) {
    final Color pColor = _getPercentageColor(data.percentage);
    final int absentClasses = data.totalClasses - data.attendedClasses;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Subject header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    data.subjectCode,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    data.subjectName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: data.totalClasses > 0 ? data.attendedClasses / data.totalClasses : 0,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(pColor),
              ),
            ),
            const SizedBox(height: 12),

            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _statPill('Total', '${data.totalClasses}', Colors.blue),
                _statPill('Present', '${data.attendedClasses}', Colors.green),
                _statPill('Absent', '$absentClasses', absentClasses > 0 ? Colors.red : Colors.grey),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: pColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: pColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${data.percentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: pColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statPill(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

class _SubjectAttendance {
  final String subjectName;
  final String subjectCode;
  final int totalClasses;
  final int attendedClasses;
  final double percentage;

  _SubjectAttendance({
    required this.subjectName,
    required this.subjectCode,
    required this.totalClasses,
    required this.attendedClasses,
    required this.percentage,
  });
}
