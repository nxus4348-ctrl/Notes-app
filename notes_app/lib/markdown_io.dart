// ============================================================
// MARKDOWN IMPORT / EXPORT — Flutter
//
// Converts between Quill's Delta format (what's stored in the
// `content` column) and plain Markdown, so notes can be shared,
// backed up, or imported from other apps.
//
// pubspec.yaml additions needed:
//   file_picker: ^8.0.0
//   share_plus: ^9.0.0
//   path_provider: ^2.1.0
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

// ------------------------------------------------------------
// DELTA -> MARKDOWN
// ------------------------------------------------------------
String deltaToMarkdown(quill.Document doc) {
  final delta = doc.toDelta();
  final buffer = StringBuffer();
  var lineBuffer = StringBuffer();

  void flushLine(Map<String, dynamic>? attrs) {
    var line = lineBuffer.toString();
    if (attrs != null) {
      if (attrs['header'] == 1) line = '# $line';
      if (attrs['header'] == 2) line = '## $line';
      if (attrs['header'] == 3) line = '### $line';
      if (attrs['list'] == 'bullet') line = '- $line';
      if (attrs['list'] == 'ordered') line = '1. $line';
      if (attrs['blockquote'] == true) line = '> $line';
      if (attrs['code-block'] == true) line = '    $line';
    }
    buffer.writeln(line);
    lineBuffer = StringBuffer();
  }

  for (final op in delta.toList()) {
    final data = op.data;
    if (data is! String) continue; // skip embeds (images etc.) for now

    final attrs = op.attributes;
    final segments = data.split('\n');

    for (var i = 0; i < segments.length; i++) {
      var text = segments[i];
      if (attrs != null) {
        if (attrs['bold'] == true) text = '**$text**';
        if (attrs['italic'] == true) text = '*$text*';
        if (attrs['code'] == true) text = '`$text`';
        if (attrs['link'] != null) text = '[$text](${attrs['link']})';
      }
      lineBuffer.write(text);
      // A newline in the data (except the very last empty segment) ends a line
      if (i < segments.length - 1) {
        flushLine(attrs);
      }
    }
  }
  if (lineBuffer.isNotEmpty) flushLine(null);

  return buffer.toString().trim();
}

// ------------------------------------------------------------
// MARKDOWN -> DELTA
// Supports: headers (#, ##, ###), bold (**x**), italic (*x*),
// bullet lists (- x), ordered lists (1. x), blockquotes (> x),
// inline code (`x`), and links ([text](url)).
// ------------------------------------------------------------
quill.Document markdownToDelta(String markdown) {
  final doc = quill.Document();
  final lines = markdown.split('\n');
  var offset = 0;

  for (final rawLine in lines) {
    var line = rawLine;
    Map<String, dynamic>? blockAttrs;

    if (line.startsWith('### ')) {
      blockAttrs = {'header': 3};
      line = line.substring(4);
    } else if (line.startsWith('## ')) {
      blockAttrs = {'header': 2};
      line = line.substring(3);
    } else if (line.startsWith('# ')) {
      blockAttrs = {'header': 1};
      line = line.substring(2);
    } else if (line.startsWith('- ')) {
      blockAttrs = {'list': 'bullet'};
      line = line.substring(2);
    } else if (RegExp(r'^\d+\.\s').hasMatch(line)) {
      blockAttrs = {'list': 'ordered'};
      line = line.replaceFirst(RegExp(r'^\d+\.\s'), '');
    } else if (line.startsWith('> ')) {
      blockAttrs = {'blockquote': true};
      line = line.substring(2);
    }

    _insertInlineMarkdown(doc, offset, line);
    offset += line.length;

    doc.insert(offset, '\n');
    if (blockAttrs != null) {
      doc.format(offset, 0, quill.Attribute.fromKeyValue(
          blockAttrs.keys.first, blockAttrs.values.first));
    }
    offset += 1;
  }

  return doc;
}

