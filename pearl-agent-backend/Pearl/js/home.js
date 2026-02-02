// ============================================
// PEARL HOME PAGE - DATABASE INTEGRATED
// ============================================

// Global State
let userData = null;
let onboardingData = null;
let gamificationData = null;
let sessionData = null;
let skillsData = null;

// DOM Elements
const mobileMenuBtn = document.querySelector('.mobile-menu-btn');
const mobileMenu = document.querySelector('.mobile-menu');
const mobileMenuClose = document.querySelector('.mobile-menu-close');
const moduleCards = document.querySelectorAll('.module-card');
const applyButtons = document.querySelectorAll('.apply-btn');
const filterButtons = document.querySelectorAll('.filter-btn');
const moduleModal = document.querySelector('.module-modal');
const storyModal = document.querySelector('.story-modal');
const modalClose = document.querySelectorAll('.modal-close');
const storyClose = document.querySelector('.story-close');
const snackbar = document.querySelector('.snackbar');
const themeToggle = document.getElementById('themeToggle');
const mobileThemeToggle = document.getElementById('mobileThemeToggle');
const taikenPreview = document.querySelector('.taiken-preview');
const enterStoryBtn = document.getElementById('enterStoryBtn');
const continueBtn = document.getElementById('continueBtn');

// ============================================
// INITIALIZATION
// ============================================

document.addEventListener('DOMContentLoaded', async function() {
  console.log('🚀 Initializing PEARL Home Page...');
  
  // Check authentication
  if (!AuthService.isAuthenticated()) {
    console.log('❌ User not authenticated, redirecting to login...');
    window.location.href = 'login.html';
    return;
  }
  
  // Show loading state
  showPageLoader();
  
  try {
    // Load all user data
    await loadUserData();
    await loadOnboardingData();
    await loadGamificationData();
    await loadSessionData();
    await loadSkillsData();
    
    // Update UI with data
    updateUserInterface();
    
    // Initialize event listeners
    initializeEventListeners();
    
    // Initialize animations
    initializeAnimations();
    
    console.log('✅ Home page initialized successfully');
  } catch (error) {
    console.error('❌ Error initializing home page:', error);
    showNotification('Failed to load dashboard. Please refresh.', 'error');
  } finally {
    hidePageLoader();
  }
});

// ============================================
// DATA LOADING FUNCTIONS
// ============================================

/**
 * Load user profile data from database
 */
async function loadUserData() {
  try {
    const user = AuthService.getCurrentUser();
    if (!user || !user.id) {
      throw new Error('No user data found');
    }
    
    console.log('📥 Loading user profile data...');
    
    // Call the backend API to get complete user profile
    const response = await fetch(`${API_CONFIG.BASE_URL}/api/profile/complete/${user.id}`, {
      headers: API_CONFIG.getHeaders()
    });
    
    if (!response.ok) {
      throw new Error('Failed to load user profile');
    }
    
    const data = await response.json();
    userData = data;
    
    console.log('✅ User data loaded:', userData);
    return userData;
  } catch (error) {
    console.error('❌ Error loading user data:', error);
    // Fallback to cached user data
    userData = AuthService.getCurrentUser();
    throw error;
  }
}

/**
 * Load onboarding data
 */
async function loadOnboardingData() {
  try {
    const user = AuthService.getCurrentUser();
    console.log('📥 Loading onboarding data...');
    
    const response = await fetch(`${API_CONFIG.BASE_URL}/api/onboarding/status`, {
      headers: API_CONFIG.getHeaders()
    });
    
    if (response.ok) {
      const data = await response.json();
      onboardingData = data;
      console.log('✅ Onboarding data loaded:', onboardingData);
    }
  } catch (error) {
    console.error('❌ Error loading onboarding data:', error);
  }
}

/**
 * Load gamification data
 */
async function loadGamificationData() {
  try {
    console.log('📥 Loading gamification data...');
    
    const response = await fetch(`${API_CONFIG.BASE_URL}/api/gamification/summary`, {
      headers: API_CONFIG.getHeaders()
    });
    
    if (response.ok) {
      const data = await response.json();
      gamificationData = data;
      console.log('✅ Gamification data loaded:', gamificationData);
    }
  } catch (error) {
    console.error('❌ Error loading gamification data:', error);
  }
}

