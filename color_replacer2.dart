import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    String content = file.readAsStringSync();
    
    bool changed = false;

    if (content.contains('color: Colors.black12')) {
      content = content.replaceAll('color: Colors.black12', 'color: Theme.of(context).dividerColor');
      changed = true;
    }
    if (content.contains('color: Colors.black26')) {
      content = content.replaceAll('color: Colors.black26', 'color: Theme.of(context).dividerColor');
      changed = true;
    }
    if (content.contains('color: Colors.black38')) {
      content = content.replaceAll('color: Colors.black38', 'color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38)');
      changed = true;
    }
    if (content.contains('Colors.black.withValues(alpha: 0.05)')) {
      content = content.replaceAll('Colors.black.withValues(alpha: 0.05)', 'Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05)');
      changed = true;
    }
    if (content.contains('Colors.black.withValues(alpha: 0.03)')) {
      content = content.replaceAll('Colors.black.withValues(alpha: 0.03)', 'Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.03)');
      changed = true;
    }
    
    // Fix const issues with Theme
    if (changed) {
      content = content.replaceAll('const [BoxShadow', '[BoxShadow');
      content = content.replaceAll('const Divider', 'Divider');
      content = content.replaceAll('const BorderSide', 'BorderSide');
      
      file.writeAsStringSync(content);
      print('Updated ${file.path}');
    }
  }
}
