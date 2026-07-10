// ============================================================
// CLIENT SYNC LOGIC — example in Dart (Flutter), same idea in
// any language: gather dirty rows, POST /sync, apply the delta.
// ============================================================

Future<void> runSync(Database db, ApiClient api) async {
  // 1. Gather everything that changed locally since the last sync
  final dirtyNotes = await db.query('notes', where: 'usn = -1');
  final dirtyDecks = await db.query('decks', where: 'usn = -1');

  final meta = (await db.query('sync_meta')).first;
  final lastUsn = meta['last_synced_usn'] as int;

  // 2. Send them to the server along with our last known USN
  final response = await api.post('/sync', body: {
    'last_synced_usn': lastUsn,
    'changes': {
      'notes': dirtyNotes,
      'decks': dirtyDecks,
    },
  });

  await db.transaction((txn) async {
    // 3. Apply the server's canonical versions.
    //    Upsert by id; the server already resolved conflicts (LWW),
    //    so we just trust what comes back.
    for (final note in response['changes']['notes']) {
      await txn.insert(
        'notes',
        note,
        conflictAlgorithm: ConflictAlgorithm.replace, // overwrite local
      );
    }
    for (final deck in response['changes']['decks']) {
      await txn.insert('decks', deck,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // 4. Now that the push succeeded, clear the "dirty" flag on the
    //    records we sent — the server has assigned them real USNs
    //    and returned them in the payload above (so step 3 already
    //    overwrote their usn field locally). Nothing else to do here.

    // 5. Save the new high-water mark
    await txn.update(
      'sync_meta',
      {'last_synced_usn': response['new_usn'], 'last_synced_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = 1',
    );
  });
}

// Call this whenever a note is edited locally:
Future<void> markDirty(Database db, String noteId) async {
  await db.update(
    'notes',
    {
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'usn': -1, // flags it for the next sync push
    },
    where: 'id = ?',
    whereArgs: [noteId],
  );
}