/**
 * Load current learning session
 */
async function loadSessionData() {
  try {
    const sessionId = localStorage.getItem('session_id');
    
    if (sessionId) {
      console.log('📥 Loading session data...');
      
      const response = await fetch(`${API_CONFIG.BASE_URL}/api/learning/session/${sessionId}`, {
        headers: API_CONFIG.getHeaders()
      });
      
      if (response.ok) {
        const data = await response.json();
        sessionData = data;
        console.log('✅ Session data loaded:', sessionData);
      }
    }
  } catch (error) {
    console.error('❌ Error loading session data:', error);
  }
}

/**
 * Load user skills data
 */
async function loadSkillsData() {
  try {
    const user = AuthService.getCurrentUser();
    console.log('📥 Loading skills data...');
    
    const response = await fetch(`${API_CONFIG.BASE_URL}/api/user/${user.id}/skills`, {
      headers: API_CONFIG.getHeaders()
    });
    
    if (response.ok) {
      const data = await response.json();
      skillsData = data;
      console.log('✅ Skills data loaded:', skillsData);
    }
  } catch (error) {
    console.error('❌ Error loading skills data:', error);
  }
}

// ============================================
// UI UPDATE FUNCTIONS
// ============================================

/**
 * Update all UI elements with loaded data
 */
function updateUserInterface() {
  updateUserProfile();
  updateHeroStats();
  updateLearningPath();
  updateProgressCard();
  updateSkillsDisplay();
  updateRecommendations();
}

/**
 * Update user profile in navbar
 */
function updateUserProfile() {
  if (!userData) {
    console.log('⚠️ No user data to display');
    return;
  }
  
  console.log('🎨 Updating user profile UI with:', userData);
  
  // Update user avatar - Try multiple selectors
  const avatarSelectors = ['.user-avatar', '.mobile-avatar', 'img[alt="User"]'];
  avatarSelectors.forEach(selector => {
    const avatars = document.querySelectorAll(selector);
    avatars.forEach(avatar => {
      if (userData.profile_pic) {
        avatar.src = userData.profile_pic;
        console.log('✅ Set avatar to:', userData.profile_pic);
      } else {
        // Use a default avatar based on username
        const avatarUrl = `https://api.dicebear.com/7.x/avataaars/svg?seed=${userData.username || 'user'}`;
        avatar.src = avatarUrl;
        console.log('✅ Set default avatar for:', userData.username);
      }
    });
  });
  
  // Update username - Try multiple selectors
  const usernameSelectors = ['.user-name', '.mobile-menu-header h4', '#navUserName', '#mobileUserName'];
  usernameSelectors.forEach(selector => {
    const elements = document.querySelectorAll(selector);
    elements.forEach(el => {
      if (el) {
        el.textContent = userData.username || 'User';
        console.log('✅ Set username to:', userData.username);
      }
    });
  });
  
  // Update user level
  const levelSelectors = ['.user-level', '#navUserLevel'];
  if (gamificationData) {
    const level = calculateLevel(gamificationData.total_points || 0);
    levelSelectors.forEach(selector => {
      const levelElement = document.querySelector(selector);
      if (levelElement) {
        levelElement.textContent = `Level ${level}`;
        console.log('✅ Set level to:', level);
      }
    });
  }
  
  // Update mobile menu user role
  const mobileUserRole = document.querySelector('.mobile-menu-header p');
  if (mobileUserRole && onboardingData) {
    mobileUserRole.textContent = onboardingData.target_role || 'Learner';
    console.log('✅ Set role to:', onboardingData.target_role);
  }
}

/**
 * Update hero section stats
 */
