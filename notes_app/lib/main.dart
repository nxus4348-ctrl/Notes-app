// ============================================================
// MAIN.DART — app entry point
// ============================================================

import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'notes_list.dart';

void main() {
  runApp(const NotesApp());
}

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notes',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: FutureBuilder(
        future: DatabaseHelper.instance,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return NotesListScreen(db: snapshot.data!, deckId: 'default');
        },
      ),
    );
  }
}
