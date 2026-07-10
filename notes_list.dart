// ============================================================
// NOTES LIST / SEARCH SCREEN — Flutter
// Shows all notes for a deck (or all decks), with live text
// search and tag filtering. Tapping a note opens NoteEditorScreen.
// ============================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'note_editor.dart';

class NotesListScreen extends StatefulWidget {
  final Database db;
  final String? deckId; // null = show notes from all decks

  const NotesListScreen({super.key, required this.db, this.deckId});

  @override
  State<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _activeTag;
  List<Map<String, dynamic>> _notes = [];
  Set<String> _allTags = {};

  @override
  void initState() {
    super.initState();
    _loadNotes();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim());
      _loadNotes();
    });
  }

  Future<void> _loadNotes() async {
    final whereClauses = <String>['deleted = 0'];
    final whereArgs = <Object?>[];

    if (widget.deckId != null) {
      whereClauses.add('deck_id = ?');
      whereArgs.add(widget.deckId);
    }
    if (_query.isNotEmpty) {
      whereClauses.add('(title LIKE ? OR content LIKE ? OR tags LIKE ?)');
      whereArgs.addAll(['%$_query%', '%$_query%', '%$_query%']);
    }
    if (_activeTag != null) {
      whereClauses.add('tags LIKE ?');
      whereArgs.add('%$_activeTag%');
    }

    final results = await widget.db.query(
      'notes',
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'updated_at DESC',
    );

    final tagSet = <String>{};
    for (final n in results) {
      final tags = (n['tags'] as String?)?.split(',') ?? [];
      tagSet.addAll(tags.where((t) => t.isNotEmpty));
    }

    setState(() {
      _notes = results;
      _allTags = tagSet;
    });
  }

  // Pulls a short plain-text preview out of the stored Quill Delta JSON
  String _previewText(String? contentJson) {
    if (contentJson == null) return '';
    try {
      final delta = quill.Document.fromJson(jsonDecode(contentJson));
      final plain = delta.toPlainText().trim();
      return plain.length > 120 ? '${plain.substring(0, 120)}…' : plain;
    } catch (_) {
      return '';
    }
  }

  void _openNote(Map<String, dynamic>? note) {
    final id = note?['id'] as String? ?? const Uuid().v4();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          db: widget.db,
          noteId: id,
          deckId: widget.deckId ?? note?['deck_id'] ?? 'default',
          existingNote: note,
        ),
      ),
    ).then((_) => _loadNotes()); // refresh list after editing
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search notes...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_allTags.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: const Text('All'),
                      selected: _activeTag == null,
                      onSelected: (_) {
                        setState(() => _activeTag = null);
                        _loadNotes();
                      },
                    ),
                  ),
                  ..._allTags.map((tag) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(tag),
                          selected: _activeTag == tag,
                          onSelected: (_) {
                            setState(() => _activeTag = _activeTag == tag ? null : tag);
                            _loadNotes();
                          },
                        ),
                      )),
                ],
              ),
            ),
          Expanded(
            child: _notes.isEmpty
                ? Center(
                    child: Text(
                      _query.isEmpty ? 'No notes yet' : 'No matches',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.separated(
                    itemCount: _notes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final note = _notes[i];
                      final tags = (note['tags'] as String?)?.split(',') ?? [];
                      return ListTile(
                        title: Text(
                          (note['title'] as String?)?.isNotEmpty == true
                              ? note['title']
                              : '(untitled)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          _previewText(note['content'] as String?),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: tags.isNotEmpty && tags.first.isNotEmpty
                            ? Wrap(
                                spacing: 4,
                                children: tags
                                    .take(2)
                                    .map((t) => Chip(
                                          label: Text(t, style: const TextStyle(fontSize: 10)),
                                          padding: EdgeInsets.zero,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ))
                                    .toList(),
                              )
                            : null,
                        onTap: () => _openNote(note),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openNote(null),
        child: const Icon(Icons.add),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
