"""
PEARL Agent - FIXED with Database Persistence
Saves all progress to: ai_module_progress, ai_action_completions, ai_checkpoint_results
"""

from typing import List, Dict, Optional
import google.generativeai as genai
from config import get_settings
from supabase import create_client
import json
from datetime import datetime

settings = get_settings()
genai.configure(api_key=settings.GEMINI_API_KEY)


class PEARLAgent:
    """Main orchestrator with database persistence"""
    
    def __init__(self):
        self.client = create_client(settings.SUPABASE_URL, settings.SUPABASE_KEY)
    
    def create_learning_path(self, user_id: str, session_id: str, skill: str, current_confidence: float = 0.0) -> Dict:
        """Create complete learning path and save to database"""
        print(f"[PEARL] Creating path for: {skill}")
        
        difficulty = "beginner" if current_confidence < 0.3 else "intermediate" if current_confidence < 0.7 else "advanced"
        
        # Step 1: Decompose skill into modules
        decomposition = self._decompose_skill(skill, difficulty)
        
        if not decomposition or 'modules' not in decomposition:
            return {"error": "Failed to decompose skill"}
        
        # Step 2: Save modules to database
        saved_modules = []
        for module in decomposition['modules']:
            # Generate actions for this module
            actions = self._generate_actions(module, skill)
            
            # Save module to ai_module_progress
            module_data = {
                "user_id": user_id,
                "session_id": session_id,
                "skill": skill,
                "module_id": module['module_id'],
                "module_name": module['name'],
                "status": 'active' if module['module_id'] == 1 else 'locked',
                "actions_completed": 0,
                "total_actions": len(actions.get('actions', [])),
                "cached_completion_data": {
                    "module": module,
                    "actions": actions.get('actions', [])
                }
            }
            
            result = self.client.table('ai_module_progress').insert(module_data).execute()
            
            if result.data:
                saved_modules.append(result.data[0])
        
        learning_path = {
            "skill": skill,
            "difficulty": difficulty,
            "total_modules": len(saved_modules),
            "estimated_hours": decomposition.get('estimated_hours', 0),
            "current_module": 1,
            "modules": saved_modules,
            "session_id": session_id
        }
        
        print(f"[PEARL] ✅ Path created and saved: {len(saved_modules)} modules")
        return learning_path
    
    def _decompose_skill(self, skill: str, difficulty: str) -> Dict:
        """Decompose skill into modules using Gemini"""
        prompt = f"""
Break down "{skill}" into 4-6 learning modules.

Each module must be:
- Specific and actionable
- Completable in 2-4 hours
- Progressive difficulty
- Clear completion criteria

Difficulty: {difficulty}

Return ONLY valid JSON:
{{
    "skill": "{skill}",
    "total_modules": 5,
    "estimated_hours": 15,
    "modules": [
        {{
            "module_id": 1,
            "name": "Module name",
            "description": "What you'll learn",
            "prerequisites": [],
            "estimated_hours": 3,
            "difficulty": "{difficulty}",
            "learning_objectives": ["obj1", "obj2"],
            "completion_criteria": "How to prove mastery"
        }}
    ]
}}
"""
        
        try:
            model = genai.GenerativeModel(
                'gemini-2.5-flash',
                generation_config={
                    "temperature": 0.3,
                    "response_mime_type": "application/json"
                }
            )
            
            response = model.generate_content(prompt)
            parsed = json.loads(response.text)
            
            if 'modules' in parsed and len(parsed['modules']) >= 4:
                return parsed
            
        except Exception as e:
            print(f"[PEARL ERROR] Decomposition failed: {e}")
        
        # Fallback
        return {
            "skill": skill,
            "total_modules": 4,
            "estimated_hours": 12,
            "modules": [
                {
                    "module_id": i,
                    "name": f"{skill} - Part {i}",
                    "description": f"Learn {skill} fundamentals",
                    "prerequisites": [i-1] if i > 1 else [],
                    "estimated_hours": 3,
                    "difficulty": difficulty,
                    "learning_objectives": [f"Master {skill} basics"],
                    "completion_criteria": "Complete all exercises"
                }
                for i in range(1, 5)
            ]
        }
    
    def _generate_actions(self, module: Dict, skill: str) -> Dict:
        """Generate 4 learning actions for a module"""
        prompt = f"""
Generate 4 learning actions for:
Skill: {skill}
Module: {module['name']}
Objectives: {', '.join(module['learning_objectives'])}

Return JSON:
{{
    "module_id": {module['module_id']},
    "actions": [
        {{"type": "byte", "title": "Video title", "description": "Details", "platform": "YouTube", "url": "https://...", "duration_minutes": 3}},
        {{"type": "course", "title": "Course title", "description": "Details", "platform": "freeCodeCamp", "url": "https://...", "duration_minutes": 45}},
        {{"type": "taiken", "title": "Project title", "description": "What to build", "platform": "Replit", "url": "https://...", "duration_minutes": 60}},
        {{"type": "checkpoint", "title": "Assessment", "description": "Test knowledge", "platform": "PEARL", "questions": []}}
    ]
}}
"""
        
        try:
            model = genai.GenerativeModel('gemini-2.5-flash', generation_config={"temperature": 0.5, "response_mime_type": "application/json"})
            response = model.generate_content(prompt)
            parsed = json.loads(response.text)
            
            # Generate checkpoint questions
            for action in parsed.get('actions', []):
                if action.get('type') == 'checkpoint':
                    action['questions'] = self._generate_checkpoint_questions(skill, module)
                    action['pass_threshold'] = 70
                    action['completed'] = False
            
            return parsed
            
        except Exception as e:
            print(f"[PEARL ERROR] Action generation failed: {e}")
            return {"module_id": module['module_id'], "actions": []}
    
    def _generate_checkpoint_questions(self, skill: str, module: Dict) -> List[Dict]:
        """Generate checkpoint questions"""
        prompt = f"""
Generate 4 multiple-choice questions for {skill} - {module['name']}.

Return JSON array:
[
    {{
        "question": "Question text?",
        "options": ["Correct answer", "Wrong 1", "Wrong 2", "Wrong 3"],
        "correct_index": 0,
        "explanation": "Why this is correct"
    }}
]
"""
        
        try:
            model = genai.GenerativeModel('gemini-2.5-flash', generation_config={"temperature": 0.7, "response_mime_type": "application/json"})
            response = model.generate_content(prompt)
            questions = json.loads(response.text)
            
            if isinstance(questions, list) and len(questions) >= 4:
                return questions[:4]
        except Exception as e:
            print(f"[PEARL ERROR] Question generation failed: {e}")
        
        # Fallback
        return [
            {
                "question": f"What is a key concept in {skill}?",
                "options": ["Understanding fundamentals", "Ignoring best practices", "Avoiding learning", "Skipping practice"],
                "correct_index": 0,
                "explanation": f"{skill} requires understanding core concepts."
            }
        ] * 4
    
    def get_next_action(self, user_id: str, session_id: str) -> Optional[Dict]:
        """Get next incomplete action from database"""
        try:
            # Get active module
            active_module = self.client.table('ai_module_progress').select('*').eq(
                'user_id', user_id
            ).eq('session_id', session_id).eq('status', 'active').single().execute()
            
            if not active_module.data:
                return None
            
            module = active_module.data
            cached_data = module.get('cached_completion_data', {})
            actions = cached_data.get('actions', [])
            
            # Find first incomplete action
            for idx, action in enumerate(actions):
                if not action.get('completed', False):
                    return {
                        "module_id": module['module_id'],
                        "module_name": module['module_name'],
                        "action_index": idx,
                        "action": action,
                        "progress_id": module['id']
                    }
            
            return None
            
        except Exception as e:
            print(f"[PEARL ERROR] Get next action failed: {e}")
            return None
    
    def complete_action(self, progress_id: str, action_index: int, completion_data: Optional[Dict] = None) -> Dict:
        """Mark action as complete and save to database"""
        try:
            # Get module progress
            module = self.client.table('ai_module_progress').select('*').eq('id', progress_id).single().execute()
            
            if not module.data:
                return {"success": False, "error": "Module not found"}
            
            # Update cached data
            cached_data = module.data.get('cached_completion_data', {})
            actions = cached_data.get('actions', [])
            
            if action_index < len(actions):
                actions[action_index]['completed'] = True
                actions[action_index]['completed_at'] = datetime.now().isoformat()
            
            cached_data['actions'] = actions
            
            # Save action completion
            action_completion = {
                "module_progress_id": progress_id,
                "action_index": action_index,
                "action_type": actions[action_index].get('type') if action_index < len(actions) else 'unknown',
                "completion_data": completion_data or {}
            }
            self.client.table('ai_action_completions').insert(action_completion).execute()
            
            # Update module progress
            actions_completed = module.data.get('actions_completed', 0) + 1
            total_actions = module.data.get('total_actions', 4)
            
            update_data = {
                "actions_completed": actions_completed,
                "cached_completion_data": cached_data,
                "last_cache_update": datetime.now().isoformat()
            }
            
            # Check if module complete
            if actions_completed >= total_actions:
                update_data['status'] = 'completed'
                update_data['completed_at'] = datetime.now().isoformat()
            
            self.client.table('ai_module_progress').update(update_data).eq('id', progress_id).execute()
            
            # If module complete, unlock next
            if actions_completed >= total_actions:
                self._unlock_next_module(module.data['user_id'], module.data['session_id'], module.data['module_id'])
            
            return {
                "success": True,
                "actions_completed": actions_completed,
                "module_complete": actions_completed >= total_actions
            }
            
        except Exception as e:
            print(f"[PEARL ERROR] Complete action failed: {e}")
            return {"success": False, "error": str(e)}
    
    def _unlock_next_module(self, user_id: str, session_id: str, current_module_id: int):
        """Unlock next module when current is complete"""
        try:
            # Find next module
            next_module = self.client.table('ai_module_progress').select('*').eq(
                'user_id', user_id
            ).eq('session_id', session_id).eq('module_id', current_module_id + 1).single().execute()
            
            if next_module.data:
                self.client.table('ai_module_progress').update({
                    'status': 'active',
                    'started_at': datetime.now().isoformat()
                }).eq('id', next_module.data['id']).execute()
                
                print(f"[PEARL] ✅ Unlocked module {current_module_id + 1}")
                
        except Exception as e:
            print(f"[PEARL] No next module to unlock: {e}")
    
    def submit_checkpoint(self, progress_id: str, user_id: str, answers: List[int]) -> Dict:
        """Submit checkpoint answers and evaluate"""
        try:
            # Get module
            module = self.client.table('ai_module_progress').select('*').eq('id', progress_id).single().execute()
            
            if not module.data:
                return {"success": False, "error": "Module not found"}
            
            # Get checkpoint questions
            cached_data = module.data.get('cached_completion_data', {})
            actions = cached_data.get('actions', [])
            
            checkpoint = next((a for a in actions if a.get('type') == 'checkpoint'), None)
            
            if not checkpoint:
                return {"success": False, "error": "Checkpoint not found"}
            
            questions = checkpoint.get('questions', [])
            
            # Evaluate
            correct_count = 0
            feedback_items = []
            
            for i, (question, answer) in enumerate(zip(questions, answers)):
                correct_idx = question.get('correct_index', 0)
                is_correct = answer == correct_idx
                
                if is_correct:
                    correct_count += 1
                
                feedback_items.append({
                    "question_num": i + 1,
                    "status": "correct" if is_correct else "incorrect",
                    "explanation": question.get('explanation', '')
                })
            
            score = (correct_count / len(questions)) * 100 if questions else 0
            passed = score >= checkpoint.get('pass_threshold', 70)
            
            # Save result
            result = {
                "module_progress_id": progress_id,
                "user_id": user_id,
                "questions": questions,
                "answers": answers,
                "score": score,
                "passed": passed
            }
            self.client.table('ai_checkpoint_results').insert(result).execute()
            
            return {
                "success": True,
                "passed": passed,
                "score": score,
                "correct_count": correct_count,
                "total_questions": len(questions),
                "feedback_items": feedback_items
            }
            
        except Exception as e:
            print(f"[PEARL ERROR] Checkpoint submission failed: {e}")
            return {"success": False, "error": str(e)}
    
    def get_user_progress(self, user_id: str, session_id: str) -> Dict:
        """Get user's complete learning progress"""
        try:
            modules = self.client.table('ai_module_progress').select('*').eq(
                'user_id', user_id
            ).eq('session_id', session_id).order('module_id').execute()
            
            total_modules = len(modules.data or [])
            completed_modules = len([m for m in (modules.data or []) if m.get('status') == 'completed'])
            
            return {
                "total_modules": total_modules,
                "completed_modules": completed_modules,
                "progress_percentage": (completed_modules / total_modules * 100) if total_modules > 0 else 0,
                "modules": modules.data or []
            }
            
        except Exception as e:
            print(f"[PEARL ERROR] Get progress failed: {e}")
            return {}


# Global instance
pearl = PEARLAgent()