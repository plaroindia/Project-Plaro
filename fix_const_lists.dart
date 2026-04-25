import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  int replaced = 0;
  for (final file in files) {
    String content = file.readAsStringSync();
    
    // Replace `this.something = []` with `this.something = const []` in constructors
    // Specifically looking for the pattern in the error logs: `this.propertyName = [],`
    // We can use a regex: `this\.([a-zA-Z0-9_]+)\s*=\s*\[\]` -> `this.$1 = const []`
    
    final regex = RegExp(r'this\.([a-zA-Z0-9_]+)\s*=\s*\[\]');
    if (regex.hasMatch(content)) {
      final newContent = content.replaceAllMapped(regex, (match) {
        return 'this.${match.group(1)} = const []';
      });
      file.writeAsStringSync(newContent);
      replaced++;
      print('Fixed \${file.path}');
    }
  }
  print('Fixed [] to const [] in \$replaced files.');
}
