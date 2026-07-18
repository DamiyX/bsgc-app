import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    String content = file.readAsStringSync();
    bool changed = false;

    if (content.contains('const TextStyle(fontSize: 10, color: Theme.of')) {
      content = content.replaceAll('const TextStyle(fontSize: 10, color: Theme.of', 'TextStyle(fontSize: 10, color: Theme.of');
      changed = true;
    }
    if (content.contains('const TextStyle')) {
      content = content.replaceAll('const TextStyle', 'TextStyle');
      changed = true;
    }
    if (content.contains('const Padding')) {
      content = content.replaceAll('const Padding', 'Padding');
      changed = true;
    }
    if (content.contains('const Icon(Icons.reply, size: 16, color: Theme.of')) {
      content = content.replaceAll('const Icon(Icons.reply, size: 16, color: Theme.of', 'Icon(Icons.reply, size: 16, color: Theme.of');
      changed = true;
    }
    if (content.contains('const Icon(Icons.add, color: Theme.of')) {
      content = content.replaceAll('const Icon(Icons.add, color: Theme.of', 'Icon(Icons.add, color: Theme.of');
      changed = true;
    }
    if (content.contains('const Icon(Icons.mic, color: Theme.of')) {
      content = content.replaceAll('const Icon(Icons.mic, color: Theme.of', 'Icon(Icons.mic, color: Theme.of');
      changed = true;
    }

    if (changed) {
      file.writeAsStringSync(content);
      print('Updated ${file.path}');
    }
  }
}