function updateHeroStats() {
  // Calculate completion percentage
  let completionRate = 0;
  if (sessionData && sessionData.roadmap) {
    const totalModules = sessionData.roadmap.skills?.length || 0;
    const completedModules = sessionData.roadmap.skills?.filter(s => s.status === 'completed').length || 0;
    completionRate = totalModules > 0 ? Math.round((completedModules / totalModules) * 100) : 0;
  }
  
  // Update completion stat
  const completionStat = document.querySelector('.stat-item:nth-child(1) .stat-number');
  if (completionStat) {
    completionStat.textContent = `${completionRate}%`;
  }
  
  // Update skills mastered
  const skillsStat = document.querySelector('.stat-item:nth-child(2) .stat-number');
  if (skillsStat && skillsData) {
    const masteredSkills = skillsData.filter(s => s.confidence_score >= 0.8).length;
    skillsStat.textContent = masteredSkills;
  }
  
  // Update job match score (if available)
  const jobMatchStat = document.querySelector('.stat-item:nth-child(3) .stat-number');
  if (jobMatchStat && sessionData) {
    const matchScore = sessionData.job_match_score || 75;
    jobMatchStat.textContent = `${matchScore}%`;
  }
}

/**
 * Update learning path section
 */
function updateLearningPath() {
  if (!sessionData || !sessionData.roadmap) return;
  
  // Update current path badge
  const pathBadge = document.querySelector('.progress-card .badge');
  if (pathBadge && onboardingData) {
    pathBadge.textContent = onboardingData.target_role || 'Learning Path';
  }
  
  // Update overall progress
  const progressPercent = document.querySelector('.progress-header span:last-child');
  const progressFill = document.querySelector('.progress-card .progress-fill');
  
  if (sessionData.roadmap.skills) {
    const totalModules = sessionData.roadmap.skills.length;
    const completedModules = sessionData.roadmap.skills.filter(s => s.status === 'completed').length;
    const percentage = Math.round((completedModules / totalModules) * 100);
    
    if (progressPercent) progressPercent.textContent = `${percentage}%`;
    if (progressFill) progressFill.style.width = `${percentage}%`;
  }
  
  // Update learning items
  const learningItems = document.querySelectorAll('.learning-item');
  if (sessionData.roadmap.skills && learningItems.length > 0) {
    sessionData.roadmap.skills.slice(0, 4).forEach((skill, index) => {
      if (learningItems[index]) {
        const item = learningItems[index];
        const icon = item.querySelector('i');
        const span = item.querySelector('span');
        
        if (span) span.textContent = skill.name;
        
        if (skill.status === 'completed') {
          item.classList.add('completed');
          item.classList.remove('active', 'locked');
          if (icon) icon.className = 'fas fa-check-circle';
        } else if (skill.status === 'active') {
          item.classList.add('active');
          item.classList.remove('completed', 'locked');
          if (icon) icon.className = 'fas fa-spinner fa-pulse';
        } else {
          item.classList.add('locked');
          item.classList.remove('completed', 'active');
          if (icon) icon.className = 'fas fa-lock';
        }
      }
    });
  }
}

/**
 * Update progress card
 */
function updateProgressCard() {
  if (!gamificationData) return;
  
  // Update streak
  const streakElement = document.querySelector('.streak-count');
  if (streakElement) {
    streakElement.textContent = gamificationData.streak_count || 0;
  }
  
  // Update points
  const pointsElement = document.querySelector('.points-value');
  if (pointsElement) {
    pointsElement.textContent = gamificationData.total_points || 0;
  }
}

/**
 * Update skills display
 */
function updateSkillsDisplay() {
  if (!skillsData || skillsData.length === 0) return;
  
  const skillsContainer = document.querySelector('.skills-overview');
  if (!skillsContainer) return;
  
  // Clear existing skills
  skillsContainer.innerHTML = '<h3>Your Skills</h3>';
  
  // Add top skills
  const topSkills = skillsData.slice(0, 6);
  topSkills.forEach(skill => {
    const skillElement = document.createElement('div');
    skillElement.className = 'skill-item';
    skillElement.innerHTML = `
      <div class="skill-header">
        <span class="skill-name">${skill.skill_name}</span>
        <span class="skill-percentage">${Math.round(skill.confidence_score * 100)}%</span>
      </div>
      <div class="skill-bar">
        <div class="skill-fill" style="width: ${skill.confidence_score * 100}%"></div>
      </div>
    `;
    skillsContainer.appendChild(skillElement);
  });
}

