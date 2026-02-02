"""
Onboarding Service - FIXED
Handles user onboarding with proper database integration
Uses: user_onboarding, user_skill_memory, ai_agent_sessions
"""
from typing import Dict, List, Optional
from config import get_settings
import google.generativeai as genai
import json
from supabase import create_client
from datetime import datetime

settings = get_settings()
genai.configure(api_key=settings.GEMINI_API_KEY)


class OnboardingService:
    """Handles user onboarding and initialization"""
    
    def __init__(self):
        self.client = create_client(settings.SUPABASE_URL, settings.SUPABASE_KEY)
    
    def process_onboarding(self, user_id: str, onboarding_data: Dict) -> Dict:
        """
        Process onboarding data and initialize user profile
        """
        print(f"[ONBOARDING] Processing onboarding for user: {user_id}")
        
        try:
            # Validate required fields
            required_fields = ['primary_career_goal', 'target_role', 'current_status', 
                             'time_availability', 'learning_preference']
            
            for field in required_fields:
                if field not in onboarding_data:
                    return {"success": False, "error": f"Missing required field: {field}"}
            
            # Prepare skills JSON (ensure it's valid)
            skills = onboarding_data.get('skills', [])
            if not isinstance(skills, list):
                skills = []
            
            # Save to user_onboarding table
            onboarding_record = {
                "user_id": user_id,
                "primary_career_goal": onboarding_data['primary_career_goal'],
                "target_role": onboarding_data['target_role'],
                "current_status": onboarding_data['current_status'],
                "skills": json.dumps(skills),  # Store as JSON string
                "time_availability": onboarding_data['time_availability'],
                "learning_preference": onboarding_data['learning_preference'],
                "short_term_goal": onboarding_data.get('short_term_goal'),
                "constraint_free_only": onboarding_data.get('constraint_free_only', False),
                "constraint_heavy_workload": onboarding_data.get('constraint_heavy_workload', False),
                "confidence_baseline": onboarding_data.get('confidence_baseline', 3)
            }
            
            # Upsert (insert or update)
            result = self.client.table('user_onboarding').upsert(onboarding_record).execute()
            
            if not result.data:
                return {"success": False, "error": "Failed to save onboarding data"}
            
            # Extract and initialize skills
            extracted_skills = self._extract_skills_from_goal(
                onboarding_data['primary_career_goal'],
                onboarding_data['target_role'],
                onboarding_data
            )
            
            # Initialize user_skill_memory for each skill
            for skill in extracted_skills:
                self._initialize_skill(user_id, skill)
            
            # Create initial AI agent session
            session = self._create_initial_session(user_id, onboarding_data)
            
            # Mark onboarding as complete in user_profiles
            self.client.table('user_profiles').update({
                'onboarding_complete': True,
                'updated_at': datetime.now().isoformat()
            }).eq('user_id', user_id).execute()
            
            # Generate welcome message
            welcome_message = self._generate_welcome_message(user_id, onboarding_data, extracted_skills)
            
            print(f"[ONBOARDING] ✅ Onboarding complete for {user_id}")
            
            return {
                "success": True,
                "session_id": session.get('id') if session else None,
                "initial_skills": extracted_skills,
                "welcome_message": welcome_message,
                "next_step": "skill_assessment"
            }
            
        except Exception as e:
            print(f"[ONBOARDING ERROR] {e}")
            return {"success": False, "error": str(e)}
    
    def _extract_skills_from_goal(self, career_goal: str, target_role: str, 
                                 onboarding_data: Dict) -> List[str]:
        """Extract skills from career goal using AI"""
        try:
            prompt = f"""
Extract 5-7 core technical skills for this career goal:

Career Goal: {career_goal}
Target Role: {target_role}
Current Status: {onboarding_data.get('current_status')}

Return ONLY a JSON array of skill names:
["Skill 1", "Skill 2", "Skill 3"]
"""
            
            model = genai.GenerativeModel('gemini-2.5-flash', 
                                        generation_config={"response_mime_type": "application/json"})
            response = model.generate_content(prompt)
            
            content = response.text.strip()
            skills = json.loads(content)
            
            if isinstance(skills, list) and len(skills) > 0:
                return skills[:7]
            
        except Exception as e:
            print(f"[ONBOARDING] Skill extraction failed: {e}")
        
        # Fallback to role-based skills
        return self._get_fallback_skills(target_role)
    
    def _get_fallback_skills(self, target_role: str) -> List[str]:
        """Get fallback skills based on role keywords"""
        role_lower = target_role.lower()
        
        skill_mappings = {
            'backend': ['Python', 'SQL', 'REST APIs', 'Git', 'Docker'],
            'frontend': ['JavaScript', 'React', 'CSS', 'HTML', 'TypeScript'],
            'fullstack': ['JavaScript', 'Python', 'React', 'Node.js', 'SQL'],
            'data': ['Python', 'SQL', 'Statistics', 'Data Analysis', 'Pandas'],
            'machine learning': ['Python', 'Machine Learning', 'Statistics', 'TensorFlow'],
            'devops': ['Docker', 'Kubernetes', 'AWS', 'CI/CD', 'Linux'],
            'mobile': ['Flutter', 'React Native', 'Swift', 'Kotlin'],
            'designer': ['Figma', 'UI/UX Design', 'Prototyping', 'User Research']
        }
        
        for keyword, skills in skill_mappings.items():
            if keyword in role_lower:
                return skills
        
        # Default
        return ['Communication', 'Problem Solving', 'Critical Thinking', 'Teamwork', 'Adaptability']
    
    def _initialize_skill(self, user_id: str, skill_name: str):
        """Initialize skill in user_skill_memory"""
        try:
            # Check if already exists
            existing = self.client.table('user_skill_memory').select('id').eq(
                'user_id', user_id
            ).eq('skill_name', skill_name).execute()
            
            if existing.data:
                return  # Already exists
            
            # Create new skill entry
            skill_data = {
                "user_id": user_id,
                "skill_name": skill_name,
                "confidence_score": 0.0,
                "practice_count": 0,
                "evidence": {
                    "source": "onboarding",
                    "initial": True
                }
            }
            
            self.client.table('user_skill_memory').insert(skill_data).execute()
            print(f"[ONBOARDING] Initialized skill: {skill_name}")
            
        except Exception as e:
            print(f"[ONBOARDING] Skill initialization failed: {e}")
    
    def _create_initial_session(self, user_id: str, onboarding_data: Dict) -> Optional[Dict]:
        """Create initial AI agent session"""
        try:
            session_data = {
                "user_id": user_id,
                "session_type": "career_guidance",
                "jd_text": onboarding_data['primary_career_goal'],
                "status": "active",
                "onboarding_id": user_id,
                "learning_preferences": {
                    "learning_preference": onboarding_data['learning_preference'],
                    "time_availability": onboarding_data['time_availability'],
                    "target_role": onboarding_data['target_role']
                }
            }
            
            result = self.client.table('ai_agent_sessions').insert(session_data).execute()
            
            if result.data:
                return result.data[0]
            
            return None
            
        except Exception as e:
            print(f"[ONBOARDING] Session creation failed: {e}")
            return None
    
    def _generate_welcome_message(self, user_id: str, onboarding_data: Dict, 
                                 skills: List[str]) -> Dict:
        """Generate personalized welcome message"""
        
        # Get username
        profile = self.client.table('user_profiles').select('username').eq(
            'user_id', user_id
        ).single().execute()
        
        username = profile.data.get('username', 'Learner') if profile.data else 'Learner'
        career_goal = onboarding_data.get('primary_career_goal', 'your goal')
        
        welcome_text = f"""
Welcome to PEARL, {username}!

I'm excited to help you become {career_goal}.

Based on your profile, I've identified {len(skills)} key skills to focus on:
{', '.join(skills[:3])}{"..." if len(skills) > 3 else ""}

Here's what's next:
1. **Skill Assessment**: Quick check on your current knowledge
2. **Personalized Roadmap**: Custom learning path for your goals
3. **First Learning Module**: Start with bite-sized content

Ready to begin? Let's take the first step together!
"""
        
        return {
            "title": "Welcome to Your Learning Journey!",
            "message": welcome_text,
            "cta_text": "Start Skill Assessment",
            "cta_action": "/assessment/start"
        }
    
    def get_onboarding_status(self, user_id: str) -> Dict:
        """Get user onboarding status"""
        try:
            # Check if onboarding exists
            onboarding = self.client.table('user_onboarding').select('*').eq(
                'user_id', user_id
            ).single().execute()
            
            if not onboarding.data:
                return {
                    "completed": False,
                    "step": 0,
                    "total_steps": 5,
                    "next_step": "basic_info"
                }
            
            # Check profile completion
            profile = self.client.table('user_profiles').select('onboarding_complete').eq(
                'user_id', user_id
            ).single().execute()
            
            completed = profile.data.get('onboarding_complete', False) if profile.data else False
            
            # Calculate step based on data completeness
            data = onboarding.data
            steps_completed = 0
            
            if data.get('primary_career_goal'):
                steps_completed += 1
            if data.get('target_role'):
                steps_completed += 1
            if data.get('skills'):
                steps_completed += 1
            if data.get('time_availability'):
                steps_completed += 1
            if data.get('learning_preference'):
                steps_completed += 1
            
            return {
                "completed": completed,
                "step": steps_completed,
                "total_steps": 5,
                "next_step": self._get_next_step(steps_completed),
                "onboarding_data": data
            }
            
        except Exception as e:
            print(f"[ONBOARDING] Get status failed: {e}")
            return {
                "completed": False,
                "step": 0,
                "total_steps": 5,
                "next_step": "basic_info"
            }
    
    def _get_next_step(self, current_step: int) -> str:
        """Get next onboarding step"""
        steps = [
            "basic_info",
            "career_goal",
            "skills_assessment",
            "preferences",
            "confirmation"
        ]
        return steps[current_step] if current_step < len(steps) else "complete"


# Global instance
onboarding_service = OnboardingService()