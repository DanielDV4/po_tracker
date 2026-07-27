import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/overload_engine.dart';

class _SetRowData {
  final int index;
  bool isCompleted;
  final TextEditingController weightController;
  final TextEditingController repsController;
  final String previousText;

  _SetRowData({
    required this.index,
    this.isCompleted = false,
    required double initialWeight,
    required int initialReps,
    required this.previousText,
  })  : weightController = TextEditingController(text: initialWeight.toStringAsFixed(1)),
        repsController = TextEditingController(text: initialReps.toString());
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  // Mock Database
  late Exercise _selectedExercise;
  final List<Exercise> _exercises = [
    Exercise(id: 'ex_1', name: 'Barbell Squat', category: ExerciseCategory.compound, baseIncrement: 5.0, maxWeightCapacity: 600.0, sets: 1),
    Exercise(id: 'ex_2', name: 'Barbell Bench Press', category: ExerciseCategory.compound, baseIncrement: 5.0, maxWeightCapacity: 400.0, sets: 1),
    Exercise(id: 'ex_3', name: 'Dumbbell Bicep Curl', category: ExerciseCategory.isolation, baseIncrement: 2.5, maxWeightCapacity: 100.0, sets: 1),
  ];

  final List<WorkoutSession> _history = [];
  final List<_SetRowData> _rows = [];

  String _bannerMessage = 'Log a set to see progression';
  Color _bannerColor = const Color(0xFF1C1C1E); // Sleek dark grey initially

  @override
  void initState() {
    super.initState();
    _selectedExercise = _exercises.first;
    _addSet(); // Initialize with first set
  }

  void _addSet() {
    setState(() {
      _rows.add(
        _SetRowData(
          index: _rows.length + 1,
          initialWeight: 100.0,
          initialReps: 5,
          previousText: '100.0 lbs x 5',
        ),
      );
    });
  }

  void _onCheckmarkTapped(_SetRowData row) {
    setState(() {
      row.isCompleted = !row.isCompleted;
    });
    
    // Compute progression whenever a set completion status changes
    _computeProgression();
  }

  void _computeProgression() {
    try {
      final completedSets = <WorkoutSet>[];
      for (final row in _rows) {
        if (row.isCompleted) {
          final weightText = row.weightController.text;
          final repsText = row.repsController.text;
          final actualWeight = weightText.isEmpty ? null : double.parse(weightText);
          final actualReps = repsText.isEmpty ? null : int.parse(repsText);
          
          completedSets.add(WorkoutSet(
            id: 'set_${row.index}',
            setNumber: row.index,
            targetWeight: 100.0, // Fixed baseline for demonstration
            targetReps: 5,
            actualWeight: actualWeight,
            actualReps: actualReps,
            exercise: _selectedExercise,
          ));
        }
      }

      if (completedSets.isEmpty) {
        setState(() {
          _bannerMessage = 'Log a set to see progression';
          _bannerColor = const Color(0xFF1C1C1E);
        });
        return;
      }

      final lastSession = _history.isNotEmpty ? _history.last : null;
      final effectivePrevious = lastSession ?? WorkoutSession(
        id: 'dummy',
        date: DateTime.now().subtract(const Duration(days: 7)),
        sets: [],
      );

      final currentSession = WorkoutSession(
        id: 'curr_session',
        date: DateTime.now(),
        previousSession: lastSession,
        sets: completedSets,
      );

      final engine = OverloadEngine();
      final nextTarget = engine.computeNextTarget(effectivePrevious, currentSession);

      setState(() {
        _bannerMessage = 'RECOMMENDED NEXT: ${nextTarget.targetWeight} lbs x ${nextTarget.targetReps} reps';
        _bannerColor = Colors.green.shade700; // Success banner
      });
    } on ArgumentError catch (e) {
      setState(() {
        _bannerMessage = 'OCL Violation: ${e.message}';
        _bannerColor = Colors.red.shade800; // Error banner
      });
    } on StateError catch (e) {
      setState(() {
        _bannerMessage = 'Invalid State: ${e.message}';
        _bannerColor = Colors.red.shade800; // Error banner
      });
    } catch (e) {
      setState(() {
        _bannerMessage = 'Unexpected Error: $e';
        _bannerColor = Colors.red.shade800;
      });
    }
  }