/**
 * Update personalized recommendations
 */
async function updateRecommendations() {
  if (!sessionData || !sessionData.current_skill) return;
  
  try {
    const response = await ContentService.getRecommendations(sessionData.current_skill);
    
    if (response.success && response.data) {
      // Update UI with recommendations
      console.log('✅ Recommendations loaded:', response.data);
    }
  } catch (error) {
    console.error('❌ Error loading recommendations:', error);
  }
}

// ============================================
// UTILITY FUNCTIONS
// ============================================

/**
 * Calculate user level based on points
 */
function calculateLevel(points) {
  // Simple level calculation: 100 points per level
  return Math.floor(points / 100) + 1;
}

/**
 * Show page loader
 */
function showPageLoader() {
  const loader = document.createElement('div');
  loader.id = 'pageLoader';
  loader.className = 'page-loader';
  loader.innerHTML = `
    <div class="loader-content">
      <div class="spinner"></div>
      <p>Loading your dashboard...</p>
    </div>
  `;
  document.body.appendChild(loader);
  
  // Add styles
  const style = document.createElement('style');
  style.textContent = `
    .page-loader {
      position: fixed;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      background: rgba(255, 255, 255, 0.95);
      display: flex;
      align-items: center;
      justify-content: center;
      z-index: 10000;
    }
    
    body.dark .page-loader {
      background: rgba(18, 18, 18, 0.95);
    }
    
    .loader-content {
      text-align: center;
    }
    
    .spinner {
      width: 50px;
      height: 50px;
      border: 4px solid #e0e0e0;
      border-top-color: #2196f3;
      border-radius: 50%;
      animation: spin 1s linear infinite;
      margin: 0 auto 20px;
    }
    
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
    
    .loader-content p {
      color: #666;
      font-size: 14px;
    }
    
    body.dark .loader-content p {
      color: #999;
    }
  `;
  document.head.appendChild(style);
}

/**
 * Hide page loader
 */
function hidePageLoader() {
  const loader = document.getElementById('pageLoader');
  if (loader) {
    loader.style.opacity = '0';
    setTimeout(() => loader.remove(), 300);
  }
}

/**
 * Show notification
 */
function showNotification(message, type = 'success') {
  const snackbarContent = snackbar.querySelector('.snackbar-content');
  const icon = snackbarContent.querySelector('i');
  
  // Update icon based on type
  if (type === 'success') {
    icon.className = 'fas fa-check-circle';
    snackbar.style.background = 'var(--success)';
  } else if (type === 'error') {
    icon.className = 'fas fa-exclamation-circle';
    snackbar.style.background = 'var(--danger)';
  } else {
    icon.className = 'fas fa-info-circle';
    snackbar.style.background = 'var(--primary)';
  }
  
  snackbarContent.querySelector('span').textContent = message;
  snackbar.classList.add('show');
  
  setTimeout(() => {
    snackbar.classList.remove('show');
  }, 3000);
}

// ============================================
// EVENT LISTENERS
// ============================================

