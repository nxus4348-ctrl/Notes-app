// ============================================================
// DATABASE HELPER — opens/creates the local SQLite database
// This runs the schema from schema_client.sql the very first
// time the app launches on a device.
// ============================================================

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class DatabaseHelper {
  static Database? _db;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'notes_app.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE decks (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            parent_id TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            usn INTEGER NOT NULL DEFAULT -1,
            deleted INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE notes (
            id TEXT PRIMARY KEY,
            deck_id TEXT NOT NULL,
            title TEXT,
            content TEXT NOT NULL,
            tags TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            usn INTEGER NOT NULL DEFAULT -1,
            deleted INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE sync_meta (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            account_id TEXT,
            last_synced_usn INTEGER NOT NULL DEFAULT 0,
            last_synced_at INTEGER
          )
        ''');

        // Seed one default deck and the sync_meta row so the app
        // has somewhere to put notes on first launch.
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.insert('decks', {
          'id': 'default',
          'name': 'My Notes',
          'parent_id': null,
          'created_at': now,
          'updated_at': now,
          'usn': -1,
          'deleted': 0,
        });
        await db.insert('sync_meta', {
          'id': 1,
          'account_id': null,
          'last_synced_usn': 0,
          'last_synced_at': null,
        });
      },
    );
  }
}
