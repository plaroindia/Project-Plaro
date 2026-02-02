// ============================================
// PEARL ONBOARDING - DATABASE INTEGRATED
// ============================================

// Onboarding state
const onboardingData = {
  step1: {
    currentRole: '',
    dreamJob: '',
    shortTermGoals: '',
    longTermGoals: '',
    timeline: null
  },
  step2: {
    interests: [],
    hobbies: '',
    learningTopics: '',
    intensity: 5
  },
  step3: {
    skills: [],
    skillGaps: '',
    certifications: '',
    experience: '',
    confidence: null
  },
  step4: {
    formats: [],
    learningStyle: '',
    times: [],
    weeklyHours: '',
    challenges: '',
    motivations: []
  }
};

let currentStep = 1;
const totalSteps = 4;
let isAnimating = false;
let isSubmitting = false;

// ============================================
// INITIALIZATION
// ============================================

document.addEventListener('DOMContentLoaded', function() {
  console.log('🚀 Initializing PEARL Onboarding...');
  
  // Check if user is authenticated
  if (!AuthService.isAuthenticated()) {
    console.log('❌ User not authenticated, redirecting to login...');
    window.location.href = 'login.html';
    return;
  }
  
  // Check if onboarding already completed
  checkOnboardingStatus();
  
  // Load any saved data
  loadSavedData();
  
  // Setup event listeners
  setupEventListeners();
  
  // Initialize interactive elements
  initInteractiveElements();
  
  // Show initial step
  showStep(1);
  
  // Update progress
  updateProgress();
  
  // Load theme
  loadTheme();
  
  console.log('✅ Onboarding initialized successfully');
});

// ============================================
// ONBOARDING STATUS CHECK
// ============================================

async function checkOnboardingStatus() {
  try {
    const user = AuthService.getCurrentUser();
    
    const response = await fetch(`${API_CONFIG.BASE_URL}/api/onboarding/status`, {
      headers: API_CONFIG.getHeaders()
    });
    
    if (response.ok) {
      const data = await response.json();
      
      // If onboarding is complete, redirect to home
      if (data.completed) {
        console.log('✅ Onboarding already completed, redirecting to home...');
        window.location.href = 'index.html';
        return;
      }
      
      // If partially completed, pre-fill the data
      if (data.onboarding_data) {
        prefillOnboardingData(data.onboarding_data);
      }
    }
  } catch (error) {
    console.error('❌ Error checking onboarding status:', error);
  }
}

/**
 * Prefill onboarding form with existing data
 */
function prefillOnboardingData(data) {
  if (!data) return;
  
  console.log('📝 Prefilling onboarding data:', data);
  
  // Step 1
  if (data.target_role) {
    setValue('dreamJob', data.target_role);
    onboardingData.step1.dreamJob = data.target_role;
  }
  
  if (data.current_status) {
    setValue('currentRole', data.current_status);
    onboardingData.step1.currentRole = data.current_status;
  }
  
  if (data.short_term_goal) {
    setValue('shortTermGoals', data.short_term_goal);
    onboardingData.step1.shortTermGoals = data.short_term_goal;
  }
  
  if (data.primary_career_goal) {
    setValue('longTermGoals', data.primary_career_goal);
    onboardingData.step1.longTermGoals = data.primary_career_goal;
  }
  
  // Step 3 - Skills
  if (data.skills && Array.isArray(data.skills)) {
    data.skills.forEach(skill => {
      onboardingData.step3.skills.push({
        skill: skill,
        level: 'intermediate'
      });
    });
    renderSkills();
  }
  
  // Step 4 - Preferences
  if (data.time_availability) {
    setValue('weeklyHours', data.time_availability);
    onboardingData.step4.weeklyHours = data.time_availability;
  }
  
  if (data.learning_preference) {
    setValue('learningStyle', data.learning_preference);
    onboardingData.step4.learningStyle = data.learning_preference;
  }
}

// ============================================
// DATA PERSISTENCE
// ============================================

function loadSavedData() {
  try {
    const savedData = localStorage.getItem('onboardingData');
    if (savedData) {
      const parsedData = JSON.parse(savedData);
      Object.assign(onboardingData, parsedData);
      console.log('📥 Loaded saved data:', onboardingData);
      applySavedData();
    }
  } catch (error) {
    console.error('❌ Error loading saved data:', error);
  }
}

