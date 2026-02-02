      class DomainConstants {
  // Domain options with icons
  static const List<Map<String, String>> domains = [
    {'value': 'computer_science', 'label': 'Computer Science', 'icon': '💻'},
    {'value': 'information_technology', 'label': 'Information Technology', 'icon': '🖥️'},
    {'value': 'medical_health', 'label': 'Medical & Health', 'icon': '🏥'},
    {'value': 'biological_sciences', 'label': 'Biological Sciences', 'icon': '🧬'},
    {'value': 'engineering_general', 'label': 'Engineering (General)', 'icon': '⚙️'},
    {'value': 'science_physics_chemistry', 'label': 'Science (Physics/Chemistry)', 'icon': '🔬'},
    {'value': 'mathematics_statistics', 'label': 'Mathematics & Statistics', 'icon': '📊'},
    {'value': 'commerce_accounting', 'label': 'Commerce & Accounting', 'icon': '💰'},
    {'value': 'business_management', 'label': 'Business & Management', 'icon': '📈'},
    {'value': 'law_civics', 'label': 'Law & Civics', 'icon': '⚖️'},
    {'value': 'arts_humanities', 'label': 'Arts & Humanities', 'icon': '🎨'},
    {'value': 'education_teaching', 'label': 'Education & Teaching', 'icon': '📚'},
    {'value': 'competitive_exams', 'label': 'Competitive Exams', 'icon': '📝'},
    {'value': 'career_placements', 'label': 'Career & Placements', 'icon': '💼'},
    {'value': 'general_discussion', 'label': 'General Discussion', 'icon': '💬'},
  ];

  // Helper methods
  static String getDomainLabel(String value) {
    return domains.firstWhere(
          (d) => d['value'] == value,
      orElse: () => {'value': value, 'label': value, 'icon': ''},
    )['label']!;
  }

  static String getDomainIcon(String value) {
    return domains.firstWhere(
          (d) => d['value'] == value,
      orElse: () => {'value': value, 'label': value, 'icon': ''},
    )['icon']!;
  }
}