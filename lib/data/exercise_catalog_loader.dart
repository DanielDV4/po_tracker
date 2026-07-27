import 'dart:convert';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import 'raw_exercise_record.dart';
import 'exercise_mapper.dart';

Future<List<Exercise>> loadExerciseCatalog() async {
  final List<Exercise> catalog = [];
  
  try {
    // Load raw string from declared flutter assets
    final String jsonString = await rootBundle.loadString('assets/data/exercises.json');
    final dynamic decoded = json.decode(jsonString);

    if (decoded is! List) {
      print('Exercise Loader Warning: The asset file is not a valid JSON array.');
      return [];
    }

    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        try {
          // Phase 1: Blindly parse raw JSON fields
          final rawRecord = RawExerciseRecord.fromJson(item);
          
          // Phase 2: Apply business mapping logic & domain constraints
          final domainExercise = mapRawExerciseToDomain(rawRecord);
          
          if (domainExercise != null) {
            catalog.add(domainExercise);
          }
        } catch (e) {
          // Gracefully skip single malformed records (e.g., unexpected data types inside the JSON object)
          print('Skipping malformed exercise record: $e');
        }
      }
    }
  } catch (e) {
    // Gracefully handle file I/O or total JSON parsing failures
    print('Failed to load or parse exercise catalog: $e');
  }

  return catalog;
}
