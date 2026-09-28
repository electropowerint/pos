import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/menu_button.dart';

class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  void _showNoteDialog(BuildContext context, {NoteItem? note}) {
    final titleCtrl = TextEditingController(text: note?.title ?? '');
    final bodyCtrl = TextEditingController(text: note?.body ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(note == null ? 'New Note' : 'Edit Note', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Title', hintText: 'Meeting notes, reminders...'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyCtrl,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Content', hintText: 'Write details here...'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () async {
                  final title = titleCtrl.text.trim();
                  final body = bodyCtrl.text.trim();
                  if (title.isEmpty && body.isEmpty) return;

                  final storage = StorageService();
                  if (note != null) {
                    note.title = title.isEmpty ? 'Untitled' : title;
                    note.body = body;
                    note.updatedAt = DateTime.now().millisecondsSinceEpoch;
                    await storage.updateNote(note);
                  } else {
                    final newNote = NoteItem(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      title: title.isEmpty ? 'Untitled' : title,
                      body: body,
                      updatedAt: DateTime.now().millisecondsSinceEpoch,
                    );
                    await storage.addNote(newNote);
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('Save Note', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StorageService(),
      builder: (context, _) {
        final storage = StorageService();

        return Scaffold(
          appBar: AppBar(
            leading: const MenuButton(),
            title: const Text('Notes'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add Note',
                onPressed: () => _showNoteDialog(context),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: AppTheme.primary,
            child: const Icon(Icons.add, color: Colors.white),
            onPressed: () => _showNoteDialog(context),
          ),
          body: storage.notes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit_note, size: 56, color: AppTheme.textMuted.withOpacity(0.4)),
                      const SizedBox(height: 12),
                      const Text('No notes yet', style: TextStyle(color: AppTheme.textMuted)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  itemCount: storage.notes.length,
                  itemBuilder: (context, index) {
                    final n = storage.notes[index];
                    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(
                      DateTime.fromMillisecondsSinceEpoch(n.updatedAt),
                    );

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (n.body.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                            ],
                            const SizedBox(height: 6),
                            Text(dateStr, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.textMuted),
                          onPressed: () => storage.deleteNote(n.id),
                        ),
                        onTap: () => _showNoteDialog(context, note: n),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
