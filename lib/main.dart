import 'package:flutter/material.dart';
import 'ui/workout_screen.dart';

void main() {
  runApp(const POTrackerApp());
}

class POTrackerApp extends StatelessWidget {
  const POTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PO Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const WorkoutScreen(),
    );
  }
}
