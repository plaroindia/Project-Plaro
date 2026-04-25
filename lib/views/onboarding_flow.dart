import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:plaro_3/views/set_profile.dart';
import 'package:plaro_3/views/skill_test_page.dart'; // ✅ skill assessment

// Onboarding state provider
final onboardingStateProvider = StateNotifierProvider<OnboardingStateNotifier, OnboardingData>(
  (ref) => OnboardingStateNotifier(),
);

class OnboardingData {
  // Required
  String? primaryCareerGoal;
  String? targetRole;
  String? currentStatus;
  List<SkillData> skills;
  String? timeAvailability;
  String? learningPreference;
  
  // Optional
  String? shortTermGoal;
  bool constraintFreeOnly;
  bool constraintHeavyWorkload;
  int? confidenceBaseline;

  OnboardingData({
    this.primaryCareerGoal,
    this.targetRole,
    this.currentStatus,
    this.skills = const [],
    this.timeAvailability,
    this.learningPreference,
    this.shortTermGoal,
    this.constraintFreeOnly = false,
    this.constraintHeavyWorkload = false,
    this.confidenceBaseline,
  });

  bool get isStep1Complete => 
      primaryCareerGoal != null && 
      primaryCareerGoal!.trim().isNotEmpty &&
      targetRole != null &&
      targetRole!.trim().isNotEmpty;

  bool get isStep2Complete => 
      currentStatus != null &&
      timeAvailability != null;

  bool get isStep3Complete => 
      skills.isNotEmpty &&
      skills.every((s) => s.skill.trim().isNotEmpty);

  bool get isStep4Complete => 
      learningPreference != null;

  bool get isComplete => 
      isStep1Complete && 
      isStep2Complete && 
      isStep3Complete && 
      isStep4Complete;

  OnboardingData copyWith({
    String? primaryCareerGoal,
    String? targetRole,
    String? currentStatus,
    List<SkillData>? skills,
    String? timeAvailability,
    String? learningPreference,
    String? shortTermGoal,
    bool? constraintFreeOnly,
    bool? constraintHeavyWorkload,
    int? confidenceBaseline,
  }) {
    return OnboardingData(
      primaryCareerGoal: primaryCareerGoal ?? this.primaryCareerGoal,
      targetRole: targetRole ?? this.targetRole,
      currentStatus: currentStatus ?? this.currentStatus,
      skills: skills ?? this.skills,
      timeAvailability: timeAvailability ?? this.timeAvailability,
      learningPreference: learningPreference ?? this.learningPreference,
      shortTermGoal: shortTermGoal ?? this.shortTermGoal,
      constraintFreeOnly: constraintFreeOnly ?? this.constraintFreeOnly,
      constraintHeavyWorkload: constraintHeavyWorkload ?? this.constraintHeavyWorkload,
      confidenceBaseline: confidenceBaseline ?? this.confidenceBaseline,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'primary_career_goal': primaryCareerGoal,
      'target_role': targetRole,
      'current_status': currentStatus,
      'skills': skills.map((s) => s.toJson()).toList(),
      'time_availability': timeAvailability,
      'learning_preference': learningPreference,
      'short_term_goal': shortTermGoal,
      'constraint_free_only': constraintFreeOnly,
      'constraint_heavy_workload': constraintHeavyWorkload,
      'confidence_baseline': confidenceBaseline,
    };
  }
}

class SkillData {
  String skill;
  int confidence; // 1-5
  
  SkillData({required this.skill, required this.confidence});
  
  Map<String, dynamic> toJson() => {
    'skill': skill,
    'confidence': confidence,
  };
}

class OnboardingStateNotifier extends StateNotifier<OnboardingData> {
  OnboardingStateNotifier() : super(OnboardingData());

  void updateCareerGoals({String? goal, String? role}) {
    state = state.copyWith(
      primaryCareerGoal: goal,
      targetRole: role,
    );
  }

  void updateCurrentStatus(String status) {
    state = state.copyWith(currentStatus: status);
  }

  void updateTimeAvailability(String time) {
    state = state.copyWith(timeAvailability: time);
  }

  void updateSkills(List<SkillData> skills) {
    state = state.copyWith(skills: skills);
  }

  void updateLearningPreference(String preference) {
    state = state.copyWith(learningPreference: preference);
  }

