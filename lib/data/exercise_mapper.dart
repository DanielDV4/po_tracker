import '../domain/models.dart';
import 'raw_exercise_record.dart';

// Sensible fixed defaults for exercises derived from the raw dataset
const double _compoundBaseIncrement = 5.0;
const double _compoundMaxCapacity = 600.0;

const double _isolationBaseIncrement = 2.5;
const double _isolationMaxCapacity = 150.0;

const double _bodyweightBaseIncrement = 2.5;
const double _bodyweightMaxCapacity = 200.0; // Represents weighted belts/vests

Exercise? mapRawExerciseToDomain(RawExerciseRecord raw) {
  if (raw.name == null || raw.name!.trim().isEmpty) {
    return null; // Cannot map an exercise without a valid name
  }

  ExerciseCategory? category;
  
  final mechanic = raw.mechanic?.toLowerCase();
  final equipment = raw.equipment?.toLowerCase();

  // Mapping rules based on dataset fields
  if (mechanic == 'isolation') {
    category = ExerciseCategory.isolation;
  } else if (mechanic == 'compound') {
    category = ExerciseCategory.compound;
  } else if (equipment == 'body only') {
    category = ExerciseCategory.bodyweight;
  } else {
    // Any record that cannot be confidently categorized is discarded
    return null;
  }

  double baseInc;
  double maxCap;

  switch (category) {
    case ExerciseCategory.compound:
      baseInc = _compoundBaseIncrement;
      maxCap = _compoundMaxCapacity;
      break;
    case ExerciseCategory.isolation:
      baseInc = _isolationBaseIncrement;
      maxCap = _isolationMaxCapacity;
      break;
    case ExerciseCategory.bodyweight:
      baseInc = _bodyweightBaseIncrement;
      maxCap = _bodyweightMaxCapacity;
      break;
  }

  // Generate a stable slugified ID from the name
  final slugId = raw.name!.toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
      
  if (slugId.isEmpty) return null;

  try {
    // We let the domain constructor enforce its strict OCL invariants (e.g. maxWeightCapacity > 0, baseIncrement <= maxCap)
    return Exercise(
      id: slugId,
      name: raw.name!,
      category: category,
      baseIncrement: baseInc,
      maxWeightCapacity: maxCap,
      sets: 1, // Baseline standard; can be mutated in UI logic later
    );
  } catch (e) {
    // If domain validation fails (e.g. invalid bounds), we safely discard the record instead of crashing
    return null;
  }
}
