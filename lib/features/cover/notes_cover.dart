import 'package:flutter/material.dart';
import 'package:private_vault_mobile/app/private_vault_theme.dart';

class NotesCover extends StatefulWidget {
  const NotesCover({super.key, required this.onUnlockRequested});

  final VoidCallback onUnlockRequested;

  @override
  State<NotesCover> createState() => _NotesCoverState();
}

class _NotesCoverState extends State<NotesCover> {
  final _controller = TextEditingController();
  final _items = <_TodoItem>[];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _items.add(_TodoItem(text));
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _items.where((item) => !item.done).length;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          key: const Key('cover-title'),
          onLongPress: widget.onUnlockRequested,
          child: const Text('Notes'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: 'Task list summary',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _items.isEmpty
                          ? 'Keep a short list for the day.'
                          : '$remaining remaining · ${_items.length} total',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('todo-input'),
                          controller: _controller,
                          onSubmitted: (_) => _add(),
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            hintText: 'Add a task',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Semantics(
                        button: true,
                        label: 'Add task',
                        child: IconButton.filled(
                          key: const Key('todo-add'),
                          onPressed: _add,
                          tooltip: 'Add task',
                          icon: const Icon(Icons.add),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: AnimatedSwitcher(
                  duration: PrivateVaultTheme.motionDuration(context),
                  child: _items.isEmpty
                      ? const Center(
                          key: ValueKey('notes-empty'),
                          child: Text('No tasks yet'),
                        )
                      : ListView.separated(
                          key: const ValueKey('notes-list'),
                          itemCount: _items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return Card(
                              child: CheckboxListTile(
                                value: item.done,
                                title: Text(item.text),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                onChanged: (value) {
                                  setState(() {
                                    item.done = value ?? false;
                                  });
                                },
                                secondary: IconButton(
                                  tooltip: 'Delete task',
                                  onPressed: () {
                                    setState(() => _items.removeAt(index));
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodoItem {
  _TodoItem(this.text);

  final String text;
  bool done = false;
}