function applySavedData() {
  // Step 1
  setValue('currentRole', onboardingData.step1.currentRole);
  setValue('dreamJob', onboardingData.step1.dreamJob);
  setValue('shortTermGoals', onboardingData.step1.shortTermGoals);
  setValue('longTermGoals', onboardingData.step1.longTermGoals);
  
  if (onboardingData.step1.timeline) {
    const radio = document.querySelector(`input[name="timeline"][value="${onboardingData.step1.timeline}"]`);
    if (radio) {
      radio.checked = true;
      radio.parentElement.classList.add('selected');
    }
  }
  
  // Step 2
  renderInterests();
  setValue('hobbies', onboardingData.step2.hobbies);
  setValue('learningTopics', onboardingData.step2.learningTopics);
  
  const intensitySlider = document.getElementById('interestIntensity');
  if (intensitySlider && onboardingData.step2.intensity) {
    intensitySlider.value = onboardingData.step2.intensity;
    const intensityValue = document.getElementById('intensityValue');
    if (intensityValue) intensityValue.textContent = onboardingData.step2.intensity;
  }
  
  // Step 3
  renderSkills();
  setValue('skillGaps', onboardingData.step3.skillGaps);
  setValue('certifications', onboardingData.step3.certifications);
  setValue('experience', onboardingData.step3.experience);
  
  if (onboardingData.step3.confidence) {
    const radio = document.querySelector(`input[name="confidence"][value="${onboardingData.step3.confidence}"]`);
    if (radio) {
      radio.checked = true;
      radio.parentElement.classList.add('selected');
    }
  }
  
  // Step 4
  if (onboardingData.step4.formats) {
    onboardingData.step4.formats.forEach(format => {
      const checkbox = document.querySelector(`input[name="format"][value="${format}"]`);
      if (checkbox) {
        checkbox.checked = true;
        checkbox.parentElement.classList.add('selected');
      }
    });
  }
  
  setValue('learningStyle', onboardingData.step4.learningStyle);
  
  if (onboardingData.step4.times) {
    onboardingData.step4.times.forEach(time => {
      const checkbox = document.querySelector(`input[name="time"][value="${time}"]`);
      if (checkbox) {
        checkbox.checked = true;
        checkbox.parentElement.classList.add('selected');
      }
    });
  }
  
  setValue('weeklyHours', onboardingData.step4.weeklyHours);
  setValue('challenges', onboardingData.step4.challenges);
  
  if (onboardingData.step4.motivations) {
    onboardingData.step4.motivations.forEach(motivation => {
      const checkbox = document.querySelector(`input[name="motivation"][value="${motivation}"]`);
      if (checkbox) {
        checkbox.checked = true;
        checkbox.parentElement.classList.add('selected');
      }
    });
  }
}

function setValue(id, value) {
  const element = document.getElementById(id);
  if (element && value) {
    element.value = value;
    if (value.trim() !== '') {
      element.classList.add('has-value');
    }
  }
}

function saveCurrentStepData() {
  // Save to localStorage for persistence
  localStorage.setItem('onboardingData', JSON.stringify(onboardingData));
  
  // Update saved status indicator
  const savedStatus = document.querySelector('.saved-status');
  if (savedStatus) {
    savedStatus.classList.add('saved');
    setTimeout(() => savedStatus.classList.remove('saved'), 1000);
  }
}

// ============================================
// STEP NAVIGATION
// ============================================

function showStep(stepNumber) {
  if (isAnimating) return;
  
  isAnimating = true;
  currentStep = stepNumber;
  
  // Update step content visibility
  document.querySelectorAll('.step-content').forEach(content => {
    content.classList.remove('active');
    setTimeout(() => content.classList.add('hidden'), 300);
  });
  
  setTimeout(() => {
    const activeContent = document.getElementById(`step${stepNumber}`);
    if (activeContent) {
      activeContent.classList.remove('hidden');
      setTimeout(() => {
        activeContent.classList.add('active');
        isAnimating = false;
      }, 50);
    }
  }, 300);
  
  // Update sidebar
  updateSidebar();
  
  // Update progress
  updateProgress();
  
  // Update navigation buttons
  updateNavigationButtons();
}

function updateSidebar() {
  document.querySelectorAll('.step-item').forEach((item, index) => {
    const stepNum = index + 1;
    if (stepNum < currentStep) {
      item.classList.add('completed');
      item.classList.remove('active');
    } else if (stepNum === currentStep) {
      item.classList.add('active');
      item.classList.remove('completed');
    } else {
      item.classList.remove('active', 'completed');
    }
  });
}

