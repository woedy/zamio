import 'package:flutter/material.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final List<_LogEntry> _all = List.generate(40, (i) => _LogEntry.demo(i));
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final filtered = _filter == 'All' ? _all : _all.where((e) => e.level == _filter).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => setState(() => _all.clear()),
            tooltip: 'Clear',
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Wrap(
              spacing: 8,
              children: ['All', 'Info', 'Warn', 'Error'].map((label) {
                final selected = _filter == label;
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => setState(() => _filter = label),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _LogTile(entry: filtered[i]),
            ),
          )
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  final _LogEntry entry;
  const _LogTile({required this.entry});

  Color _color() {
    switch (entry.level) {
      case 'Info':
        return Colors.blue;
      case 'Warn':
        return Colors.amber.shade800;
      case 'Error':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(backgroundColor: _color(), child: const Icon(Icons.bolt, color: Colors.white, size: 16)),
      title: Text(entry.message, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${entry.timestamp.toLocal()} • ${entry.tag}'),
      trailing: IconButton(
        icon: const Icon(Icons.copy),
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard'))),
      ),
    );
  }
}

class _LogEntry {
  final String level;
  final String message;
  final String tag;
  final DateTime timestamp;
  _LogEntry({required this.level, required this.message, required this.tag, required this.timestamp});

  factory _LogEntry.demo(int i) {
    final levels = ['Info', 'Warn', 'Error'];
    final level = levels[i % levels.length];
    return _LogEntry(
      level: level,
      message: 'Sample log message #$i for $level',
      tag: 'system',
      timestamp: DateTime.now().subtract(Duration(minutes: i)),
    );
  }
}