  @override
  void dispose() {
    for (var row in _rows) {
      row.weightController.dispose();
      row.repsController.dispose();
    }
    super.dispose();
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildSetRow(_SetRowData row) {
    return Container(
      color: row.isCompleted ? Colors.green.withOpacity(0.05) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // SET Index
          SizedBox(
            width: 40,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: row.isCompleted ? Colors.green.shade700 : const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${row.index}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center),
            ),
          ),
          // PREVIOUS Baseline Text
          Expanded(
            flex: 3,
            child: Text(row.previousText, style: const TextStyle(color: Colors.white54, fontSize: 14), textAlign: TextAlign.center),
          ),
          // LBS Field
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextField(
                controller: row.weightController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: row.isCompleted ? Colors.transparent : const Color(0xFF2C2C2E),
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          // REPS Field
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextField(
                controller: row.repsController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: row.isCompleted ? Colors.transparent : const Color(0xFF2C2C2E),
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          // CHECKMARK
          SizedBox(
            width: 40,
            child: GestureDetector(
              onTap: () => _onCheckmarkTapped(row),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: row.isCompleted ? Colors.green.shade700 : const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.check, color: row.isCompleted ? Colors.white : Colors.white54, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF000000); // Pure black background
    const cardColor = Color(0xFF1C1C1E); // Apple-style elevated dark gray
    const accentColor = Colors.blueAccent;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Top App Header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                  const Text('PO TRACKER', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
                    child: const Text('Finish', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            
            // Summary Stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatColumn('Duration', '45:12'),
                _buildStatColumn('Volume (lbs)', '12,500'),
                _buildStatColumn('Sets', '${_rows.where((r) => r.isCompleted).length}'),
              ],
            ),
            const SizedBox(height: 24),
            
            // Exercise Card
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      // Exercise Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<Exercise>(
                                  isExpanded: true,
                                  value: _selectedExercise,
                                  dropdownColor: const Color(0xFF2C2C2E),
                                  icon: const SizedBox.shrink(),
                                  items: _exercises.map((ex) => DropdownMenuItem(value: ex, child: Text(ex.name, style: const TextStyle(color: Colors.blueAccent, fontSize: 18, fontWeight: FontWeight.bold)))).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _selectedExercise = val;
                                        _rows.clear();
                                        _addSet();
                                        _bannerMessage = 'Log a set to see progression';
                                        _bannerColor = cardColor;
                                      });
                                    }
                                  },
                                )
                              )
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                              child: Text(_selectedExercise.category.name.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.more_vert, color: Colors.white54),
                          ],
                        ),
                      ),
                      
                      // Table Headers
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: const [
                            SizedBox(width: 40, child: Text('SET', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                            Expanded(flex: 3, child: Text('PREVIOUS', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                            Expanded(flex: 2, child: Text('LBS', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                            Expanded(flex: 2, child: Text('REPS', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                            SizedBox(width: 40, child: Icon(Icons.check, color: Colors.white54, size: 16)),
                          ],
                        ),
                      ),
                      
                      // Render Sets
                      ..._rows.map((row) => _buildSetRow(row)).toList(),
                      
                      // Add Set Button
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: TextButton(
                          onPressed: _addSet,
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.05),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            minimumSize: const Size.fromHeight(40),
                          ),
                          child: const Text('+ Add Set', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Bottom Banner (Engine Output)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: _bannerColor,
              child: Text(
                _bannerMessage,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1C1C1E),
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.white54,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.add_circle, size: 36), label: 'Workout'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
