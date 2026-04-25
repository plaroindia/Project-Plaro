import 'dart:io';

void main() {
  final files = Directory('lib').listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    String content = file.readAsStringSync();
    String newContent = content;

    // A conservative list of widget constructions and lists that often have 'const' prepended
    final targets = [
      'const Text(', 'const Icon(', 'const TextStyle(', 
      'const Padding(', 'const SizedBox(', 'const Row(', 
      'const Column(', 'const EdgeInsets.', 'const Center(',
      'const BoxDecoration(', 'const Border(', 'const CircleAvatar(',
      'const InputDecoration(', 'const []'
    ];

    for (final target in targets) {
      newContent = newContent.replaceAll(target, target.substring(6));
    }

    if (content != newContent) {
      file.writeAsStringSync(newContent);
    }
  }
}
