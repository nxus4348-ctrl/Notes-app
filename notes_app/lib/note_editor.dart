// ============================================================
// NOTE EDITOR — Flutter widget
// Uses flutter_quill for rich text (stores content as Quill's
// Delta JSON, which also renders fine as HTML/markdown export
// if you want to keep notes portable).
//
// pubspec.yaml dependencies needed:
//   flutter_quill: ^10.0.0
//   sqflite: ^2.3.0
//   uuid: ^4.0.0
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:sqflite/sqflite.dart';

class NoteEditorScreen extends StatefulWidget {
  final Database db;
  final String noteId;      // existing note id, or a freshly generated UUID for new notes
  final String deckId;
  final Map<String, dynamic>? existingNote; // null if creating new

  const NoteEditorScreen({
    super.key,
    required this.db,
    required this.noteId,
    required this.deckId,
    this.existingNote,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late quill.QuillController _controller;
  late TextEditingController _titleController;
  final List<String> _tags = [];
  final _tagInputController = TextEditingController();
  Timer? _debounce;
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(
      text: widget.existingNote?['title'] ?? '',
    );

    if (widget.existingNote != null && widget.existingNote!['content'] != null) {
      final doc = quill.Document.fromJson(jsonDecode(widget.existingNote!['content']));
      _controller = quill.QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );
      final existingTags = (widget.existingNote!['tags'] as String?)?.split(',') ?? [];
      _tags.addAll(existingTags.where((t) => t.isNotEmpty));
    } else {
      _controller = quill.QuillController.basic();
    }

    // Autosave: debounce so we're not writing to disk on every keystroke
    _controller.document.changes.listen((_) => _scheduleSave());
    _titleController.addListener(_scheduleSave);
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final contentJson = jsonEncode(_controller.document.toDelta().toJson());

    final data = {
      'id': widget.noteId,
      'deck_id': widget.deckId,
      'title': _titleController.text,
      'content': contentJson,
      'tags': _tags.join(','),
      'updated_at': now,
      'usn': -1, // mark dirty so the next sync picks this up
      'deleted': 0,
    };

    if (widget.existingNote == null) {
      data['created_at'] = now;
      await widget.db.insert('notes', data);
    } else {
      await widget.db.update('notes', data,
          where: 'id = ?', whereArgs: [widget.noteId]);
    }

    if (mounted) setState(() => _saving = false);
  }

  void _addTag(String tag) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty || _tags.contains(trimmed)) return;
    setState(() => _tags.add(trimmed));
    _tagInputController.clear();
    _scheduleSave();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            hintText: 'Note title',
            border: InputBorder.none,
          ),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(16),
              child: Icon(Icons.cloud_done_outlined, size: 20),
            ),
        ],
      ),
      body: Column(
        children: [
          // Tag chips + input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 6,
              children: [
                ..._tags.map((tag) => Chip(
                      label: Text(tag),
                      onDeleted: () {
                        setState(() => _tags.remove(tag));
                        _scheduleSave();
                      },
                    )),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _tagInputController,
                    decoration: const InputDecoration(hintText: '+ tag'),
                    onSubmitted: _addTag,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Rich text toolbar
          quill.QuillSimpleToolbar(
            controller: _controller,
            config: const quill.QuillSimpleToolbarConfig(
              showFontFamily: false,
              showFontSize: false,
              showSubscript: false,
              showSuperscript: false,
            ),
          ),

          // Editor body
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: quill.QuillEditor.basic(
                controller: _controller,
                config: const quill.QuillEditorConfig(
                  placeholder: 'Start writing...',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _titleController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }
}
