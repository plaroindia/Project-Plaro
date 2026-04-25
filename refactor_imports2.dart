import 'dart:io';

void main() {
  final dir = Directory('lib');
  if (!dir.existsSync()) return;
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  int count = 0;
  for (final file in files) {
    String content = file.readAsStringSync();
    String newContent = content;
    
    // Use regex to replace Model, View, ViewModel inside import quotes.
    // E.g., import '../../Model/user.dart' -> import '../../models/user.dart'
    newContent = newContent.replaceAllMapped(RegExp(r"import '([^']*)Model/"), (match) => "import '${match.group(1)}models/");
    newContent = newContent.replaceAllMapped(RegExp(r"import '([^']*)View/"), (match) => "import '${match.group(1)}views/");
    newContent = newContent.replaceAllMapped(RegExp(r"import '([^']*)ViewModel/"), (match) => "import '${match.group(1)}viewmodels/");

    if (content != newContent) {
      file.writeAsStringSync(newContent);
      count++;
    }
  }
  print('Updated $count files');
}
