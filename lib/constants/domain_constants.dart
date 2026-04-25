class DomainConstants {

  // MAIN DOMAINS
  static const List<Map<String, String>> domains = [
    {'value': 'technology', 'label': 'Technology', 'icon': '💻'},
    {'value': 'design_creativity', 'label': 'Design & Creativity', 'icon': '🎨'},
    {'value': 'business_finance', 'label': 'Business & Finance', 'icon': '📈'},
    {'value': 'science_research', 'label': 'Science & Research', 'icon': '🔬'},
    {'value': 'engineering', 'label': 'Engineering', 'icon': '⚙️'},
    {'value': 'languages_communication', 'label': 'Languages & Communication', 'icon': '🗣️'},
    {'value': 'education_learning', 'label': 'Learning & Education', 'icon': '📚'},
    {'value': 'career_growth', 'label': 'Career Growth', 'icon': '💼'},
    {'value': 'health_psychology', 'label': 'Health & Psychology', 'icon': '🧠'},
    {'value': 'arts_culture', 'label': 'Arts & Culture', 'icon': '🎭'},
  ];

  // SUBDOMAINS
  static const Map<String, List<Map<String, String>>> subdomains = {

    'technology': [
      {'value': 'programming', 'label': 'Programming'},
      {'value': 'web_development', 'label': 'Web Development'},
      {'value': 'mobile_development', 'label': 'Mobile Development'},
      {'value': 'ai_ml', 'label': 'AI / Machine Learning'},
      {'value': 'data_science', 'label': 'Data Science'},
      {'value': 'cybersecurity', 'label': 'Cybersecurity'},
      {'value': 'cloud_computing', 'label': 'Cloud Computing'},
      {'value': 'blockchain', 'label': 'Blockchain'},
      {'value': 'game_development', 'label': 'Game Development'},
      {'value': 'devops', 'label': 'DevOps'},
    ],

    'design_creativity': [
      {'value': 'ui_design', 'label': 'UI Design'},
      {'value': 'ux_design', 'label': 'UX Design'},
      {'value': 'graphic_design', 'label': 'Graphic Design'},
      {'value': '3d_modeling', 'label': '3D Modeling'},
      {'value': 'animation', 'label': 'Animation'},
      {'value': 'video_editing', 'label': 'Video Editing'},
      {'value': 'motion_design', 'label': 'Motion Design'},
      {'value': 'illustration', 'label': 'Illustration'},
    ],

    'business_finance': [
      {'value': 'entrepreneurship', 'label': 'Entrepreneurship'},
      {'value': 'product_management', 'label': 'Product Management'},
      {'value': 'marketing', 'label': 'Marketing'},
      {'value': 'sales', 'label': 'Sales'},
      {'value': 'finance', 'label': 'Finance'},
      {'value': 'investing', 'label': 'Investing'},
      {'value': 'stock_market', 'label': 'Stock Market'},
    ],

    'science_research': [
      {'value': 'physics', 'label': 'Physics'},
      {'value': 'chemistry', 'label': 'Chemistry'},
      {'value': 'biology', 'label': 'Biology'},
      {'value': 'astronomy', 'label': 'Astronomy'},
      {'value': 'environmental_science', 'label': 'Environmental Science'},
    ],

    'engineering': [
      {'value': 'mechanical', 'label': 'Mechanical Engineering'},
      {'value': 'electrical', 'label': 'Electrical Engineering'},
      {'value': 'civil', 'label': 'Civil Engineering'},
      {'value': 'robotics', 'label': 'Robotics'},
      {'value': 'iot', 'label': 'Internet of Things'},
    ],

    'languages_communication': [
      {'value': 'english', 'label': 'English'},
      {'value': 'spanish', 'label': 'Spanish'},
      {'value': 'french', 'label': 'French'},
      {'value': 'japanese', 'label': 'Japanese'},
      {'value': 'public_speaking', 'label': 'Public Speaking'},
      {'value': 'writing', 'label': 'Writing'},
    ],

    'education_learning': [
      {'value': 'study_techniques', 'label': 'Study Techniques'},
      {'value': 'memory_skills', 'label': 'Memory Skills'},
      {'value': 'note_taking', 'label': 'Note Taking'},
      {'value': 'critical_thinking', 'label': 'Critical Thinking'},
    ],

    'career_growth': [
      {'value': 'interview_prep', 'label': 'Interview Preparation'},
      {'value': 'resume_building', 'label': 'Resume Building'},
      {'value': 'portfolio_building', 'label': 'Portfolio Building'},
      {'value': 'networking', 'label': 'Networking'},
    ],

    'health_psychology': [
      {'value': 'mental_health', 'label': 'Mental Health'},
      {'value': 'psychology', 'label': 'Psychology'},
      {'value': 'productivity', 'label': 'Productivity'},
      {'value': 'focus', 'label': 'Focus & Deep Work'},
    ],

    'arts_culture': [
      {'value': 'history', 'label': 'History'},
      {'value': 'philosophy', 'label': 'Philosophy'},
      {'value': 'music', 'label': 'Music'},
      {'value': 'photography', 'label': 'Photography'},
    ],
  };

}