  void updateOptionalFields({
    String? shortTermGoal,
    bool? constraintFreeOnly,
    bool? constraintHeavyWorkload,
    int? confidenceBaseline,
  }) {
    state = state.copyWith(
      shortTermGoal: shortTermGoal,
      constraintFreeOnly: constraintFreeOnly,
      constraintHeavyWorkload: constraintHeavyWorkload,
      confidenceBaseline: confidenceBaseline,
    );
  }

  Future<void> saveOnboarding() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('No user logged in');

      // Save to database
      await Supabase.instance.client
          .from('user_onboarding')
          .upsert(
        {
          'user_id': user.id,
          ...state.toJson(),
        },
        onConflict: 'user_id',
      );

      // Mark onboarding as complete
      await Supabase.instance.client
          .from('user_profiles')
          .update({'onboarding_complete': true})
          .eq('user_id', user.id);

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'onboarding_complete': true}),
      );
    } catch (e) {
      debugPrint('Error saving onboarding: $e');
      rethrow;
    }
  }
}

class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  int _currentStep = 0;
  bool _isSubmitting = false;

  final List<String> _stepTitles = [
    'Career Goals',
    'Current Status',
    'Skills & Expertise',
    'Learning Preferences',
    'Optional Details',
  ];

  Future<void> _saveAndContinue() async {
    final onboardingData = ref.read(onboardingStateProvider);

    // Validate current step
    bool canProceed = false;
    switch (_currentStep) {
      case 0:
        canProceed = onboardingData.isStep1Complete;
        break;
      case 1:
        canProceed = onboardingData.isStep2Complete;
        break;
      case 2:
        canProceed = onboardingData.isStep3Complete;
        break;
      case 3:
        canProceed = onboardingData.isStep4Complete;
        break;
      case 4:
        canProceed = true; // Optional step
        break;
    }

    if (!canProceed && _currentStep < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all required fields'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_currentStep == 2) {
      // ── After Skills & Expertise: run the skill test, then continue ──────
      final onboarding = ref.read(onboardingStateProvider);
      final skills = onboarding.skills.map((s) => s.skill).toList();
      final userRole = _inferRole(onboarding.currentStatus);

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SkillTestPage(
            skills: skills,
            userRole: userRole,
            // onCompleted not needed — Navigator.pop() inside SkillTestPage
            // returns here automatically.
          ),
        ),
      );

      // Skill test is done (or user pressed back on error screen).
      // Either way, advance to the next onboarding step.
      if (mounted) setState(() => _currentStep++);
    } else if (_currentStep < 4) {
      setState(() => _currentStep++);
    } else {
      // Final step - save onboarding data and navigate to profile setup
      setState(() => _isSubmitting = true);
      try {
        await ref.read(onboardingStateProvider.notifier).saveOnboarding();

        if (mounted) {
          // Navigate to SetProfile page instead of navipg
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const SetProfile(isOnboarding: true),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text('Complete Your Profile'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Progress indicator
          LinearProgressIndicator(
            value: (_currentStep + 1) / 5,
            backgroundColor: Colors.grey[800],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
          SizedBox(height: 20),

          // Step title
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _stepTitles[_currentStep],
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(height: 10),

          // Step indicator
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Step ${_currentStep + 1} of 5',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
          ),
          SizedBox(height: 30),

          // Step content
          Expanded(
            child: IndexedStack(
              index: _currentStep,
              children: [
                _buildStep1(),
                _buildStep2(),
                _buildStep3(),
                _buildStep4(),
                _buildStep5(),
              ],
            ),
          ),

          // Navigation buttons
          Padding(
            padding: EdgeInsets.all(24),
            child: Row(
              children: [
                if (_currentStep > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _currentStep--),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.blue),
                      ),
                      child: Text('Back', style: TextStyle(color: Colors.blue)),
                    ),
                  ),
                if (_currentStep > 0) SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _saveAndContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isSubmitting
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _currentStep < 4 ? 'Next' : 'Complete',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Maps onboarding currentStatus → SkillTestPage userRole so difficulty
  // is set correctly: student→intermediate, others→beginner by default.
  // Professional users won't have gone through onboarding, but we handle
  // 'employed' as a proxy for the Professional role difficulty.
  String _inferRole(String? currentStatus) {
    switch (currentStatus) {
      case 'employed':
        return 'Professional';
      case 'student':
        return 'Student';
      default:
        return 'Learner';
    }
  }

  Widget _buildStep1() {
    final onboarding = ref.watch(onboardingStateProvider);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What is your primary career goal?',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          SizedBox(height: 16),
          TextField(
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'e.g., Become a Backend Developer',
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: Colors.grey[900]?.withOpacity(0.3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[800]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.blue, width: 2),
              ),
            ),
            onChanged: (value) {
              ref.read(onboardingStateProvider.notifier).updateCareerGoals(
                goal: value,
                role: onboarding.targetRole,
              );
            },
          ),
          SizedBox(height: 24),

          Text(
            'What is your target role?',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          SizedBox(height: 16),
          TextField(
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'e.g., Senior Software Engineer',
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: Colors.grey[900]?.withOpacity(0.3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[800]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.blue, width: 2),
              ),
            ),
            onChanged: (value) {
              ref.read(onboardingStateProvider.notifier).updateCareerGoals(
                goal: onboarding.primaryCareerGoal,
                role: value,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    final onboarding = ref.watch(onboardingStateProvider);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What is your current status?',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          SizedBox(height: 16),

          ...[
            ('student', 'Student'),
            ('employed', 'Employed'),
            ('unemployed', 'Unemployed'),
            ('career_switcher', 'Career Switcher'),
          ].map((option) {
            return Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () {
                  ref.read(onboardingStateProvider.notifier)
                      .updateCurrentStatus(option.$1);
                },
                child: Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: onboarding.currentStatus == option.$1
                        ? Colors.blue.withOpacity(0.2)
                        : Colors.grey[900]?.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: onboarding.currentStatus == option.$1
                          ? Colors.blue
                          : Colors.grey[800]!,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        onboarding.currentStatus == option.$1
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: onboarding.currentStatus == option.$1
                            ? Colors.blue
                            : Colors.grey,
                      ),
                      SizedBox(width: 12),
                      Text(
                        option.$2,
                        style: TextStyle(
                          color: onboarding.currentStatus == option.$1
                              ? Colors.white
                              : Colors.grey[400],
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          SizedBox(height: 24),

          Text(
            'How much time can you dedicate to learning?',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          SizedBox(height: 16),

          ...[
            '1-5 hours/week',
            '5-10 hours/week',
            '10-20 hours/week',
            '20+ hours/week',
          ].map((option) {
            return Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () {
                  ref.read(onboardingStateProvider.notifier)
                      .updateTimeAvailability(option);
                },
                child: Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: onboarding.timeAvailability == option
                        ? Colors.blue.withOpacity(0.2)
                        : Colors.grey[900]?.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: onboarding.timeAvailability == option
                          ? Colors.blue
                          : Colors.grey[800]!,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        onboarding.timeAvailability == option
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: onboarding.timeAvailability == option
                            ? Colors.blue
                            : Colors.grey,
                      ),
                      SizedBox(width: 12),
                      Text(
                        option,
                        style: TextStyle(
                          color: onboarding.timeAvailability == option
                              ? Colors.white
                              : Colors.grey[400],
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStep3() {
    final onboarding = ref.watch(onboardingStateProvider);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add your current skills and rate your confidence',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          SizedBox(height: 16),

          // Skill list
          ...onboarding.skills.asMap().entries.map((entry) {
            final index = entry.key;
            final skill = entry.value;

            return Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[900]?.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[800]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            skill.skill,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            final newSkills = List<SkillData>.from(onboarding.skills);
                            newSkills.removeAt(index);
                            ref.read(onboardingStateProvider.notifier)
                                .updateSkills(newSkills);
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Confidence: ',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                        ...List.generate(5, (i) {
                          return IconButton(
                            icon: Icon(
                              i < skill.confidence
                                  ? Icons.star
                                  : Icons.star_border,
                              color: i < skill.confidence
                                  ? Colors.blue
                                  : Colors.grey,
                            ),
                            onPressed: () {
                              final newSkills = List<SkillData>.from(onboarding.skills);
                              newSkills[index] = SkillData(
                                skill: skill.skill,
                                confidence: i + 1,
                              );
                              ref.read(onboardingStateProvider.notifier)
                                  .updateSkills(newSkills);
                            },
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),

          // Add skill button
          OutlinedButton.icon(
            onPressed: () => _showAddSkillDialog(),
            icon: Icon(Icons.add, color: Colors.blue),
            label: Text('Add Skill', style: TextStyle(color: Colors.blue)),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: Colors.blue),
            ),
          ),

          if (onboarding.skills.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                'Add at least one skill to continue',
                style: TextStyle(color: Colors.orange[300], fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }

  void _showAddSkillDialog() {
    final controller = TextEditingController();
    int confidence = 3;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text('Add Skill', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g., Python, Machine Learning',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: Colors.grey[800],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Confidence Level:',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return IconButton(
                    icon: Icon(
                      i < confidence ? Icons.star : Icons.star_border,
                      color: i < confidence ? Colors.blue : Colors.grey,
                    ),
                    onPressed: () {
                      setDialogState(() => confidence = i + 1);
                    },
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  final onboarding = ref.read(onboardingStateProvider);
                  final newSkills = List<SkillData>.from(onboarding.skills);
                  newSkills.add(SkillData(
                    skill: controller.text.trim(),
                    confidence: confidence,
                  ));
                  ref.read(onboardingStateProvider.notifier)
                      .updateSkills(newSkills);
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: Text('Add', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep4() {
    final onboarding = ref.watch(onboardingStateProvider);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How do you prefer to learn?',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          SizedBox(height: 16),

          ...[
            ('video', 'Video Tutorials', Icons.play_circle),
            ('reading', 'Reading/Documentation', Icons.menu_book),
            ('hands_on', 'Hands-on Practice', Icons.code),
            ('mixed', 'Mixed Approach', Icons.layers),
          ].map((option) {
            return Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () {
                  ref.read(onboardingStateProvider.notifier)
                      .updateLearningPreference(option.$1);
                },
                child: Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: onboarding.learningPreference == option.$1
                        ? Colors.blue.withOpacity(0.2)
                        : Colors.grey[900]?.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: onboarding.learningPreference == option.$1
                          ? Colors.blue
                          : Colors.grey[800]!,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        option.$3,
                        color: onboarding.learningPreference == option.$1
                            ? Colors.blue
                            : Colors.grey,
                      ),
                      SizedBox(width: 16),
                      Text(
                        option.$2,
                        style: TextStyle(
                          color: onboarding.learningPreference == option.$1
                              ? Colors.white
                              : Colors.grey[400],
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStep5() {
    final onboarding = ref.watch(onboardingStateProvider);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Optional: Help us personalize your experience',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          SizedBox(height: 24),

          Text(
            'Short-term goal (3-6 months)',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          SizedBox(height: 8),
          TextField(
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'e.g., Get an internship, Build portfolio',
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: Colors.grey[900]?.withOpacity(0.3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              ref.read(onboardingStateProvider.notifier).updateOptionalFields(
                shortTermGoal: value.isEmpty ? null : value,
              );
            },
          ),
          SizedBox(height: 24),

          Text(
            'Learning constraints',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          SizedBox(height: 8),

          CheckboxListTile(
            title: Text(
              'Prefer free resources only',
              style: TextStyle(color: Colors.white),
            ),
            value: onboarding.constraintFreeOnly,
            onChanged: (value) {
              ref.read(onboardingStateProvider.notifier).updateOptionalFields(
                constraintFreeOnly: value ?? false,
              );
            },
            activeColor: Colors.blue,
            checkColor: Colors.white,
            tileColor: Colors.grey[900]?.withOpacity(0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey[800]!),
            ),
          ),
          SizedBox(height: 12),

          CheckboxListTile(
            title: Text(
              'Have a heavy workload/limited time',
              style: TextStyle(color: Colors.white),
            ),
            value: onboarding.constraintHeavyWorkload,
            onChanged: (value) {
              ref.read(onboardingStateProvider.notifier).updateOptionalFields(
                constraintHeavyWorkload: value ?? false,
              );
            },
            activeColor: Colors.blue,
            checkColor: Colors.white,
            tileColor: Colors.grey[900]?.withOpacity(0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey[800]!),
            ),
          ),
          SizedBox(height: 24),

          Text(
            'How confident are you in achieving your career goal?',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(5, (i) {
              final level = i + 1;
              return InkWell(
                onTap: () {
                  ref.read(onboardingStateProvider.notifier).updateOptionalFields(
                    confidenceBaseline: level,
                  );
                },
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: onboarding.confidenceBaseline == level
                        ? Colors.blue
                        : Colors.grey[900]?.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: onboarding.confidenceBaseline == level
                          ? Colors.blue
                          : Colors.grey[800]!,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      level.toString(),
                      style: TextStyle(
                        color: onboarding.confidenceBaseline == level
                            ? Colors.white
                            : Colors.grey[400],
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Not confident',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              Text(
                'Very confident',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}