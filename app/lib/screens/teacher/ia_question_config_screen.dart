import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ia_questionwise_entry_screen.dart';

/// Configuration screen for setting up question paper structure before
/// entering question-wise IA marks. Collects:
/// 1. Number of questions
/// 2. Number of sub-questions (or none)
/// 3. Max marks per question/sub-question
/// Then navigates to the entry table.
///
/// If a config already exists in Firestore for this IA, it skips the wizard
/// and goes directly to the entry table.
class IAQuestionConfigScreen extends StatefulWidget {
  final String iaLabel; // "IA1", "IA2", or "IA3"
  final String iaFieldKey; // "ia_1", "ia_2", or "ia_3"
  final String subjectId;
  final String subjectCode;
  final String subjectName;
  final Map<String, dynamic> subjectData;
  final String batchId;

  const IAQuestionConfigScreen({
    super.key,
    required this.iaLabel,
    required this.iaFieldKey,
    required this.subjectId,
    required this.subjectCode,
    required this.subjectName,
    required this.subjectData,
    required this.batchId,
  });

  @override
  State<IAQuestionConfigScreen> createState() => _IAQuestionConfigScreenState();
}

class _IAQuestionConfigScreenState extends State<IAQuestionConfigScreen> {
  bool _checkingExisting = true;
  int _currentStep = 0;

  // Step 1: Number of questions
  final _numQuestionsController = TextEditingController();
  int? _numQuestions;

  // Step 2: Sub-questions
  bool _hasSubQuestions = false;
  final _numSubQuestionsController = TextEditingController();
  int? _numSubQuestions;

  // Step 3: Max marks
  final _maxMarksController = TextEditingController(text: '10');
  int? _maxMarks;

  @override
  void initState() {
    super.initState();
    _checkExistingConfig();
  }

  @override
  void dispose() {
    _numQuestionsController.dispose();
    _numSubQuestionsController.dispose();
    _maxMarksController.dispose();
    super.dispose();
  }