function updateProgress() {
  const progress = (currentStep / totalSteps) * 100;
  
  // Update progress circle
  const progressCircle = document.querySelector('.progress-fg');
  if (progressCircle) {
    const circumference = 2 * Math.PI * 54;
    const offset = circumference - (progress / 100) * circumference;
    progressCircle.style.strokeDashoffset = offset;
  }
  
  // Update progress text
  const progressPercent = document.querySelector('.progress-percent');
  const progressNumber = document.querySelector('.step-number-large');
  const progressTitle = document.querySelector('.step-title-large');
  
  if (progressPercent) progressPercent.textContent = `${Math.round(progress)}%`;
  if (progressNumber) progressNumber.innerHTML = `${currentStep}<span class="step-total">/${totalSteps}</span>`;
  
  const stepTitles = ['Career Goals', 'Interests', 'Skills', 'Preferences'];
  if (progressTitle) progressTitle.textContent = stepTitles[currentStep - 1];
  
  // Update large step counter
  const currentStepLarge = document.querySelector('.current-step-large');
  if (currentStepLarge) currentStepLarge.textContent = String(currentStep).padStart(2, '0');
}

function updateNavigationButtons() {
  const prevBtn = document.getElementById('prevBtn');
  const nextBtn = document.getElementById('nextBtn');
  
  if (prevBtn) {
    prevBtn.style.display = currentStep > 1 ? 'flex' : 'none';
  }
  
  if (nextBtn) {
    if (currentStep === totalSteps) {
      nextBtn.innerHTML = '<span class="material-icons">check</span> Complete Onboarding';
    } else {
      nextBtn.innerHTML = 'Continue <span class="material-icons">arrow_forward</span>';
    }
  }
}

function goToNextStep() {
  // Validate current step
  if (!validateCurrentStep()) {
    return;
  }
  
  // Save current step data
  saveCurrentStepData();
  
  if (currentStep < totalSteps) {
    showStep(currentStep + 1);
  } else {
    submitOnboarding();
  }
}

function goToPreviousStep() {
  if (currentStep > 1) {
    saveCurrentStepData();
    showStep(currentStep - 1);
  }
}

// ============================================
// VALIDATION
// ============================================

function validateCurrentStep() {
  let isValid = true;
  let errorMessage = '';
  
  switch(currentStep) {
    case 1:
      const currentRole = document.getElementById('currentRole')?.value.trim();
      const dreamJob = document.getElementById('dreamJob')?.value.trim();
      
      if (!currentRole || !dreamJob) {
        errorMessage = 'Please fill in your current role and dream job';
        isValid = false;
      }
      
      if (isValid) {
        onboardingData.step1.currentRole = currentRole;
        onboardingData.step1.dreamJob = dreamJob;
        onboardingData.step1.shortTermGoals = document.getElementById('shortTermGoals')?.value.trim() || '';
        onboardingData.step1.longTermGoals = document.getElementById('longTermGoals')?.value.trim() || '';
        onboardingData.step1.timeline = document.querySelector('input[name="timeline"]:checked')?.value || null;
      }
      break;
      
    case 2:
      if (onboardingData.step2.interests.length === 0) {
        errorMessage = 'Please add at least one interest';
        isValid = false;
      }
      
      if (isValid) {
        onboardingData.step2.hobbies = document.getElementById('hobbies')?.value.trim() || '';
        onboardingData.step2.learningTopics = document.getElementById('learningTopics')?.value.trim() || '';
        onboardingData.step2.intensity = document.getElementById('interestIntensity')?.value || 5;
      }
      break;
      
    case 3:
      if (onboardingData.step3.skills.length === 0) {
        errorMessage = 'Please add at least one skill';
        isValid = false;
      }
      
      if (isValid) {
        onboardingData.step3.skillGaps = document.getElementById('skillGaps')?.value.trim() || '';
        onboardingData.step3.certifications = document.getElementById('certifications')?.value.trim() || '';
        onboardingData.step3.experience = document.getElementById('experience')?.value.trim() || '';
        onboardingData.step3.confidence = document.querySelector('input[name="confidence"]:checked')?.value || null;
      }
      break;
      
    case 4:
      const formats = Array.from(document.querySelectorAll('input[name="format"]:checked')).map(el => el.value);
      const times = Array.from(document.querySelectorAll('input[name="time"]:checked')).map(el => el.value);
      
      if (formats.length === 0) {
        errorMessage = 'Please select at least one learning format';
        isValid = false;
      }
      
      if (isValid) {
        onboardingData.step4.formats = formats;
        onboardingData.step4.learningStyle = document.getElementById('learningStyle')?.value || '';
        onboardingData.step4.times = times;
        onboardingData.step4.weeklyHours = document.getElementById('weeklyHours')?.value || '';
        onboardingData.step4.challenges = document.getElementById('challenges')?.value.trim() || '';
        onboardingData.step4.motivations = Array.from(document.querySelectorAll('input[name="motivation"]:checked')).map(el => el.value);
      }
      break;
  }
  
  if (!isValid && errorMessage) {
    showNotification(errorMessage, 'error');
    shakeForm();
  }
  
  return isValid;
}

