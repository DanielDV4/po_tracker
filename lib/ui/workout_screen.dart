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
    required String initialWeightText,
    required String initialRepsText,
    required this.previousText,
  })  : weightController = TextEditingController(text: initialWeightText),
        repsController = TextEditingController(text: initialRepsText);
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
  
  // Independent state trackers per exercise ID for Hevy-style memory
  final Map<String, double> _exerciseCurrentWeights = {};
  final Map<String, int> _exerciseCurrentReps = {};

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
    
    final currentTargetW = _exerciseCurrentWeights[_selectedExercise!.id];
    final currentTargetR = _exerciseCurrentReps[_selectedExercise!.id];
    
    // First-time UX: Leave text fields empty instead of forcing 100.0
    final initialWeightText = currentTargetW != null ? currentTargetW.toStringAsFixed(1) : '';
    final initialRepsText = currentTargetR != null ? currentTargetR.toString() : '';

    // Hevy-style Previous Column Lookup
    String prevText = '—';
    WorkoutSession? lastSession;
    for (int i = _history.length - 1; i >= 0; i--) {
      if (_history[i].sets.isNotEmpty && _history[i].sets.first.exercise.id == _selectedExercise!.id) {
        lastSession = _history[i];
        break;
      }
    }
    
    final setIndex = _rows.length + 1;
    if (lastSession != null) {
      try {
        // Look up the exact historical performance for THAT specific set index
        final matchingSet = lastSession.sets.firstWhere((s) => s.setNumber == setIndex);
        final w = matchingSet.actualWeight ?? matchingSet.targetWeight;
        final r = matchingSet.actualReps ?? matchingSet.targetReps;
        prevText = '${w.toStringAsFixed(1)} lbs x $r';
      } catch (_) {
        // If they add more sets this time than last time, leave as blank dash
        prevText = '—';
      }
    } else {
      prevText = 'First time';
    }

    setState(() {
      _rows.add(
        _SetRowData(
          index: setIndex,
          initialWeightText: initialWeightText,
          initialRepsText: initialRepsText,
          previousText: prevText,
        ),
      );
    });
  }

  void _onCheckmarkTapped(_SetRowData row) {
    setState(() {
      row.isCompleted = !row.isCompleted;
    });
  }

  void _onFinishTapped() {
    if (_selectedExercise == null) return;
    
    try {
      final completedSets = <WorkoutSet>[];

      for (final row in _rows) {
        if (row.isCompleted) {
          final weightText = row.weightController.text;
          final repsText = row.repsController.text;
          
          final parsedWeight = double.tryParse(weightText);
          final parsedReps = int.tryParse(repsText);
          
          // Engine Bridge: Feed custom user inputs securely to the Domain layer
          // If the field is empty and we have no state, fallback to 0.0 (which triggers OCL validation rejection)
          final setTargetWeight = parsedWeight ?? (_exerciseCurrentWeights[_selectedExercise!.id] ?? 0.0);
          final setTargetReps = parsedReps ?? (_exerciseCurrentReps[_selectedExercise!.id] ?? 5);

          completedSets.add(WorkoutSet(
            id: 'set_${row.index}',
            setNumber: row.index,
            targetWeight: setTargetWeight, 
            targetReps: setTargetReps,
            actualWeight: parsedWeight,
            actualReps: parsedReps,
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

      WorkoutSession? lastSessionForExercise;
      for (int i = _history.length - 1; i >= 0; i--) {
        if (_history[i].sets.isNotEmpty && _history[i].sets.first.exercise.id == _selectedExercise!.id) {
          lastSessionForExercise = _history[i];
          break;
        }
      }

      final effectivePrevious = lastSessionForExercise ?? WorkoutSession(
        id: 'dummy_start',
        date: DateTime.now().subtract(const Duration(days: 7)),
        sets: [],
      );

      final currentSession = WorkoutSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        date: DateTime.now(),
        previousSession: lastSessionForExercise, 
        sets: completedSets,
      );

      final engine = OverloadEngine();
      final nextTarget = engine.computeNextTarget(effectivePrevious, currentSession);

      setState(() {
        _history.add(currentSession);
        
        _exerciseCurrentWeights[_selectedExercise!.id] = nextTarget.targetWeight;
        _exerciseCurrentReps[_selectedExercise!.id] = nextTarget.targetReps;

        _bannerMessage = 'SESSION FINISHED! Next Target: ${nextTarget.targetWeight} lbs x ${nextTarget.targetReps} reps';
        _bannerColor = Colors.green.shade700;
        
        _rows.clear();
        _addSet(); 
      });
    } on ArgumentError catch (e) {
      setState(() {
        _bannerMessage = 'OCL Violation: ${e.message}';
        _bannerColor = Colors.red.shade800; 
      });
    } on StateError catch (e) {
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

  double _calculateVolume() {
    double vol = 0;
    for (var r in _rows) {
      if (r.isCompleted) {
        final w = double.tryParse(r.weightController.text) ?? 0;
        final reps = int.tryParse(r.repsController.text) ?? 0;
        vol += w * reps;
      }
    }
    return vol;
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
        selectedColor: Colors.blueAccent.withValues(alpha: 0.2),
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

  Widget _buildMetric(String label, String value, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white54, size: 14),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildSetRow(_SetRowData row) {
    final bgColor = row.isCompleted ? Colors.green.withValues(alpha: 0.12) : Colors.transparent;
    final badgeColor = row.isCompleted ? Colors.green.shade600 : const Color(0xFF2C2C2E);
    final borderColor = row.isCompleted ? Colors.green.withValues(alpha: 0.3) : Colors.white10;

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${row.index}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center),
            ),
          ),
          
          Expanded(
            flex: 3,
            child: Text(row.previousText, style: const TextStyle(color: Colors.white54, fontSize: 13), textAlign: TextAlign.center),
          ),
          
          SizedBox(
            width: 60,
            child: Container(
              decoration: BoxDecoration(
                color: row.isCompleted ? Colors.transparent : const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderColor),
              ),
              child: TextField(
                controller: row.weightController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          
          SizedBox(
            width: 60,
            child: Container(
              decoration: BoxDecoration(
                color: row.isCompleted ? Colors.transparent : const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderColor),
              ),
              child: TextField(
                controller: row.repsController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ),
          
          SizedBox(
            width: 44,
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => _onCheckmarkTapped(row),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.check, color: row.isCompleted ? Colors.white : Colors.white54, size: 18),
                ),
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

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: bgColor,
        body: Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
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
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () {}, 
        ),
        title: const Text('Strength Session', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: TextButton(
              onPressed: _onFinishTapped,
              style: TextButton.styleFrom(
                backgroundColor: Colors.blueAccent.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Finish', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: cardColor,
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildMetric('Duration', '45:12', Icons.timer_outlined),
                  _buildMetric('Volume', '${_calculateVolume().toStringAsFixed(0)} lbs', Icons.fitness_center),
                  _buildMetric('Sets', '${_rows.where((r) => r.isCompleted).length}', Icons.format_list_numbered),
                ],
              ),
            ),
            
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: _showExercisePicker,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _selectedExercise!.name, 
                                    style: const TextStyle(color: Colors.blueAccent, fontSize: 18, fontWeight: FontWeight.w800),
                                    overflow: TextOverflow.ellipsis,
                                  )
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
                                  child: Text(_selectedExercise!.category.name.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.more_horiz, color: Colors.white54),
                              ],
                            ),
                          ),
                        ),
                        
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Add notes here...',
                              hintStyle: const TextStyle(color: Colors.white38),
                              filled: true,
                              fillColor: const Color(0xFF2C2C2E),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: const [
                              SizedBox(width: 36, child: Text('SET', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                              Expanded(flex: 3, child: Text('PREVIOUS', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                              SizedBox(width: 60, child: Text('LBS', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                              SizedBox(width: 12),
                              SizedBox(width: 60, child: Text('REPS', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                              SizedBox(width: 44, child: Icon(Icons.check, color: Colors.white54, size: 16)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        
                        ..._rows.map((row) => _buildSetRow(row)).toList(),
                        
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: OutlinedButton(
                            onPressed: _addSet,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blueAccent, 
                              side: const BorderSide(color: Colors.white10),
                              backgroundColor: Colors.white.withValues(alpha: 0.02),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              minimumSize: const Size.fromHeight(44),
                            ),
                            child: const Text('+ Add Set', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: _bannerColor,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, -5))
                ],
              ),
              child: SafeArea(
                top: false,
                child: Text(
                  _bannerMessage,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
