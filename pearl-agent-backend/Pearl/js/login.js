// Navigation
function goBack() {
  history.back();
}

// Theme Toggle
function toggleTheme() {
  document.body.classList.toggle('dark');
  const icon = document.querySelector('.theme-toggle .material-icons');
  const isDark = document.body.classList.contains('dark');
  icon.textContent = isDark ? 'light_mode' : 'dark_mode';
  
  // Save preference to localStorage
  localStorage.setItem('theme', isDark ? 'dark' : 'light');
  
  // Show notification
  showSnackbar(isDark ? 'Dark mode enabled' : 'Light mode enabled');
}

// Check saved theme preference
window.addEventListener('DOMContentLoaded', () => {
  const savedTheme = localStorage.getItem('theme');
  if (savedTheme === 'dark') {
    document.body.classList.add('dark');
    const icon = document.querySelector('.theme-toggle .material-icons');
    if (icon) icon.textContent = 'light_mode';
  }
  
  // Check if already logged in
  checkAuthStatus();
});

// Check if already logged in
function checkAuthStatus() {
  if (AuthService.isAuthenticated()) {
    showSnackbar('Already logged in. Redirecting...', 'success');
    setTimeout(() => {
      window.location.href = 'index.html';
    }, 1000);
  }
}

// Password Toggle
function togglePassword(id) {
  const field = document.getElementById(id);
  const icon = field.parentElement.querySelector('.toggle');
  
  if (field.type === 'password') {
    field.type = 'text';
    icon.textContent = 'visibility';
    icon.style.color = 'var(--primary)';
  } else {
    field.type = 'password';
    icon.textContent = 'visibility_off';
    icon.style.color = '';
  }
}

// Form Validation
const form = document.getElementById('signupForm');

form.addEventListener('submit', async function (e) {
  e.preventDefault();

  // Reset errors
  document.querySelectorAll('.error').forEach(el => {
    el.textContent = '';
    el.style.display = 'none';
  });

  // Get form values
  const email = document.getElementById('email').value.trim();
  const password = document.getElementById('password').value;
  const confirm = document.getElementById('confirmPassword').value;
  const terms = document.getElementById('terms').checked;

  let isValid = true;

  // Email validation
  if (!email) {
    showError('emailError', 'Email is required');
    isValid = false;
  } else if (!/^\S+@\S+\.\S+$/.test(email)) {
    showError('emailError', 'Please enter a valid email address');
    isValid = false;
  }

  // Password validation
  if (!password) {
    showError('passwordError', 'Password is required');
    isValid = false;
  } else if (password.length < 8) {
    showError('passwordError', 'Password must be at least 8 characters');
    isValid = false;
  } else if (!/(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]/.test(password)) {
    showError('passwordError', 'Password must contain uppercase, number, and special character');
    isValid = false;
  }

  // Confirm password validation
  if (!confirm) {
    showError('confirmError', 'Please confirm your password');
    isValid = false;
  } else if (password !== confirm) {
    showError('confirmError', 'Passwords do not match');
    isValid = false;
  }

  // Terms validation
  if (!terms) {
    showSnackbar('Please accept the terms and conditions', 'error');
    document.getElementById('terms').focus();
    return;
  }

  if (!isValid) return;

  // Show loading state
  const submitBtn = form.querySelector('button[type="submit"]');
  const originalText = submitBtn.textContent;
  submitBtn.textContent = 'Creating Account...';
  submitBtn.disabled = true;

  try {
    // Extract username from email (before @)
    const username = email.split('@')[0];
    
    console.log('📤 Attempting signup with:', { email, username });
    
    // Call backend API
    const result = await AuthService.signup(email, password, username);
    
    if (result.success) {
      console.log('✅ Signup successful:', result);
      showSnackbar('Account created successfully!', 'success');
      
      // IMPORTANT: Redirect to ONBOARDING, not index.html
      setTimeout(() => {
        console.log('🔄 Redirecting to onboarding...');
        window.location.href = 'onboarding.html';
      }, 1500);
    } else {
      throw new Error(result.message || 'Failed to create account');
    }
    
  } catch (error) {
    console.error('❌ Signup error:', error);
    showSnackbar(error.message || 'Failed to create account. Please try again.', 'error');
    submitBtn.textContent = originalText;
    submitBtn.disabled = false;
  }
});

