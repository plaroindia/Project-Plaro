// Game State
let gameState = {
    currentScene: 1,
    totalScenes: 4,
    lives: 3,
    hints: 3,
    hintPoints: 3,
    xp: 0,
    chapterProgress: 45,
    answers: {},
    usedHints: [],
    purchasedHints: [],
    startTime: new Date(),
    livesTimer: null
};

// DOM Elements
const themeToggle = document.getElementById('themeToggle');
const mobileMenuBtn = document.querySelector('.mobile-menu-btn');
const tabButtons = document.querySelectorAll('.tab-btn');
const tabContents = document.querySelectorAll('.tab-content');
const nextChapterBtn = document.getElementById('nextChapterBtn');
const hintBtn = document.getElementById('hintBtn');
const livesDisplay = document.querySelector('.lives-display');
const livesOverlay = document.getElementById('livesOverlay');
const hintModal = document.getElementById('hintModal');
const successModal = document.getElementById('successModal');
const errorModal = document.getElementById('errorModal');
const continueLearningBtn = document.getElementById('continueLearningBtn');

// Initialize when page loads
document.addEventListener('DOMContentLoaded', function() {
    initThemeToggle();
    initTabs();
    initLivesSystem();
    updateUI();
    
    // Check for saved theme preference
    if (localStorage.getItem('theme') === 'dark') {
        document.body.classList.add('dark');
        themeToggle.innerHTML = '<i class="fas fa-sun"></i>';
    }
    
    // Start lives timer
    startLivesTimer();
    
    // Highlight code with Prism
    Prism.highlightAll();
});

// Theme Toggle
function initThemeToggle() {
    themeToggle.addEventListener('click', () => {
        document.body.classList.toggle('dark');
        if (document.body.classList.contains('dark')) {
            localStorage.setItem('theme', 'dark');
            themeToggle.innerHTML = '<i class="fas fa-sun"></i>';
        } else {
            localStorage.setItem('theme', 'light');
            themeToggle.innerHTML = '<i class="fas fa-moon"></i>';
        }
    });
}

// Tab Navigation
function initTabs() {
    tabButtons.forEach(button => {
        button.addEventListener('click', () => {
            const tabId = button.getAttribute('data-tab');
            
            // Remove active class from all buttons and contents
            tabButtons.forEach(btn => btn.classList.remove('active'));
            tabContents.forEach(content => content.classList.remove('active'));
            
            // Add active class to clicked button and corresponding content
            button.classList.add('active');
            document.getElementById(`${tabId}Tab`).classList.add('active');
        });
    });
}

// Lives System
function initLivesSystem() {
    // Click lives display to show overlay
    livesDisplay.addEventListener('click', () => {
        livesOverlay.classList.add('active');
    });
    
    // Close overlay when clicking outside
    livesOverlay.addEventListener('click', (e) => {
        if (e.target === livesOverlay) {
            closeLivesOverlay();
        }
    });
    
    // Initialize unlock hint buttons
    document.querySelectorAll('.unlock-hint').forEach(button => {
        button.addEventListener('click', (e) => {
            const hintId = e.target.getAttribute('data-hint');
            unlockHint(hintId);
        });
    });
    
    // Hint button click
    hintBtn.addEventListener('click', () => {
        if (gameState.hintPoints > 0) {
            showHintModal();
        } else {
            showNotification('No hint points remaining!', 'error');
        }
    });
    
    // Next chapter button
    nextChapterBtn.addEventListener('click', () => {
        if (gameState.currentScene < gameState.totalScenes) {
            nextScene();
        } else {
            showNotification('Chapter completed! Continue to next chapter?', 'success');
            if (continueLearningBtn) {
                continueLearningBtn.focus();
            }
        }
    });
    
    // Continue learning button
    if (continueLearningBtn) {
        continueLearningBtn.addEventListener('click', () => {
            // In a real app, this would redirect to the next chapter
            showNotification('Redirecting to Chapter 3: The Feature Request...', 'success');
            setTimeout(() => {
                window.location.href = 'taiken-story-chapter3.html'; // Hypothetical next chapter
            }, 1500);
        });
    }
}

