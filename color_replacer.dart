import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    String content = file.readAsStringSync();
    
    bool changed = false;

    // Backgrounds
    if (content.contains('backgroundColor: Colors.white')) {
      content = content.replaceAll('backgroundColor: Colors.white', 'backgroundColor: Theme.of(context).scaffoldBackgroundColor');
      changed = true;
    }
    
    if (content.contains('color: Colors.grey.shade50')) {
      content = content.replaceAll('color: Colors.grey.shade50', 'color: Theme.of(context).colorScheme.surface');
      changed = true;
    }
    if (content.contains('color: Colors.grey.shade100')) {
      content = content.replaceAll('color: Colors.grey.shade100', 'color: Theme.of(context).colorScheme.surface');
      changed = true;
    }

    // Text Colors (Black to Theme dynamic)
    if (content.contains('color: Colors.black87')) {
      content = content.replaceAll('color: Colors.black87', 'color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87)');
      changed = true;
    }
    if (content.contains('color: Colors.black54')) {
      content = content.replaceAll('color: Colors.black54', 'color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)');
      changed = true;
    }
    if (content.contains('color: Colors.black45')) {
      content = content.replaceAll('color: Colors.black45', 'color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)');
      changed = true;
    }

    if (changed) {
      file.writeAsStringSync(content);
      print('Updated ${file.path}');
    }
  }
}