function shakeForm() {
  const form = document.querySelector('.step-content.active');
  if (form) {
    form.style.animation = 'shake 0.5s ease-in-out';
    setTimeout(() => {
      form.style.animation = '';
    }, 500);
  }
}

// ============================================
// SUBMIT ONBOARDING
// ============================================

async function submitOnboarding() {
  if (isSubmitting) return;
  
  isSubmitting = true;
  
  try {
    const submitBtn = document.getElementById('nextBtn');
    const originalText = submitBtn.innerHTML;
    submitBtn.innerHTML = '<span class="material-icons fa-spin">autorenew</span> Saving...';
    submitBtn.disabled = true;
    
    // Prepare data for backend
    const backendData = {
      primary_career_goal: onboardingData.step1.longTermGoals || onboardingData.step1.dreamJob,
      target_role: onboardingData.step1.dreamJob,
      current_status: mapCurrentStatus(onboardingData.step1.currentRole),
      skills: onboardingData.step3.skills.map(s => s.skill),
      time_availability: onboardingData.step4.weeklyHours || '5-10 hours/week',
      learning_preference: mapLearningPreference(onboardingData.step4.learningStyle),
      short_term_goal: onboardingData.step1.shortTermGoals,
      constraint_free_only: false,
      constraint_heavy_workload: false,
      confidence_baseline: parseInt(onboardingData.step3.confidence) || 3
    };
    
    console.log('📤 Submitting onboarding data:', backendData);
    
    // Submit to backend
    const response = await fetch(`${API_CONFIG.BASE_URL}/api/onboarding/start`, {
      method: 'POST',
      headers: API_CONFIG.getHeaders(),
      body: JSON.stringify(backendData)
    });
    
    if (!response.ok) {
      throw new Error('Failed to submit onboarding');
    }
    
    const result = await response.json();
    console.log('✅ Onboarding submitted successfully:', result);
    
    // Mark onboarding as complete
    localStorage.setItem('onboardingComplete', 'true');
    
    // Start learning journey
    await startLearningJourney();
    
    // Show success modal
    prepareSummary();
    showSuccessModal();
    
  } catch (error) {
    console.error('❌ Error submitting onboarding:', error);
    showNotification('Failed to save onboarding. Please try again.', 'error');
    
    const submitBtn = document.getElementById('nextBtn');
    submitBtn.innerHTML = '<span class="material-icons">check</span> Complete Onboarding';
    submitBtn.disabled = false;
  } finally {
    isSubmitting = false;
  }
}

/**
 * Start learning journey after onboarding
 */
async function startLearningJourney() {
  try {
    const goal = onboardingData.step1.dreamJob;
    const result = await PearlAgentService.startJourney(goal);
    
    if (result.success) {
      console.log('✅ Learning journey started:', result.data);
    }
  } catch (error) {
    console.error('❌ Error starting learning journey:', error);
  }
}

/**
 * Map current status to backend enum
 */
function mapCurrentStatus(status) {
  const statusMap = {
    'student': 'student',
    'employed': 'employed',
    'unemployed': 'unemployed',
    'career switcher': 'career_switcher'
  };
  
  const lowerStatus = status.toLowerCase();
  for (const [key, value] of Object.entries(statusMap)) {
    if (lowerStatus.includes(key)) {
      return value;
    }
  }
  
  return 'student';
}

/**
 * Map learning preference to backend enum
 */
function mapLearningPreference(preference) {
  const preferenceMap = {
    'video': 'video',
    'reading': 'reading',
    'hands-on': 'hands_on',
    'mixed': 'mixed',
    'visual': 'video',
    'auditory': 'video',
    'kinesthetic': 'hands_on'
  };
  
  return preferenceMap[preference] || 'mixed';
}

// ============================================
// SUCCESS MODAL
// ============================================

