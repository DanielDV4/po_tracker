import 'package:test/test.dart';
import '../lib/domain/models.dart';
import '../lib/domain/overload_engine.dart';

void main() {
  group('OCL Invariants & Bounds Checking', () {
    test('Exercise throws ArgumentError when baseIncrement > maxWeightCapacity', () {
      expect(
        () => Exercise(
          id: '1',
          name: 'Squat',
          category: ExerciseCategory.compound,
          baseIncrement: 50.0,
          maxWeightCapacity: 40.0,
          sets: 3,
        ),
        throwsArgumentError,
      );
    });

    test('Exercise throws ArgumentError when sets <= 0 or maxWeightCapacity <= 0', () {
      expect(
        () => Exercise(
          id: '1',
          name: 'Squat',
          category: ExerciseCategory.compound,
          baseIncrement: 5.0,
          maxWeightCapacity: 0.0,
          sets: 3,
        ),
        throwsArgumentError,
      );

      expect(
        () => Exercise(
          id: '1',
          name: 'Squat',
          category: ExerciseCategory.compound,
          baseIncrement: 5.0,
          maxWeightCapacity: 100.0,
          sets: 0,
        ),
        throwsArgumentError,
      );
    });

    test('WorkoutSet throws ArgumentError when targetWeight <= 0 or negative actual values are provided', () {
      final validExercise = Exercise(
        id: '1', name: 'Squat', category: ExerciseCategory.compound, baseIncrement: 5.0, maxWeightCapacity: 100.0, sets: 1,
      );

      // Target Weight zero/negative
      expect(
        () => WorkoutSet(
          id: 's1', setNumber: 1, targetWeight: 0.0, targetReps: 5, actualWeight: 10.0, actualReps: 5, exercise: validExercise,
        ),
        throwsArgumentError,
      );

      // Negative actual weight
      expect(
        () => WorkoutSet(
          id: 's1', setNumber: 1, targetWeight: 10.0, targetReps: 5, actualWeight: -5.0, actualReps: 5, exercise: validExercise,
        ),
        throwsArgumentError,
      );

      // Negative actual reps
      expect(
        () => WorkoutSet(
          id: 's1', setNumber: 1, targetWeight: 10.0, targetReps: 5, actualWeight: 10.0, actualReps: -1, exercise: validExercise,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Overload Engine Business Logic', () {
    late OverloadEngine engine;
    late Exercise benchPress;
    late Exercise bicepCurl;

    setUp(() {
      engine = OverloadEngine();
      benchPress = Exercise(id: 'ex1', name: 'Bench Press', category: ExerciseCategory.compound, baseIncrement: 5.0, maxWeightCapacity: 315.0, sets: 1);
      bicepCurl = Exercise(id: 'ex2', name: 'Bicep Curl', category: ExerciseCategory.isolation, baseIncrement: 2.5, maxWeightCapacity: 100.0, sets: 1);
    });

    test('Pre-condition Validation: OverloadEngine throws StateError if actualReps or actualWeight is null', () {
      final currentSet = WorkoutSet(id: 's1', setNumber: 1, targetWeight: 100.0, targetReps: 5, actualWeight: null, actualReps: null, exercise: benchPress);
      final currentSession = WorkoutSession(id: 'sess1', date: DateTime.now(), sets: [currentSet]);
      final previousSession = WorkoutSession(id: 'sess0', date: DateTime.now(), sets: []);

      expect(
        () => engine.computeNextTarget(previousSession, currentSession),
        throwsStateError,
      );
    });

    test('Successful Progression: Hitting target reps increases targetWeight by baseIncrement', () {
      final currentSet = WorkoutSet(id: 's1', setNumber: 1, targetWeight: 100.0, targetReps: 5, actualWeight: 100.0, actualReps: 5, exercise: benchPress);
      final currentSession = WorkoutSession(id: 'sess1', date: DateTime.now(), sets: [currentSet]);
      final previousSession = WorkoutSession(id: 'sess0', date: DateTime.now(), sets: []);

      final nextTarget = engine.computeNextTarget(previousSession, currentSession);
      expect(nextTarget.targetWeight, 105.0); // 100 + 5.0
    });

    test('Hard Cap Enforcement: When targetWeight + baseIncrement exceeds maxWeightCapacity, safely truncate', () {
      // 312.5 + 5.0 = 317.5 (which is strictly > 315.0 max capacity)
      final currentSet = WorkoutSet(id: 's1', setNumber: 1, targetWeight: 312.5, targetReps: 5, actualWeight: 312.5, actualReps: 5, exercise: benchPress);
      final currentSession = WorkoutSession(id: 'sess1', date: DateTime.now(), sets: [currentSet]);
      final previousSession = WorkoutSession(id: 'sess0', date: DateTime.now(), sets: []);

      final nextTarget = engine.computeNextTarget(previousSession, currentSession);
      expect(nextTarget.targetWeight, 315.0); // Capped gracefully at max capacity
    });

    test('3-Strike Deload: Failing target reps across 3 consecutive historical sessions applies a 10% deload penalty', () {
      // Historical session 2 (Strike 1)
      final hist2Set = WorkoutSet(id: 'h2', setNumber: 1, targetWeight: 100.0, targetReps: 5, actualWeight: 100.0, actualReps: 4, exercise: benchPress);
      final hist2Sess = WorkoutSession(id: 'sess_h2', date: DateTime.now(), sets: [hist2Set]);

      // Historical session 1 (Strike 2)
      final hist1Set = WorkoutSet(id: 'h1', setNumber: 1, targetWeight: 100.0, targetReps: 5, actualWeight: 100.0, actualReps: 4, exercise: benchPress);
      final hist1Sess = WorkoutSession(id: 'sess_h1', date: DateTime.now(), previousSession: hist2Sess, sets: [hist1Set]);

      // Current session (Strike 3)
      final currSet = WorkoutSet(id: 'curr', setNumber: 1, targetWeight: 100.0, targetReps: 5, actualWeight: 100.0, actualReps: 4, exercise: benchPress);
      final currSess = WorkoutSession(id: 'sess_curr', date: DateTime.now(), previousSession: hist1Sess, sets: [currSet]);

      final nextTarget = engine.computeNextTarget(hist1Sess, currSess);
      expect(nextTarget.targetWeight, 90.0); // 100 * 0.9 = 90
    });

    test('Anti-Contamination Bug Fix Verification: Failures on Exercise A do NOT trigger a deload penalty on Exercise B', () {
      // History 2: Bench Press Failed (Strike 1 for Bench Press)
      final hist2Set = WorkoutSet(id: 'h2', setNumber: 1, targetWeight: 100.0, targetReps: 5, actualWeight: 100.0, actualReps: 4, exercise: benchPress);
      final hist2Sess = WorkoutSession(id: 'sess_h2', date: DateTime.now(), sets: [hist2Set]);

      // History 1: Bicep Curl Failed (This should NOT contaminate the Bench Press history)
      final hist1Set = WorkoutSet(id: 'h1', setNumber: 1, targetWeight: 30.0, targetReps: 10, actualWeight: 30.0, actualReps: 8, exercise: bicepCurl);
      final hist1Sess = WorkoutSession(id: 'sess_h1', date: DateTime.now(), previousSession: hist2Sess, sets: [hist1Set]);

      // Current: Bench Press Failed (Strike 2 for Bench Press)
      final currSet = WorkoutSet(id: 'curr', setNumber: 1, targetWeight: 100.0, targetReps: 5, actualWeight: 100.0, actualReps: 4, exercise: benchPress);
      final currSess = WorkoutSession(id: 'sess_curr', date: DateTime.now(), previousSession: hist1Sess, sets: [currSet]);

      final nextTarget = engine.computeNextTarget(hist1Sess, currSess);
      
      // Since Bench Press only explicitly failed twice (currSess and hist2Sess), it should NOT receive a deload penalty.
      // Target weight remains standard on standard failure.
      expect(nextTarget.targetWeight, 100.0); 
    });
  });
}
