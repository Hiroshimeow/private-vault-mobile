import 'package:flutter/material.dart';

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
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('todo-input'),
                      controller: _controller,
                      onSubmitted: (_) => _add(),
                      decoration: const InputDecoration(
                        hintText: 'Add a task',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    key: const Key('todo-add'),
                    onPressed: _add,
                    tooltip: 'Add task',
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _items.isEmpty
                    ? const Center(child: Text('No tasks yet'))
                    : ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return CheckboxListTile(
                            value: item.done,
                            title: Text(item.text),
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
                          );
                        },
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
