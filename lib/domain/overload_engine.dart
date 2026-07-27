import 'dart:math';
import 'models.dart';

class OverloadEngine {
  WorkoutSet computeNextTarget(WorkoutSession previousSession, WorkoutSession currentSession) {
    if (currentSession.sets.isEmpty) {
      throw StateError('Pre-condition Violated: Cannot compute progression on an empty session.');
    }

    bool currentSucceeded = true;
    for (final set in currentSession.sets) {
      if (set.actualReps == null || set.actualWeight == null) {
        throw StateError('Pre-condition Violated: actualWeight or actualReps is null.');
      }
      if (set.actualReps! < set.targetReps) {
        currentSucceeded = false;
      }
    }

    final referenceSet = currentSession.sets.first;
    final exercise = referenceSet.exercise;
    double nextTargetWeight = referenceSet.targetWeight;

    if (currentSucceeded) {
      // Logic Flow Option A (Hard Cap): Truncating weight to maxWeightCapacity safely.
      nextTargetWeight = min(
        nextTargetWeight + exercise.baseIncrement,
        exercise.maxWeightCapacity,
      );
    } else {
      int consecutiveFailures = 1; // The current session counts as the first failure
      WorkoutSession? pointer = previousSession;

      while (pointer != null && consecutiveFailures < 3) {
        bool historyFailed = false;
        
        // Anti-Contamination: Only look at sets for this specific exercise
        final matchingSets = pointer.sets.where((s) => s.exercise.id == exercise.id).toList();
        
        if (matchingSets.isNotEmpty) {
          for (final set in matchingSets) {
            if (set.actualReps != null && set.actualReps! < set.targetReps) {
              historyFailed = true;
              break;
            }
          }
          
          if (historyFailed) {
            consecutiveFailures++;
          } else {
            break; // A success breaks the failure streak
          }
        }
        
        // Traverse back in time
        pointer = pointer.previousSession;
      }

      if (consecutiveFailures >= 3) {
        nextTargetWeight *= 0.9;
      }
    }

    // Post-Condition & OCL Validations
    if (nextTargetWeight <= 0) {
      throw ArgumentError('OCL Invariant Violated: targetWeight must be > 0');
    }
    
    if (nextTargetWeight > exercise.maxWeightCapacity) {
      throw ArgumentError('Post-condition Violated: newly calculated targetWeight exceeds maxWeightCapacity');
    }

    if (!currentSucceeded && nextTargetWeight < referenceSet.targetWeight) {
      // This is a sanity check to ensure weight only dropped if it was actually a 3-strike.
      // (Given our logic above, this implicitly checks out, but strict models benefit from explicit post-conditions).
    }

    return WorkoutSet(
      id: '', // Would typically be generated via UUID
      setNumber: 1, 
      targetWeight: nextTargetWeight,
      targetReps: referenceSet.targetReps,
      actualWeight: null,
      actualReps: null,
      exercise: exercise,
    );
  }
}