function prepareSummary() {
  const careerGoal = onboardingData.step1.dreamJob || 'Not specified';
  const summaryCareerGoal = document.getElementById('summaryCareerGoal');
  if (summaryCareerGoal) summaryCareerGoal.textContent = careerGoal;
  
  const interests = onboardingData.step2.interests.slice(0, 3).join(', ') || 'Not specified';
  const summaryInterests = document.getElementById('summaryInterests');
  if (summaryInterests) summaryInterests.textContent = interests;
  
  const skills = onboardingData.step3.skills.slice(0, 3).map(s => s.skill).join(', ') || 'Not specified';
  const summarySkills = document.getElementById('summarySkills');
  if (summarySkills) summarySkills.textContent = skills;
  
  const styleLabels = {
    'visual': 'Visual Learner',
    'auditory': 'Auditory Learner',
    'kinesthetic': 'Hands-on Learner',
    'reading': 'Reading/Writing Learner',
    'mixed': 'Mixed Learning Style'
  };
  const learningStyle = styleLabels[onboardingData.step4.learningStyle] || onboardingData.step4.learningStyle || 'Not specified';
  const summaryLearningStyle = document.getElementById('summaryLearningStyle');
  if (summaryLearningStyle) summaryLearningStyle.textContent = learningStyle;
}

function showSuccessModal() {
  const modal = document.getElementById('successModal');
  if (modal) {
    modal.classList.add('show');
    document.body.style.overflow = 'hidden';
    
    // Redirect after 5 seconds or when user clicks button
    setTimeout(() => {
      window.location.href = 'index.html';
    }, 10000);
  }
}

// ============================================
// EVENT LISTENERS
// ============================================

function setupEventListeners() {
  const prevBtn = document.getElementById('prevBtn');
  const nextBtn = document.getElementById('nextBtn');
  
  if (prevBtn) {
    prevBtn.addEventListener('click', goToPreviousStep);
  }
  
  if (nextBtn) {
    nextBtn.addEventListener('click', goToNextStep);
  }
  
  // Step items in sidebar
  document.querySelectorAll('.step-item').forEach(item => {
    item.addEventListener('click', function() {
      const stepNumber = parseInt(this.dataset.step);
      if (stepNumber <= currentStep) {
        showStep(stepNumber);
      }
    });
  });
  
  // Auto-save on input
  document.addEventListener('input', function(e) {
    if (e.target.matches('input, textarea, select')) {
      saveCurrentStepData();
    }
  });
  
  // Auto-save on change
  document.addEventListener('change', function(e) {
    if (e.target.matches('input, select')) {
      saveCurrentStepData();
      
      if (e.target.type === 'radio' || e.target.type === 'checkbox') {
        const card = e.target.closest('.timeline-card, .confidence-card, .preference-card, .motivation-card');
        if (card) {
          card.classList.add('selected');
        }
      }
    }
  });
  
  // Interest/skill input Enter key
  const interestInput = document.getElementById('interestInput');
  const skillInput = document.getElementById('skillInput');
  
  if (interestInput) {
    interestInput.addEventListener('keypress', function(e) {
      if (e.key === 'Enter') {
        e.preventDefault();
        addInterest();
      }
    });
  }
  
  if (skillInput) {
    skillInput.addEventListener('keypress', function(e) {
      if (e.key === 'Enter') {
        e.preventDefault();
        addSkill();
      }
    });
  }
  
  // Keyboard shortcuts
  document.addEventListener('keydown', function(e) {
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
      e.preventDefault();
      goToNextStep();
    }
    
    if (e.key === 'Escape' && currentStep > 1) {
      goToPreviousStep();
    }
  });
}

// ============================================
// INTERACTIVE ELEMENTS
// ============================================

function initInteractiveElements() {
  // Floating labels
  document.querySelectorAll('.form-group.floating input, .form-group.floating textarea, .form-group.floating select').forEach(element => {
    if (element.value.trim() !== '') {
      element.classList.add('has-value');
    }
    
    element.addEventListener('focus', function() {
      this.parentElement.classList.add('focused');
    });
    
    element.addEventListener('blur', function() {
      this.parentElement.classList.remove('focused');
    });
  });
  
  // Card interactions
  document.querySelectorAll('.timeline-card, .confidence-card, .preference-card, .motivation-card').forEach(card => {
    card.addEventListener('click', function() {
      const input = this.querySelector('input');
      if (input) {
        if (input.type === 'checkbox') {
          input.checked = !input.checked;
        } else if (input.type === 'radio') {
          // Remove selected from siblings
          const siblings = this.parentElement.querySelectorAll('.selected');
          siblings.forEach(sib => sib.classList.remove('selected'));
        }
        
        if (input.checked) {
          this.classList.add('selected');
        } else {
          this.classList.remove('selected');
        }
        
        input.dispatchEvent(new Event('change', { bubbles: true }));
      }
    });
  });
}

