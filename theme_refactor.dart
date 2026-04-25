import 'dart:io';

void main() {
  final files = [
    'lib/views/widgets/unified_comments_bottom_sheet.dart',
    'lib/views/widgets/Post_card.dart',
    'lib/views/widgets/Profile_card.dart',
    'lib/views/widgets/post_comment_card.dart',
    'lib/views/widgets/post_user_card.dart',
    'lib/views/home_page.dart',
    'lib/views/profile.dart',
  ];

  for (final path in files) {
    var file = File(path);
    if (!file.existsSync()) continue;
    var content = file.readAsStringSync();

    // Whites
    content = content.replaceAll(RegExp(r'color:\s*Colors\.white70'), 'color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)');
    content = content.replaceAll(RegExp(r'color:\s*Colors\.white54'), 'color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)');
    content = content.replaceAll(RegExp(r'color:\s*Colors\.white\b'), 'color: Theme.of(context).colorScheme.onSurface');
    
    // Backgrounds & Surfaces (Greys)
    content = content.replaceAll(RegExp(r'color:\s*Colors\.grey\[800\]'), 'color: Theme.of(context).cardColor');
    content = content.replaceAll(RegExp(r'color:\s*Colors\.grey\[850\]'), 'color: Theme.of(context).scaffoldBackgroundColor');
    content = content.replaceAll(RegExp(r'color:\s*Colors\.grey\[900\]'), 'color: Theme.of(context).scaffoldBackgroundColor');
    content = content.replaceAll(RegExp(r'color:\s*Colors\.grey\[\d+\]'), 'color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)');
    content = content.replaceAll(RegExp(r'color:\s*Colors\.grey\b'), 'color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)');
    
    content = content.replaceAll(RegExp(r'backgroundColor:\s*Colors\.grey\[\d+\]'), 'backgroundColor: Theme.of(context).cardColor');
    content = content.replaceAll(RegExp(r'backgroundColor:\s*Colors\.grey\b'), 'backgroundColor: Theme.of(context).cardColor');
    
    // Foreground colors (usually text on buttons)
    content = content.replaceAll(RegExp(r'foregroundColor:\s*Colors\.white\b'), 'foregroundColor: Theme.of(context).colorScheme.onPrimary');

    file.writeAsStringSync(content);
    print('Updated \$path');
  }
}