function initializeEventListeners() {
  console.log('🎧 Setting up event listeners...');
  
  // Mobile menu toggle
  if (mobileMenuBtn) {
    mobileMenuBtn.addEventListener('click', () => {
      mobileMenu.classList.add('active');
      document.body.style.overflow = 'hidden';
    });
  }
  
  if (mobileMenuClose) {
    mobileMenuClose.addEventListener('click', () => {
      mobileMenu.classList.remove('active');
      document.body.style.overflow = 'auto';
    });
  }
  
  // Logout button - Try multiple selectors
  const logoutSelectors = ['.logout', 'a[href*="login.html"]', '.mobile-menu a:last-child'];
  logoutSelectors.forEach(selector => {
    const logoutBtns = document.querySelectorAll(selector);
    logoutBtns.forEach(logoutBtn => {
      if (logoutBtn && logoutBtn.textContent.toLowerCase().includes('logout')) {
        logoutBtn.addEventListener('click', async (e) => {
          e.preventDefault();
          
          console.log('🚪 Logout clicked');
          
          if (confirm('Are you sure you want to logout?')) {
            try {
              console.log('📤 Logging out...');
              await AuthService.signout();
              console.log('✅ Logout successful');
              showNotification('Logged out successfully', 'success');
              
              setTimeout(() => {
                window.location.href = 'login.html';
              }, 500);
            } catch (error) {
              console.error('❌ Logout error:', error);
              // Force logout even if API fails
              localStorage.clear();
              window.location.href = 'login.html';
            }
          }
        });
      }
    });
  });
  
  // Theme toggle
  if (themeToggle) {
    themeToggle.addEventListener('click', toggleTheme);
  }
  
  if (mobileThemeToggle) {
    mobileThemeToggle.addEventListener('change', toggleTheme);
  }
  
  // Module cards click
  moduleCards.forEach(card => {
    card.addEventListener('click', () => {
      if (!card.classList.contains('locked')) {
        const moduleId = card.dataset.module;
        openModuleModal(moduleId);
      } else {
        showNotification('Complete previous modules to unlock this one', 'info');
      }
    });
  });
  
  // Modal close buttons
  modalClose.forEach(btn => {
    btn.addEventListener('click', () => {
      moduleModal.classList.remove('active');
      storyModal.classList.remove('active');
      document.body.style.overflow = 'auto';
    });
  });
  
  // Enter story button
  if (enterStoryBtn) {
    enterStoryBtn.addEventListener('click', () => {
      window.location.href = 'taiken-story.html';
    });
  }
  
  console.log('✅ Event listeners initialized');
}

// ============================================
// ANIMATIONS
// ============================================

function initializeAnimations() {
  // Smooth scrolling
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e) {
      e.preventDefault();
      const targetId = this.getAttribute('href');
      if (targetId === '#') return;
      
      const targetElement = document.querySelector(targetId);
      if (targetElement) {
        const offset = 80;
        const targetPosition = targetElement.offsetTop - offset;
        window.scrollTo({ top: targetPosition, behavior: 'smooth' });
        
        mobileMenu.classList.remove('active');
        document.body.style.overflow = 'auto';
      }
    });
  });
  
  // Initialize progress animations
  animateProgressBars();
  
  // Initialize scroll animations
  initializeScrollAnimations();
}

function animateProgressBars() {
  const progressBars = document.querySelectorAll('.progress-fill, .skill-fill');
  progressBars.forEach((bar, index) => {
    const width = bar.style.width;
    bar.style.width = '0%';
    setTimeout(() => {
      bar.style.width = width;
      bar.style.transition = 'width 1s ease';
    }, index * 100);
  });
}

function initializeScrollAnimations() {
  const observerOptions = {
    threshold: 0.1,
    rootMargin: '0px 0px -50px 0px'
  };
  
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('animate-in');
      }
    });
  }, observerOptions);
  
  document.querySelectorAll('.roadmap-level, .progress-card, .job-card, .module-card').forEach(el => {
    observer.observe(el);
  });
}

function toggleTheme() {
  document.body.classList.toggle('dark');
  const isDark = document.body.classList.contains('dark');
  
  const icon = document.querySelector('.theme-toggle i');
  if (icon) {
    icon.className = isDark ? 'fas fa-sun' : 'fas fa-moon';
  }
  
  localStorage.setItem('theme', isDark ? 'dark' : 'light');
  showNotification(isDark ? 'Dark mode enabled' : 'Light mode enabled', 'success');
}

// Load theme on page load
const savedTheme = localStorage.getItem('theme') || 'light';
if (savedTheme === 'dark') {
  document.body.classList.add('dark');
}

function openModuleModal(moduleId) {
  // Implement module modal logic
  console.log('Opening module:', moduleId);
  moduleModal.classList.add('active');
  document.body.style.overflow = 'hidden';
}