// lib/domain/models.dart

enum ExerciseCategory {
  compound,
  isolation,
  bodyweight,
}

class Exercise {
  final String id;
  final String name;
  final ExerciseCategory category;
  final double baseIncrement;
  final double maxWeightCapacity;
  final int sets;

  Exercise({
    required this.id,
    required this.name,
    required this.category,
    required this.baseIncrement,
    required this.maxWeightCapacity,
    required this.sets,
  }) {
    // OCL Invariants Validation
    if (sets <= 0) {
      throw ArgumentError('OCL Invariant Violated: sets must be > 0');
    }
    if (baseIncrement <= 0) {
      throw ArgumentError('OCL Invariant Violated: baseIncrement must be > 0');
    }
    if (maxWeightCapacity <= 0) {
      throw ArgumentError('OCL Invariant Violated: maxWeightCapacity must be > 0');
    }
    if (baseIncrement > maxWeightCapacity) {
      throw ArgumentError('OCL Invariant Violated: baseIncrement <= maxWeightCapacity');
    }
  }
}

class WorkoutSet {
  final String id;
  final int setNumber;
  final double targetWeight;
  final int targetReps;
  final double? actualWeight;
  final int? actualReps;
  final Exercise exercise;

  WorkoutSet({
    required this.id,
    required this.setNumber,
    required this.targetWeight,
    required this.targetReps,
    this.actualWeight,
    this.actualReps,
    required this.exercise,
  }) {
    // OCL Invariants Validation
    if (setNumber <= 0) {
      throw ArgumentError('OCL Invariant Violated: setNumber must be > 0');
    }
    if (targetWeight <= 0) {
      throw ArgumentError('OCL Invariant Violated: targetWeight must be > 0');
    }
    if (targetReps <= 0) {
      throw ArgumentError('OCL Invariant Violated: targetReps must be > 0');
    }
    if (actualWeight != null && actualWeight! < 0) {
      throw ArgumentError('OCL Invariant Violated: actualWeight must be >= 0');
    }
    if (actualReps != null && actualReps! < 0) {
      throw ArgumentError('OCL Invariant Violated: actualReps must be >= 0');
    }
  }
}

class WorkoutSession {
  final String id;
  final DateTime date;
  final WorkoutSession? previousSession;
  final List<WorkoutSet> sets;

  WorkoutSession({
    required this.id,
    required this.date,
    this.previousSession,
    required this.sets,
  });
}