  /// Check if a config already exists for this IA.
  /// If so, skip the wizard and go directly to the entry table.
  Future<void> _checkExistingConfig() async {
    try {
      // Check the subject-level config doc
      DocumentSnapshot configSnap = await FirebaseFirestore.instance
          .collection('ia_configs')
          .doc('${widget.subjectId}_${widget.iaFieldKey}')
          .get();

      if (configSnap.exists && mounted) {
        final savedConfig = configSnap.data() as Map<String, dynamic>;
        // Reconstruct the in-memory config (with pairs as List<List<int>>)
        final config = _reconstructConfig(savedConfig);
        // Go directly to entry screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => IAQuestionwiseEntryScreen(
              iaLabel: widget.iaLabel,
              iaFieldKey: widget.iaFieldKey,
              subjectId: widget.subjectId,
              subjectCode: widget.subjectCode,
              subjectName: widget.subjectName,
              subjectData: widget.subjectData,
              batchId: widget.batchId,
              config: config,
            ),
          ),
        );
        return;
      }
    } catch (e) {
      print('Error checking existing config: $e');
    }

    if (mounted) {
      setState(() => _checkingExisting = false);
    }
  }

  /// Reconstruct the in-memory config from Firestore-safe flat format.
  Map<String, dynamic> _reconstructConfig(Map<String, dynamic> saved) {
    final int numQ = saved['numQuestions'] as int;
    final int numSub = saved['numSubQuestions'] as int;
    final bool hasSub = numSub > 0;
    final int halfPoint = numQ ~/ 2;

    List<int> sectionA = List.generate(halfPoint, (i) => i + 1);
    List<int> sectionB = List.generate(numQ - halfPoint, (i) => halfPoint + i + 1);

    // Rebuild pairs from sections (respecting sub-question mode)
    List<List<int>> pairsA = _buildPairs(sectionA, hasSubQuestions: hasSub);
    List<List<int>> pairsB = _buildPairs(sectionB, hasSubQuestions: hasSub);

    return {
      'numQuestions': numQ,
      'numSubQuestions': numSub,
      'maxMarksPerQuestion': saved['maxMarksPerQuestion'] as int,
      'sectionA': sectionA,
      'sectionB': sectionB,
      'pairsA': pairsA,
      'pairsB': pairsB,
    };
  }

  /// Build pairs from a list of question numbers.
  /// - With sub-questions: each question is its own OR choice (pair of 1).
  /// - Without sub-questions: consecutive questions are grouped into pairs of 2.
  List<List<int>> _buildPairs(List<int> questions, {required bool hasSubQuestions}) {
    if (hasSubQuestions) {
      // Each question is its own OR-option (Q1 vs Q2 vs ...)
      return questions.map((q) => [q]).toList();
    }
    // No sub-questions: pair consecutive questions (Q1+Q2 vs Q3+Q4)
    List<List<int>> pairs = [];
    for (int i = 0; i < questions.length; i += 2) {
      if (i + 1 < questions.length) {
        pairs.add([questions[i], questions[i + 1]]);
      } else {
        pairs.add([questions[i]]);
      }
    }
    return pairs;
  }

  /// Build the config for section/pair structure.
  Map<String, dynamic> _buildConfig() {
    final int numQ = _numQuestions!;
    final int halfPoint = numQ ~/ 2;
    final bool hasSub = _hasSubQuestions && (_numSubQuestions ?? 0) > 0;

    List<int> sectionA = List.generate(halfPoint, (i) => i + 1);
    List<int> sectionB = List.generate(numQ - halfPoint, (i) => halfPoint + i + 1);

    List<List<int>> pairsA = _buildPairs(sectionA, hasSubQuestions: hasSub);
    List<List<int>> pairsB = _buildPairs(sectionB, hasSubQuestions: hasSub);

    return {
      'numQuestions': numQ,
      'numSubQuestions': hasSub ? (_numSubQuestions ?? 0) : 0,
      'maxMarksPerQuestion': _maxMarks ?? 10,
      'sectionA': sectionA,
      'sectionB': sectionB,
      'pairsA': pairsA,
      'pairsB': pairsB,
    };
  }

  /// Save config to Firestore (flat, no nested arrays).
  Future<void> _saveConfigToFirestore(Map<String, dynamic> config) async {
    try {
      // Save only Firestore-safe fields (no nested arrays)
      await FirebaseFirestore.instance
          .collection('ia_configs')
          .doc('${widget.subjectId}_${widget.iaFieldKey}')
          .set({
        'numQuestions': config['numQuestions'],
        'numSubQuestions': config['numSubQuestions'],
        'maxMarksPerQuestion': config['maxMarksPerQuestion'],
        'subjectId': widget.subjectId,
        'iaFieldKey': widget.iaFieldKey,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving config: $e');
    }
  }

  void _goToNextStep() {
    switch (_currentStep) {
      case 0:
        final numQ = int.tryParse(_numQuestionsController.text.trim());
        if (numQ == null || numQ < 2 || numQ > 20) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Enter a valid number of questions (2–20).'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        setState(() {
          _numQuestions = numQ;
          _currentStep = 1;
        });
        break;

      case 1:
        if (_hasSubQuestions) {
          final numSub = int.tryParse(_numSubQuestionsController.text.trim());
          if (numSub == null || numSub < 2 || numSub > 5) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Enter a valid number of sub-questions (2–5).'),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
          _numSubQuestions = numSub;
        } else {
          _numSubQuestions = 0;
        }
        setState(() => _currentStep = 2);
        break;

      case 2:
        final maxM = int.tryParse(_maxMarksController.text.trim());
        if (maxM == null || maxM < 1 || maxM > 100) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Enter valid max marks (1–100).'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        _maxMarks = maxM;

        final config = _buildConfig();

        // Save config to Firestore so we don't ask again
        _saveConfigToFirestore(config);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => IAQuestionwiseEntryScreen(
              iaLabel: widget.iaLabel,
              iaFieldKey: widget.iaFieldKey,
              subjectId: widget.subjectId,
              subjectCode: widget.subjectCode,
              subjectName: widget.subjectName,
              subjectData: widget.subjectData,
              batchId: widget.batchId,
              config: config,
            ),
          ),
        );
        break;
    }
  }

  void _goBack() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_checkingExisting) {
      return Scaffold(
        appBar: AppBar(
          title: Text('${widget.iaLabel} — ${widget.subjectCode}'),
          backgroundColor: theme.colorScheme.inversePrimary,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.iaLabel} Setup — ${widget.subjectCode}'),
        backgroundColor: theme.colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Progress indicator ---
            Row(
              children: List.generate(3, (i) {
                final bool isActive = i <= _currentStep;
                final bool isCurrent = i == _currentStep;
                return Expanded(
                  child: Container(
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: isActive
                          ? (isCurrent
                              ? theme.colorScheme.primary
                              : theme.colorScheme.primary.withValues(alpha: 0.5))
                          : Colors.grey.shade300,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Text(
              'Step ${_currentStep + 1} of 3',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // --- Step Content ---
            Expanded(child: _buildStepContent(theme)),

            // --- Navigation Buttons ---
            const SizedBox(height: 16),
            Row(
              children: [
                if (_currentStep > 0)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _goBack,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                if (_currentStep > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _goToNextStep,
                    icon: Icon(_currentStep == 2
                        ? Icons.check_circle_outline
                        : Icons.arrow_forward),
                    label: Text(_currentStep == 2
                        ? 'Start Entering Marks'
                        : 'Next'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
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

  Widget _buildStepContent(ThemeData theme) {
    switch (_currentStep) {
      case 0:
        return _buildStep1(theme);
      case 1:
        return _buildStep2(theme);
      case 2:
        return _buildStep3(theme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStep1(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.quiz_outlined, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'How many questions in the ${widget.iaLabel} question paper?',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Questions will be divided into 2 sections (A & B) and paired for best-pair selection.',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _numQuestionsController,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: 'e.g. 8',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          ),
          onSubmitted: (_) => _goToNextStep(),
        ),
        const SizedBox(height: 12),
        Text(
          'Must be between 2 and 20.',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildStep2(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_list_numbered, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Do questions have sub-questions?',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'e.g., Q1 → 1a), 1b) etc.',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _SelectableCard(
                  label: 'No Sub-Questions',
                  icon: Icons.looks_one,
                  isSelected: !_hasSubQuestions,
                  onTap: () => setState(() {
                    _hasSubQuestions = false;
                    _numSubQuestionsController.clear();
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SelectableCard(
                  label: 'Has Sub-Questions',
                  icon: Icons.format_list_bulleted,
                  isSelected: _hasSubQuestions,
                  onTap: () => setState(() => _hasSubQuestions = true),
                ),
              ),
            ],
          ),
          if (_hasSubQuestions) ...[
            const SizedBox(height: 24),
            Text(
              'How many sub-questions per question?',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _numSubQuestionsController,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'e.g. 2',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
              onSubmitted: (_) => _goToNextStep(),
            ),
            const SizedBox(height: 8),
            Text(
              'Must be between 2 and 5.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ],
          const SizedBox(height: 24),
          if (_numQuestions != null) _buildPreview(theme),
        ],
      ),
    );
  }

  Widget _buildStep3(ThemeData theme) {
    final String marksLabel = _hasSubQuestions
        ? 'Max marks per sub-question'
        : 'Max marks per question';
    final String example = _hasSubQuestions
        ? 'e.g., if each sub-question is worth 5 marks'
        : 'e.g., if each question is worth 10 marks';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.scoreboard_outlined, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(marksLabel, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            example,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _maxMarksController,
            keyboardType: TextInputType.number,
            autofocus: true,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: '10',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            ),
            onSubmitted: (_) => _goToNextStep(),
          ),
          const SizedBox(height: 24),
          _buildSummaryCard(theme),
        ],
      ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    final int numQ = _numQuestions!;
    final int half = numQ ~/ 2;
    final sectionA = List.generate(half, (i) => 'Q${i + 1}');
    final sectionB = List.generate(numQ - half, (i) => 'Q${half + i + 1}');

    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Preview', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Section A: ${sectionA.join(", ")}'),
            Text('Section B: ${sectionB.join(", ")}'),
            const SizedBox(height: 4),
            Text(
              'Pairs A: ${_buildPairPreviewStr(sectionA)}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              'Pairs B: ${_buildPairPreviewStr(sectionB)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _buildPairPreviewStr(List<String> questions) {
    List<String> pairs = [];
    for (int i = 0; i < questions.length; i += 2) {
      if (i + 1 < questions.length) {
        pairs.add('(${questions[i]} & ${questions[i + 1]})');
      } else {
        pairs.add('(${questions[i]})');
      }
    }
    return pairs.join(', ');
  }

  Widget _buildSummaryCard(ThemeData theme) {
    final int numQ = _numQuestions ?? 0;
    final int numSub = _hasSubQuestions ? (_numSubQuestions ?? 0) : 0;
    final int maxM = int.tryParse(_maxMarksController.text.trim()) ?? 10;
    final int marksPerQ = _hasSubQuestions ? (maxM * numSub) : maxM;
    final int totalPossible = numQ * marksPerQ;

    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Configuration Summary',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(),
            _summaryRow('Questions', '$numQ'),
            _summaryRow('Sub-questions',
                _hasSubQuestions ? '$numSub per question' : 'None'),
            _summaryRow(
              _hasSubQuestions ? 'Marks/sub-question' : 'Marks/question',
              '$maxM',
            ),
            _summaryRow('Total marks per question', '$marksPerQ'),
            _summaryRow('Max possible total', '$totalPossible'),
            const Divider(),
            Text(
              'Section A: Q1–Q${numQ ~/ 2}  |  Section B: Q${numQ ~/ 2 + 1}–Q$numQ',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _SelectableCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SelectableCard({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected
                  ? theme.colorScheme.primary
                  : Colors.grey,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? theme.colorScheme.primary
                    : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