void _insertInlineMarkdown(quill.Document doc, int offset, String line) {
  // Simple regex-based inline parser for **bold**, *italic*, `code`, [text](url)
  final pattern = RegExp(r'(\*\*(.+?)\*\*)|(\*(.+?)\*)|(`(.+?)`)|(\[(.+?)\]\((.+?)\))');
  var lastEnd = 0;
  var cursor = offset;

  for (final match in pattern.allMatches(line)) {
    if (match.start > lastEnd) {
      final plain = line.substring(lastEnd, match.start);
      doc.insert(cursor, plain);
      cursor += plain.length;
    }

    if (match.group(1) != null) {
      final text = match.group(2)!;
      doc.insert(cursor, text);
      doc.format(cursor, text.length, quill.Attribute.bold);
      cursor += text.length;
    } else if (match.group(3) != null) {
      final text = match.group(4)!;
      doc.insert(cursor, text);
      doc.format(cursor, text.length, quill.Attribute.italic);
      cursor += text.length;
    } else if (match.group(5) != null) {
      final text = match.group(6)!;
      doc.insert(cursor, text);
      doc.format(cursor, text.length, quill.Attribute.inlineCode);
      cursor += text.length;
    } else if (match.group(7) != null) {
      final text = match.group(8)!;
      final url = match.group(9)!;
      doc.insert(cursor, text);
      doc.format(cursor, text.length, quill.Attribute.link.fromString(url));
      cursor += text.length;
    }
    lastEnd = match.end;
  }

  if (lastEnd < line.length) {
    final remaining = line.substring(lastEnd);
    doc.insert(cursor, remaining);
  }
}

// ------------------------------------------------------------
// FILE I/O — export a single note, export all notes, import .md files
// ------------------------------------------------------------
class MarkdownIO {
  final Database db;
  MarkdownIO(this.db);

  /// Exports one note as a shareable .md file
  Future<void> exportNote(Map<String, dynamic> note) async {
    final doc = quill.Document.fromJson(jsonDecode(note['content']));
    final markdown = deltaToMarkdown(doc);
    final title = (note['title'] as String?)?.isNotEmpty == true
        ? note['title']
        : 'untitled';

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$title.md');
    await file.writeAsString(markdown);

    await Share.shareXFiles([XFile(file.path)], text: title);
  }

  /// Exports every note in a deck as a zip-free bundle of .md files
  /// dropped into the app's documents directory, and shares the folder.
  Future<void> exportAllNotes(String deckId) async {
    final notes = await db.query('notes',
        where: 'deck_id = ? AND deleted = 0', whereArgs: [deckId]);
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/export');
    await exportDir.create(recursive: true);

    final files = <XFile>[];
    for (final note in notes) {
      final doc = quill.Document.fromJson(jsonDecode(note['content']));
      final markdown = deltaToMarkdown(doc);
      final title = (note['title'] as String?)?.isNotEmpty == true
          ? note['title']
          : note['id'];
      final file = File('${exportDir.path}/$title.md');
      await file.writeAsString(markdown);
      files.add(XFile(file.path));
    }

    if (files.isNotEmpty) await Share.shareXFiles(files);
  }

  /// Lets the user pick one or more .md files and imports them as new notes
  Future<int> importMarkdownFiles(String deckId) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['md', 'markdown', 'txt'],
    );
    if (result == null) return 0;

    var imported = 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final picked in result.files) {
      if (picked.path == null) continue;
      final content = await File(picked.path!).readAsString();
      final doc = markdownToDelta(content);
      final title = picked.name.replaceAll(RegExp(r'\.(md|markdown|txt)$'), '');

      await db.insert('notes', {
        'id': const Uuid().v4(),
        'deck_id': deckId,
        'title': title,
        'content': jsonEncode(doc.toDelta().toJson()),
        'tags': '',
        'created_at': now,
        'updated_at': now,
        'usn': -1, // dirty, will be picked up on next sync
        'deleted': 0,
      });
      imported++;
    }
    return imported;
  }
}