// ============================================
// INTERESTS & SKILLS
// ============================================

function addInterest() {
  const input = document.getElementById('interestInput');
  const value = input.value.trim();
  
  if (value && !onboardingData.step2.interests.includes(value)) {
    onboardingData.step2.interests.push(value);
    renderInterests();
    input.value = '';
    saveCurrentStepData();
  }
}

function removeInterest(interest) {
  const index = onboardingData.step2.interests.indexOf(interest);
  if (index > -1) {
    onboardingData.step2.interests.splice(index, 1);
    renderInterests();
    saveCurrentStepData();
  }
}

function renderInterests() {
  const container = document.getElementById('interestsList');
  if (!container) return;
  
  container.innerHTML = onboardingData.step2.interests.map(interest => `
    <div class="tag-item">
      <span>${interest}</span>
      <button type="button" onclick="removeInterest('${interest}')">
        <span class="material-icons">close</span>
      </button>
    </div>
  `).join('');
}

function addSkill() {
  const input = document.getElementById('skillInput');
  const value = input.value.trim();
  
  if (value && !onboardingData.step3.skills.find(s => s.skill === value)) {
    onboardingData.step3.skills.push({
      skill: value,
      level: 'intermediate'
    });
    renderSkills();
    input.value = '';
    saveCurrentStepData();
  }
}

function removeSkill(skill) {
  const index = onboardingData.step3.skills.findIndex(s => s.skill === skill);
  if (index > -1) {
    onboardingData.step3.skills.splice(index, 1);
    renderSkills();
    saveCurrentStepData();
  }
}

function renderSkills() {
  const container = document.getElementById('skillsList');
  if (!container) return;
  
  container.innerHTML = onboardingData.step3.skills.map(skill => `
    <div class="tag-item">
      <span>${skill.skill}</span>
      <button type="button" onclick="removeSkill('${skill.skill}')">
        <span class="material-icons">close</span>
      </button>
    </div>
  `).join('');
}

// ============================================
// UTILITY FUNCTIONS
// ============================================

function loadTheme() {
  const savedTheme = localStorage.getItem('theme') || 'light';
  if (savedTheme === 'dark') {
    document.body.classList.add('dark');
    const icon = document.querySelector('.theme-toggle .material-icons');
    if (icon) icon.textContent = 'light_mode';
  }
}

function toggleTheme() {
  document.body.classList.toggle('dark');
  const icon = document.querySelector('.theme-toggle .material-icons');
  const isDark = document.body.classList.contains('dark');
  
  icon.textContent = isDark ? 'light_mode' : 'dark_mode';
  localStorage.setItem('theme', isDark ? 'dark' : 'light');
  
  showNotification(isDark ? 'Dark mode enabled' : 'Light mode enabled');
}

function showNotification(message, type = 'info') {
  const notification = document.createElement('div');
  notification.className = `notification ${type}`;
  notification.textContent = message;
  
  notification.style.cssText = `
    position: fixed;
    bottom: 20px;
    right: 20px;
    background: var(--card-light);
    color: var(--text-light);
    padding: 12px 24px;
    border-radius: var(--radius-md);
    box-shadow: var(--shadow-lg);
    z-index: 1000;
    animation: slideInUp 0.3s ease;
    border-left: 4px solid var(--primary);
  `;
  
  if (type === 'success') {
    notification.style.borderLeftColor = '#10b981';
  } else if (type === 'error') {
    notification.style.borderLeftColor = '#ef4444';
  }
  
  document.body.appendChild(notification);
  
  setTimeout(() => {
    notification.style.opacity = '0';
    setTimeout(() => notification.remove(), 300);
  }, 3000);
}

function skipOnboarding() {
  if (confirm('Skip onboarding? You can always complete it later from your profile settings.')) {
    localStorage.setItem('onboardingSkipped', 'true');
    window.location.href = 'index.html';
  }
}

function goBack() {
  if (document.referrer) {
    window.history.back();
  } else {
    window.location.href = 'index.html';
  }
}

// Make functions globally available
window.addInterest = addInterest;
window.addSkill = addSkill;
window.removeInterest = removeInterest;
window.removeSkill = removeSkill;
window.toggleTheme = toggleTheme;
window.goBack = goBack;
window.skipOnboarding = skipOnboarding;