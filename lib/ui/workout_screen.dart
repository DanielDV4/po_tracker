import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/overload_engine.dart';
import '../data/exercise_catalog_loader.dart';

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
  bool _isLoading = true;
  List<Exercise> _allExercises = [];
  Exercise? _selectedExercise;

  // History tracking for progression chains
  final List<WorkoutSession> _history = [];
  
  // Bug Fix 1: Track the working targetWeight per exercise persistently
  final Map<String, double> _exerciseTargets = {};
  final Map<String, int> _exerciseReps = {};

  final List<_SetRowData> _rows = [];

  String _bannerMessage = 'Log sets and tap Finish to compute progression';
  Color _bannerColor = const Color(0xFF1C1C1E);

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final catalog = await loadExerciseCatalog();
    if (mounted) {
      setState(() {
        _allExercises = catalog;
        if (catalog.isNotEmpty) {
          _selectedExercise = catalog.first;
          _addSet(); 
        }
        _isLoading = false;
      });
    }
  }

  void _addSet() {
    if (_selectedExercise == null) return;
    
    // Seed at a sane default (100.0) only the first time the exercise is ever used.
    final currentTargetW = _exerciseTargets[_selectedExercise!.id] ?? 100.0;
    final currentTargetR = _exerciseReps[_selectedExercise!.id] ?? 5;

    setState(() {
      _rows.add(
        _SetRowData(
          index: _rows.length + 1,
          initialWeight: currentTargetW,
          initialReps: currentTargetR,
          previousText: '${currentTargetW.toStringAsFixed(1)} lbs x $currentTargetR',
        ),
      );
    });
  }

  void _onCheckmarkTapped(_SetRowData row) {
    // Checkmark taps only toggle UI state. No engine calls!
    setState(() {
      row.isCompleted = !row.isCompleted;
    });
  }

  void _onFinishTapped() {
    if (_selectedExercise == null) return;
    
    try {
      final completedSets = <WorkoutSet>[];
      final currentTargetR = _exerciseReps[_selectedExercise!.id] ?? 5;

      for (final row in _rows) {
        if (row.isCompleted) {
          final weightText = row.weightController.text;
          final repsText = row.repsController.text;
          
          final parsedWeight = weightText.isEmpty ? null : double.parse(weightText);
          final actualReps = repsText.isEmpty ? null : int.parse(repsText);
          
          // Bug Fix 1: Ensure custom weight values typed by the user are correctly passed into WorkoutSet
          // as the target basis for progression, overriding the cached default.
          final setTargetWeight = parsedWeight ?? (_exerciseTargets[_selectedExercise!.id] ?? 100.0);

          completedSets.add(WorkoutSet(
            id: 'set_${row.index}',
            setNumber: row.index,
            targetWeight: setTargetWeight, 
            targetReps: currentTargetR,
            actualWeight: parsedWeight,
            actualReps: actualReps,
            exercise: _selectedExercise!,
          ));
        }
      }

      if (completedSets.isEmpty) {
        setState(() {
          _bannerMessage = 'Cannot finish: No sets completed';
          _bannerColor = Colors.red.shade800;
        });
        return;
      }

      // Bug Fix 2: Session history lookup points correctly to the immediate past session for THAT SPECIFIC EXERCISE.
      WorkoutSession? lastSessionForExercise;
      for (int i = _history.length - 1; i >= 0; i--) {
        if (_history[i].sets.isNotEmpty && _history[i].sets.first.exercise.id == _selectedExercise!.id) {
          lastSessionForExercise = _history[i];
          break;
        }
      }

      // Provide a valid empty anchor if no history exists yet
      final effectivePrevious = lastSessionForExercise ?? WorkoutSession(
        id: 'dummy_start',
        date: DateTime.now().subtract(const Duration(days: 7)),
        sets: [],
      );

      final currentSession = WorkoutSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        date: DateTime.now(),
        previousSession: lastSessionForExercise, // Link firmly to the past chain for 3-strike deload logic
        sets: completedSets,
      );

      final engine = OverloadEngine();
      final nextTarget = engine.computeNextTarget(effectivePrevious, currentSession);

      setState(() {
        // Maintain _history as a real chain
        _history.add(currentSession);
        
        // Use the returned result to update the tracked targetWeight persistently
        _exerciseTargets[_selectedExercise!.id] = nextTarget.targetWeight;
        _exerciseReps[_selectedExercise!.id] = nextTarget.targetReps;

        _bannerMessage = 'SESSION FINISHED! Next Target: ${nextTarget.targetWeight} lbs x ${nextTarget.targetReps} reps';
        _bannerColor = Colors.green.shade700;
        
        // Clear out stale state and re-initialize the set row with the newly calculated target weight
        _rows.clear();
        _addSet(); 
      });
    } on ArgumentError catch (e) {
      setState(() {
        _bannerMessage = 'OCL Violation: ${e.message}';
        _bannerColor = Colors.red.shade800; 
      });
    } on StateError catch (e) {
      // Surface StateError cleanly
      setState(() {
        _bannerMessage = 'Invalid State: ${e.message}';
        _bannerColor = Colors.red.shade800; 
      });
    } catch (e) {
      setState(() {
        _bannerMessage = 'Unexpected Error: $e';
        _bannerColor = Colors.red.shade800;
      });
    }
  }

  void _showExercisePicker() {
    String searchQuery = '';
    ExerciseCategory? filterCategory;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredList = _allExercises.where((ex) {
              final matchesQuery = ex.name.toLowerCase().contains(searchQuery.toLowerCase());
              final matchesCat = filterCategory == null || ex.category == filterCategory;
              return matchesQuery && matchesCat;
            }).toList();

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 24, left: 16, right: 16
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    onChanged: (val) => setModalState(() => searchQuery = val),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search exercises...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.search, color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF2C2C2E),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('All', null, filterCategory, (cat) => setModalState(() => filterCategory = cat)),
                        _buildFilterChip('Compound', ExerciseCategory.compound, filterCategory, (cat) => setModalState(() => filterCategory = cat)),
                        _buildFilterChip('Isolation', ExerciseCategory.isolation, filterCategory, (cat) => setModalState(() => filterCategory = cat)),
                        _buildFilterChip('Bodyweight', ExerciseCategory.bodyweight, filterCategory, (cat) => setModalState(() => filterCategory = cat)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.4,
                    child: filteredList.isEmpty 
                      ? const Center(child: Text('No exercises found.', style: TextStyle(color: Colors.white54)))
                      : ListView.builder(
                          itemCount: filteredList.length,
                          itemBuilder: (context, index) {
                            final ex = filteredList[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(ex.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              subtitle: Text(ex.category.name.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              onTap: () {
                                Navigator.pop(context);
                                _selectNewExercise(ex);
                              },
                            );
                          },
                        ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChip(String label, ExerciseCategory? value, ExerciseCategory? current, Function(ExerciseCategory?) onSelected) {
    final isSelected = value == current;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontWeight: FontWeight.bold)),
        selected: isSelected,
        selectedColor: Colors.blueAccent.withOpacity(0.2),
        backgroundColor: const Color(0xFF2C2C2E),
        showCheckmark: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide.none),
        onSelected: (_) => onSelected(value),
      ),
    );
  }

  void _selectNewExercise(Exercise ex) {
    if (ex.id == _selectedExercise?.id) return;
    setState(() {
      _selectedExercise = ex;
      _rows.clear();
      _addSet();
      _bannerMessage = 'Log sets and tap Finish to compute progression';
      _bannerColor = const Color(0xFF1C1C1E);
    });
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
          Expanded(
            flex: 3,
            child: Text(row.previousText, style: const TextStyle(color: Colors.white54, fontSize: 14), textAlign: TextAlign.center),
          ),
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
    const bgColor = Color(0xFF000000);
    const cardColor = Color(0xFF1C1C1E);
    const accentColor = Colors.blueAccent;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: bgColor,
        body: Center(child: CircularProgressIndicator(color: accentColor)),
      );
    }

    if (_allExercises.isEmpty || _selectedExercise == null) {
      return const Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: Text(
            'Failed to load exercises or catalog is empty.', 
            style: TextStyle(color: Colors.redAccent, fontSize: 16)
          )
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                  const Text('PO TRACKER', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                  GestureDetector(
                    onTap: _onFinishTapped,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
                      child: const Text('Finish', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatColumn('Duration', '45:12'),
                _buildStatColumn('Volume (lbs)', '12,500'),
                _buildStatColumn('Sets', '${_rows.where((r) => r.isCompleted).length}'),
              ],
            ),
            const SizedBox(height: 24),
            
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
                      GestureDetector(
                        onTap: _showExercisePicker,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          color: Colors.transparent, 
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  _selectedExercise!.name, 
                                  style: const TextStyle(color: Colors.blueAccent, fontSize: 18, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                )
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                                child: Text(_selectedExercise!.category.name.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.keyboard_arrow_down, color: Colors.blueAccent),
                            ],
                          ),
                        ),
                      ),
                      
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
                      
                      ..._rows.map((row) => _buildSetRow(row)).toList(),
                      
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
