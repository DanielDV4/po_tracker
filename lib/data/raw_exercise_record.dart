class RawExerciseRecord {
  final String? name;
  final String? mechanic;
  final String? equipment;
  final String? category;
  final List<String>? primaryMuscles;

  RawExerciseRecord({
    this.name,
    this.mechanic,
    this.equipment,
    this.category,
    this.primaryMuscles,
  });

  factory RawExerciseRecord.fromJson(Map<String, dynamic> json) {
    return RawExerciseRecord(
      name: json['name'] as String?,
      mechanic: json['mechanic'] as String?,
      equipment: json['equipment'] as String?,
      category: json['category'] as String?,
      primaryMuscles: (json['primaryMuscles'] as List<dynamic>?)?.map((e) => e as String).toList(),
    );
  }
}