// Helper Functions
function showError(elementId, message) {
  const element = document.getElementById(elementId);
  if (element) {
    element.textContent = message;
    element.style.display = 'flex';
    element.style.alignItems = 'center';
    element.innerHTML = `<span class="material-icons" style="font-size: 16px; margin-right: 4px;">error</span>${message}`;
  }
}

function showSnackbar(message, type = 'info') {
  const snackbar = document.getElementById('snackbar');
  
  // Set message and type
  snackbar.textContent = message;
  snackbar.className = 'snackbar';
  
  // Add type class
  if (type === 'success') {
    snackbar.style.background = 'linear-gradient(135deg, #10b981 0%, #059669 100%)';
  } else if (type === 'error') {
    snackbar.style.background = 'linear-gradient(135deg, #ef4444 0%, #dc2626 100%)';
  } else {
    snackbar.style.background = 'linear-gradient(135deg, #3b82f6 0%, #1d4ed8 100%)';
  }
  
  // Show snackbar
  snackbar.classList.add('show');
  
  // Auto hide after 4 seconds
  setTimeout(() => {
    snackbar.classList.remove('show');
  }, 4000);
}

// Terms and Privacy modals
function showTerms() {
  showSnackbar('Terms & Conditions page would open here', 'info');
  // In real app: window.open('terms.html', '_blank');
}

function showPrivacy() {
  showSnackbar('Privacy Policy page would open here', 'info');
  // In real app: window.open('privacy.html', '_blank');
}

// Real-time validation
document.getElementById('email').addEventListener('blur', validateEmailField);
document.getElementById('password').addEventListener('input', validatePasswordStrength);
document.getElementById('confirmPassword').addEventListener('input', validateConfirmPassword);

function validateEmailField() {
  const email = document.getElementById('email').value.trim();
  const emailError = document.getElementById('emailError');
  
  if (!email) return;
  
  if (!/^\S+@\S+\.\S+$/.test(email)) {
    showError('emailError', 'Please enter a valid email');
  } else {
    emailError.textContent = '';
    emailError.style.display = 'none';
  }
}

function validatePasswordStrength() {
  const password = document.getElementById('password').value;
  const passwordError = document.getElementById('passwordError');
  
  if (!password) return;
  
  if (password.length < 8) {
    showError('passwordError', 'Password strength: Weak (min 8 characters)');
  } else if (!/(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])/.test(password)) {
    showError('passwordError', 'Password strength: Medium (add uppercase, number, special)');
  } else {
    passwordError.innerHTML = '<span class="material-icons" style="font-size: 16px; margin-right: 4px; color: #10b981;">check_circle</span>Password strength: Strong';
    passwordError.style.display = 'flex';
    passwordError.style.color = '#10b981';
  }
}

function validateConfirmPassword() {
  const password = document.getElementById('password').value;
  const confirm = document.getElementById('confirmPassword').value;
  const confirmError = document.getElementById('confirmError');
  
  if (!confirm) return;
  
  if (password !== confirm) {
    showError('confirmError', 'Passwords do not match');
  } else {
    confirmError.innerHTML = '<span class="material-icons" style="font-size: 16px; margin-right: 4px; color: #10b981;">check_circle</span>Passwords match';
    confirmError.style.display = 'flex';
    confirmError.style.color = '#10b981';
  }
}

// Enter key to submit
document.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.target.matches('button')) {
    const form = document.getElementById('signupForm');
    const submitBtn = form.querySelector('button[type="submit"]');
    if (submitBtn && !submitBtn.disabled) {
      submitBtn.click();
    }
  }
});