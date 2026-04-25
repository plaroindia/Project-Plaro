import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  int totalFiles = 0;
  for (final file in files) {
    String content = file.readAsStringSync();
    bool changed = false;

    // Relative imports
    if (content.contains("import 'Model/")) {
      content = content.replaceAll("import 'Model/", "import 'models/");
      changed = true;
    }
    if (content.contains("import 'View/")) {
      content = content.replaceAll("import 'View/", "import 'views/");
      changed = true;
    }
    if (content.contains("import 'ViewModel/")) {
      content = content.replaceAll("import 'ViewModel/", "import 'viewmodels/");
      changed = true;
    }
    
    // Package imports
    if (content.contains("import 'package:plaro_3/Model/")) {
      content = content.replaceAll("import 'package:plaro_3/Model/", "import 'package:plaro_3/models/");
      changed = true;
    }
    if (content.contains("import 'package:plaro_3/View/")) {
      content = content.replaceAll("import 'package:plaro_3/View/", "import 'package:plaro_3/views/");
      changed = true;
    }
    if (content.contains("import 'package:plaro_3/ViewModel/")) {
      content = content.replaceAll("import 'package:plaro_3/ViewModel/", "import 'package:plaro_3/viewmodels/");
      changed = true;
    }

    // Also handle directory imports like 'package:plaro_3/View' (unlikely but possible)

    if (changed) {
      file.writeAsStringSync(content);
      totalFiles++;
    }
  }
  print('Updated imports in \$totalFiles files.');
}