// Scene Navigation
function nextScene() {
    if (gameState.currentScene < gameState.totalScenes) {
        // Hide current scene
        const currentScene = document.getElementById(`scene${gameState.currentScene}`);
        currentScene.classList.remove('active');
        
        // Show next scene
        gameState.currentScene++;
        const nextScene = document.getElementById(`scene${gameState.currentScene}`);
        nextScene.classList.add('active');
        
        // Update scene progress
        updateSceneProgress();
        
        // Scroll to top of scene
        nextScene.scrollIntoView({ behavior: 'smooth', block: 'start' });
        
        // Update chapter progress
        updateChapterProgress(15);
        
        // Show notification
        showNotification(`Moving to Scene ${gameState.currentScene}`, 'info');
    }
}

function prevScene() {
    if (gameState.currentScene > 1) {
        // Hide current scene
        const currentScene = document.getElementById(`scene${gameState.currentScene}`);
        currentScene.classList.remove('active');
        
        // Show previous scene
        gameState.currentScene--;
        const prevScene = document.getElementById(`scene${gameState.currentScene}`);
        prevScene.classList.add('active');
        
        // Update scene progress
        updateSceneProgress();
        
        // Scroll to top of scene
        prevScene.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
}

function updateSceneProgress() {
    const sceneProgress = document.querySelector('.scene-progress span');
    if (sceneProgress) {
        sceneProgress.textContent = `Scene ${gameState.currentScene} of ${gameState.totalScenes}`;
    }
}

// Chapter Progress
function updateChapterProgress(increment) {
    gameState.chapterProgress = Math.min(gameState.chapterProgress + increment, 100);
    
    // Update progress bar
    const progressFill = document.querySelector('.story-panel .progress-fill');
    const progressText = document.querySelector('.story-progress-indicator .progress-info span:last-child');
    
    if (progressFill) {
        progressFill.style.width = `${gameState.chapterProgress}%`;
    }
    
    if (progressText) {
        progressText.textContent = `${gameState.chapterProgress}%`;
    }
    
    // Update main dashboard progress if this is the last scene
    if (gameState.currentScene === gameState.totalScenes) {
        updateDashboardProgress();
    }
}

function updateDashboardProgress() {
    // This would update the main dashboard progress via API in a real app
    console.log('Chapter progress updated to:', gameState.chapterProgress);
    
    // Update local storage for demo purposes
    localStorage.setItem('taikenChapterProgress', gameState.chapterProgress.toString());
}

// Answer Checking
function checkAnswer(questionId) {
    const question = document.getElementById(questionId);
    const selectedChoice = question.querySelector('input[type="radio"]:checked');
    
    if (!selectedChoice) {
        showNotification('Please select an answer', 'error');
        return;
    }
    
    const choice = selectedChoice.closest('.choice');
    const isCorrect = choice.getAttribute('data-correct') === 'true';
    
    // Store answer
    gameState.answers[questionId] = {
        selected: selectedChoice.value,
        correct: isCorrect,
        timestamp: new Date()
    };
    
    if (isCorrect) {
        // Correct answer
        choice.style.borderColor = 'var(--success)';
        choice.style.background = 'rgba(16, 185, 129, 0.1)';
        
        // Award XP
        awardXP(25);
        
        // Show success modal
        showSuccessModal();
        
        // Auto-progress after delay if this is the last question in scene
        setTimeout(() => {
            if (gameState.currentScene < gameState.totalScenes) {
                nextScene();
            }
        }, 2000);
    } else {
        // Incorrect answer
        choice.style.borderColor = 'var(--danger)';
        choice.style.background = 'rgba(239, 68, 68, 0.1)';
        
        // Lose a life
        loseLife();
        
        // Show error modal with specific feedback
        let errorMessage = "That's not quite right. ";
        
        if (questionId === 'question1') {
            errorMessage += "Remember to check what the API actually returns vs what the component expects.";
        } else if (questionId === 'question2') {
            errorMessage += "Consider null safety and defensive programming practices.";
        }
        
        showErrorModal(errorMessage);
    }
}

function awardXP(amount) {
    gameState.xp += amount;
    
    // Update XP display if it exists
    const xpDisplay = document.querySelector('.xp-earned');
    if (xpDisplay) {
        xpDisplay.textContent = `+${amount} XP earned`;
    }
    
    // Show XP notification
    showNotification(`+${amount} XP! Total: ${gameState.xp}`, 'success');
}

// Lives Management
function loseLife() {
    if (gameState.lives > 0) {
        gameState.lives--;
        updateLivesDisplay();
        
        if (gameState.lives === 0) {
            showNotification('You ran out of lives! Please wait for lives to regenerate or buy more.', 'error');
            disableInputs();
            startLifeRegenerationTimer();
        }
    }
}

function gainLife() {
    if (gameState.lives < 3) {
        gameState.lives++;
        updateLivesDisplay();
        
        if (gameState.lives === 3) {
            enableInputs();
        }
    }
}

function updateLivesDisplay() {
    const livesContainer = document.querySelector('.lives-container');
    const livesCount = document.querySelector('.lives-count');
    const hearts = livesContainer.querySelectorAll('i');
    
    // Update hearts
    hearts.forEach((heart, index) => {
        if (index < gameState.lives) {
            heart.style.opacity = '1';
        } else {
            heart.style.opacity = '0.3';
        }
    });
    
    // Update count in overlay
    if (livesCount) {
        livesCount.textContent = gameState.lives;
    }
    
    // Update hearts in overlay
    const overlayHearts = document.querySelectorAll('.hearts-display i');
    overlayHearts.forEach((heart, index) => {
        if (index < gameState.lives) {
            heart.style.opacity = '1';
        } else {
            heart.style.opacity = '0.3';
        }
    });
}

function disableInputs() {
    // Disable all interactive elements
    document.querySelectorAll('button, input, textarea').forEach(element => {
        if (!element.classList.contains('lives-overlay') && !element.closest('.lives-overlay')) {
            element.disabled = true;
            element.style.opacity = '0.5';
            element.style.cursor = 'not-allowed';
        }
    });
    
    // Re-enable lives overlay buttons
    document.querySelectorAll('.lives-overlay button').forEach(button => {
        button.disabled = false;
        button.style.opacity = '1';
        button.style.cursor = 'pointer';
    });
}

function enableInputs() {
    // Enable all interactive elements
    document.querySelectorAll('button, input, textarea').forEach(element => {
        element.disabled = false;
        element.style.opacity = '1';
        element.style.cursor = '';
    });
}

// Hint System
function useHint() {
    if (gameState.hintPoints > 0) {
        gameState.hintPoints--;
        gameState.usedHints.push({
            scene: gameState.currentScene,
            timestamp: new Date(),
            cost: 1
        });
        
        updateHintDisplay();
        showNotification(`Hint used! ${gameState.hintPoints} hint points remaining`, 'info');
        
        // Unlock the corresponding hint
        const hintItems = document.querySelectorAll('.hint-item.locked');
        if (hintItems.length > 0) {
            const firstLockedHint = hintItems[0];
            unlockHintElement(firstLockedHint);
        }
        
        closeHintModal();
    } else {
        showNotification('No hint points remaining!', 'error');
    }
}

function unlockHint(hintId) {
    if (gameState.hintPoints > 0) {
        gameState.hintPoints--;
        gameState.purchasedHints.push({
            hintId: hintId,
            timestamp: new Date()
        });
        
        updateHintDisplay();
        
        const hintItem = document.querySelector(`.unlock-hint[data-hint="${hintId}"]`).closest('.hint-item');
        unlockHintElement(hintItem);
        
        showNotification(`Hint ${hintId} unlocked!`, 'success');
    } else {
        showNotification('Not enough hint points!', 'error');
    }
}

function unlockHintElement(hintItem) {
    hintItem.classList.remove('locked');
    hintItem.classList.add('unlocked');
    
    const icon = hintItem.querySelector('.hint-icon i');
    icon.className = 'fas fa-check-circle';
    
    const unlockButton = hintItem.querySelector('.unlock-hint');
    if (unlockButton) {
        unlockButton.style.display = 'none';
    }
    
    // Add to hint history
    addHintHistory(`Unlocked hint: ${hintItem.querySelector('h4').textContent}`);
}

function updateHintDisplay() {
    // Update hint button text
    hintBtn.innerHTML = `<i class="fas fa-lightbulb"></i> Get Hint (${gameState.hintPoints} left)`;
    
    // Update hint count
    const hintCount = document.querySelector('.hints-count .count');
    if (hintCount) {
        hintCount.textContent = gameState.hintPoints;
    }
    
    // Update hint points in modal
    const hintPointsText = document.querySelector('#hintModal .modal-body strong:last-child');
    if (hintPointsText) {
        hintPointsText.textContent = gameState.hintPoints;
    }
}

function addHintHistory(text) {
    const historyContainer = document.querySelector('.hint-history');
    const historyItem = document.createElement('div');
    historyItem.className = 'history-item';
    historyItem.innerHTML = `
        <i class="fas fa-lightbulb"></i>
        <div>
            <strong>${text}</strong>
            <small>Just now - Cost: 1 hint point</small>
        </div>
    `;
    
    historyContainer.insertBefore(historyItem, historyContainer.firstChild);
}

// Timer System
function startLivesTimer() {
    // Check if we need to regenerate a life
    const lastLifeLoss = localStorage.getItem('lastLifeLoss');
    if (lastLifeLoss && gameState.lives < 3) {
        const timeSinceLoss = new Date() - new Date(lastLifeLoss);
        const timeToRegen = 30 * 60 * 1000; // 30 minutes in milliseconds
        
        if (timeSinceLoss >= timeToRegen) {
            gainLife();
            localStorage.removeItem('lastLifeLoss');
        } else {
            // Start timer for next life regeneration
            const timeLeft = timeToRegen - timeSinceLoss;
            startLifeTimer(timeLeft);
        }
    }
}

function startLifeRegenerationTimer() {
    // Store when life was lost
    localStorage.setItem('lastLifeLoss', new Date().toISOString());
    
    // Start 30-minute timer
    startLifeTimer(30 * 60 * 1000);
}

function startLifeTimer(duration) {
    clearInterval(gameState.livesTimer);
    
    gameState.livesTimer = setInterval(() => {
        duration -= 1000;
        
        if (duration <= 0) {
            clearInterval(gameState.livesTimer);
            gainLife();
            updateTimerDisplay('00:00');
        } else {
            updateTimerDisplay(formatTime(duration));
        }
    }, 1000);
}

function updateTimerDisplay(time) {
    const timerDisplay = document.getElementById('lifeTimer');
    if (timerDisplay) {
        timerDisplay.textContent = time;
    }
}

function formatTime(milliseconds) {
    const minutes = Math.floor(milliseconds / 60000);
    const seconds = Math.floor((milliseconds % 60000) / 1000);
    return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
}

// Modal Functions
function showHintModal() {
    hintModal.classList.add('active');
    document.body.style.overflow = 'hidden';
}

function closeHintModal() {
    hintModal.classList.remove('active');
    document.body.style.overflow = 'auto';
}

function confirmUseHint() {
    useHint();
}

function showSuccessModal() {
    successModal.classList.add('active');
    document.body.style.overflow = 'hidden';
    
    setTimeout(() => {
        closeSuccessModal();
    }, 3000);
}

function closeSuccessModal() {
    successModal.classList.remove('active');
    document.body.style.overflow = 'auto';
}

function showErrorModal(message) {
    const errorMessage = document.getElementById('errorMessage');
    if (errorMessage) {
        errorMessage.textContent = message;
    }
    
    errorModal.classList.add('active');
    document.body.style.overflow = 'hidden';
}

function closeErrorModal() {
    errorModal.classList.remove('active');
    document.body.style.overflow = 'auto';
}

function closeLivesOverlay() {
    livesOverlay.classList.remove('active');
}

// Code Editor Functions
function runCode() {
    const codeEditor = document.getElementById('codeEditor');
    const testResults = document.getElementById('testResults');
    
    if (!codeEditor || !testResults) return;
    
    const code = codeEditor.value;
    
    // Simple test runner for demo purposes
    // In a real app, this would use a proper code execution service
    const tests = [
        {
            name: 'Test 1: Basic functionality',
            passed: code.includes('userData?.data?.map') || code.includes('userData.data?.map'),
            message: 'Should use optional chaining or null check'
        },
        {
            name: 'Test 2: Fallback array',
            passed: code.includes('|| []') || code.includes('||[]'),
            message: 'Should provide fallback empty array'
        },
        {
            name: 'Test 3: No hardcoded "users" property',
            passed: !code.includes('.users.map'),
            message: 'Should not use hardcoded "users" property'
        }
    ];
    
    const passedTests = tests.filter(test => test.passed).length;
    const totalTests = tests.length;
    
    let resultsHTML = `
        <h4>Test Results: ${passedTests}/${totalTests} passed</h4>
        <div class="test-list">
    `;
    
    tests.forEach(test => {
        resultsHTML += `
            <div class="test-result ${test.passed ? 'passed' : 'failed'}">
                <i class="fas fa-${test.passed ? 'check' : 'times'}"></i>
                <span>${test.name}</span>
                <small>${test.message}</small>
            </div>
        `;
    });
    
    resultsHTML += '</div>';
    testResults.innerHTML = resultsHTML;
    
    if (passedTests === totalTests) {
        testResults.style.borderColor = 'var(--success)';
        showNotification('All tests passed! Your solution is correct.', 'success');
        awardXP(50);
    } else {
        testResults.style.borderColor = 'var(--danger)';
        showNotification(`${passedTests}/${totalTests} tests passed. Keep trying!`, 'error');
    }
}

function submitFix() {
    const codeEditor = document.getElementById('codeEditor');
    if (!codeEditor) return;
    
    const code = codeEditor.value;
    
    // Check if solution is correct
    const hasOptionalChaining = code.includes('userData?.data?.map');
    const hasFallback = code.includes('|| []') || code.includes('||[]');
    
    if (hasOptionalChaining && hasFallback) {
        showSuccessModal();
        awardXP(100);
        updateChapterProgress(25);
    } else {
        showErrorModal('Your solution needs optional chaining and a fallback array. Try again!');
    }
}

// Review Chapter
function reviewChapter() {
    // Reset to first scene
    document.querySelectorAll('.story-scene').forEach(scene => {
        scene.classList.remove('active');
    });
    
    gameState.currentScene = 1;
    document.getElementById('scene1').classList.add('active');
    updateSceneProgress();
    
    showNotification('Reviewing chapter from the beginning...', 'info');
}

// Watch Ad for Life
function watchAdForLife() {
    showNotification('Playing ad... Life will be added after ad completes', 'info');
    
    // Simulate ad completion after 3 seconds
    setTimeout(() => {
        gainLife();
        showNotification('Ad completed! You gained 1 life.', 'success');
    }, 3000);
}

// Buy Lives
function buyLives() {
    showNotification('Redirecting to coin purchase...', 'info');
    
    // In a real app, this would open a purchase modal
    setTimeout(() => {
        // Simulate purchase completion
        gameState.lives = 3;
        updateLivesDisplay();
        showNotification('Purchase successful! Lives restored to 3.', 'success');
    }, 2000);
}

// Update UI
function updateUI() {
    updateLivesDisplay();
    updateHintDisplay();
    updateSceneProgress();
}

// Notification System
function showNotification(message, type = 'info') {
    // Create notification element
    const notification = document.createElement('div');
    notification.className = `notification ${type}`;
    
    const icon = type === 'success' ? 'fa-check-circle' :
                 type === 'error' ? 'fa-times-circle' : 'fa-info-circle';
    
    notification.innerHTML = `
        <i class="fas ${icon}"></i>
        <span>${message}</span>
    `;
    
    // Add to page
    document.body.appendChild(notification);
    
    // Animate in
    setTimeout(() => {
        notification.classList.add('show');
    }, 10);
    
    // Remove after 3 seconds
    setTimeout(() => {
        notification.classList.remove('show');
        setTimeout(() => {
            notification.remove();
        }, 300);
    }, 3000);
}

// Add notification styles
const notificationStyles = document.createElement('style');
notificationStyles.textContent = `
    .notification {
        position: fixed;
        top: 100px;
        right: 20px;
        background: var(--card-light);
        color: var(--text-light);
        padding: 1rem 1.5rem;
        border-radius: var(--radius);
        box-shadow: var(--shadow-lg);
        display: flex;
        align-items: center;
        gap: 12px;
        z-index: 9999;
        transform: translateX(100%);
        opacity: 0;
        transition: transform 0.3s ease, opacity 0.3s ease;
        border-left: 4px solid var(--primary);
        min-width: 300px;
        max-width: 400px;
    }
    
    body.dark .notification {
        background: var(--card-dark);
        color: var(--text-dark);
    }
    
    .notification.success {
        border-left-color: var(--success);
    }
    
    .notification.error {
        border-left-color: var(--danger);
    }
    
    .notification.info {
        border-left-color: var(--info);
    }
    
    .notification.show {
        transform: translateX(0);
        opacity: 1;
    }
    
    .notification i {
        font-size: 1.25rem;
    }
    
    .notification.success i {
        color: var(--success);
    }
    
    .notification.error i {
        color: var(--danger);
    }
    
    .notification.info i {
        color: var(--info);
    }
    
    .notification span {
        flex: 1;
        font-weight: 500;
    }
`;
document.head.appendChild(notificationStyles);

// Save game state on page unload
window.addEventListener('beforeunload', () => {
    localStorage.setItem('taikenGameState', JSON.stringify(gameState));
});

// Load game state on page load
window.addEventListener('load', () => {
    const savedState = localStorage.getItem('taikenGameState');
    if (savedState) {
        const parsed = JSON.parse(savedState);
        // Merge saved state with default state
        gameState = { ...gameState, ...parsed };
        updateUI();
    }
});