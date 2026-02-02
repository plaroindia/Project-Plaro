"""
FIXED PEARL Routes - Proper Error Handling and Service Integration
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Dict
from database import EnhancedSupabaseHelper
from services.enhanced_rag_service import enhanced_rag
from config import get_settings
import json
import google.generativeai as genai
from datetime import datetime
import traceback

# Import new services
try:
    from services.learning_optimizer_agent import learning_optimizer
    OPTIMIZER_AVAILABLE = True
except Exception as e:
    print(f"[WARNING] Learning optimizer not available: {e}")
    OPTIMIZER_AVAILABLE = False

try:
    from services.job_retrieval_service import adzuna_service
    ADZUNA_AVAILABLE = True
except Exception as e:
    print(f"[WARNING] Adzuna service not available: {e}")
    ADZUNA_AVAILABLE = False

try:
    from services.content_provider_service import content_provider
    CONTENT_PROVIDER_AVAILABLE = True
except Exception as e:
    print(f"[WARNING] Content provider not available: {e}")
    CONTENT_PROVIDER_AVAILABLE = False

router = APIRouter()
db = EnhancedSupabaseHelper()
settings = get_settings()

# Configure Gemini
genai.configure(api_key=settings.GEMINI_API_KEY)

# Import the pearl agent
from services.pearl_agent import pearl


# ============================================
# REQUEST MODELS
# ============================================

class CareerGoalRequest(BaseModel):
    goal: str
    user_id: str = settings.DEMO_USER_ID
    jd_text: Optional[str] = None


class ModuleActionRequest(BaseModel):
    session_id: str
    skill: str
    module_id: int
    action_index: int
    completion_data: dict
    user_id: str = settings.DEMO_USER_ID


class CheckpointSubmission(BaseModel):
    session_id: str
    skill: str
    module_id: int
    answers: List[int]
    user_id: str = settings.DEMO_USER_ID


# ============================================
# DATABASE HELPER
# ============================================

class PEARLDatabaseHelper:
    """Database persistence"""
    
    @staticmethod
    def save_learning_paths(session_id: str, user_id: str, learning_paths: Dict) -> bool:
        try:
            db.client.table('ai_agent_sessions').update({
                'jd_parsed': {
                    'learning_paths': learning_paths,
                    'updated_at': datetime.now().isoformat()
                }
            }).eq('id', session_id).execute()
            return True
        except Exception as e:
            print(f"[ERROR] Save learning paths failed: {e}")
            return False
    
    @staticmethod
    def save_module_progress(session_id: str, user_id: str, skill: str, module_id: int, module_data: Dict) -> Optional[str]:
        try:
            existing = db.client.table('ai_module_progress').select('id').eq(
                'session_id', session_id
            ).eq('skill', skill).eq('module_id', module_id).execute()
            
            progress_data = {
                'session_id': session_id,
                'user_id': user_id,
                'skill': skill,
                'module_id': module_id,
                'module_name': module_data.get('name', f'{skill} - Module {module_id}'),
                'status': module_data.get('status', 'locked'),
                'total_actions': len(module_data.get('actions', [])),
                'actions_completed': sum(1 for a in module_data.get('actions', []) if a.get('completed')),
                'started_at': datetime.now().isoformat() if module_data.get('status') == 'active' else None,
                'completed_at': datetime.now().isoformat() if module_data.get('status') == 'completed' else None
            }
            
            if existing.data:
                result = db.client.table('ai_module_progress').update(progress_data).eq(
                    'id', existing.data[0]['id']
                ).execute()
            else:
                result = db.client.table('ai_module_progress').insert(progress_data).execute()
            
            return result.data[0]['id'] if result.data else None
        except Exception as e:
            print(f"[ERROR] Save module progress failed: {e}")
            return None


# ============================================
# SKILL EXTRACTION
# ============================================

async def extract_skills_from_goal(goal: str) -> List[str]:
    """
    Extract skills from any career goal using Gemini
    Works for tech AND non-tech careers
    """
    
    prompt = f"""
Analyze this career goal and extract 3-5 specific technical skills needed.

Career Goal: "{goal}"

Return a JSON array of skill names. Be specific and relevant.

Examples:
- "Become a Backend Developer" → ["Python", "SQL", "REST APIs", "Git"]
- "Become a Singer" → ["Vocal Technique", "Music Theory", "Performance Skills", "Recording Basics"]
- "Data Scientist" → ["Python", "Statistics", "Machine Learning", "Data Visualization"]
- "Game Developer" → ["C++", "Game Engines", "3D Graphics", "Physics Simulation"]

Return only the JSON array, nothing else:
["skill1", "skill2", "skill3"]
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
        skills = json.loads(response.text)
        
        if isinstance(skills, list) and len(skills) > 0:
            print(f"[SUCCESS] Extracted skills for '{goal}': {skills}")
            return skills
        
        print(f"[WARNING] Invalid skill format, using intelligent fallback")
        
    except Exception as e:
        print(f"[ERROR] Skill extraction failed: {e}")
    
    # INTELLIGENT fallback based on goal keywords
    goal_lower = goal.lower()
    
    # Skill mapping for common careers
    skill_mappings = {
        "singer": ["Vocal Technique", "Music Theory", "Performance Skills"],
        "musician": ["Music Theory", "Instrument Mastery", "Composition"],
        "backend": ["Python", "SQL", "REST APIs"],
        "frontend": ["JavaScript", "React", "CSS"],
        "data": ["Python", "SQL", "Statistics"],
        "mobile": ["Flutter", "React Native", "Mobile UI"],
        "ml": ["Python", "Machine Learning", "Data Analysis"],
        "machine learning": ["Python", "Machine Learning", "Statistics"],
        "devops": ["Docker", "Kubernetes", "CI/CD"],
        "game": ["Unity", "C++", "Game Design"],
        "designer": ["Figma", "UI/UX Design", "Prototyping"],
        "writer": ["Writing Skills", "Storytelling", "Editing"],
        "photographer": ["Photography", "Lighting", "Photo Editing"],
        "artist": ["Drawing", "Color Theory", "Digital Art"]
    }
    
    for keyword, skills in skill_mappings.items():
        if keyword in goal_lower:
            print(f"[FALLBACK] Matched '{keyword}' → {skills}")
            return skills
    
    # Last resort: generic soft skills
    print(f"[FALLBACK] No match, using generic skills")
    return ["Communication", "Problem Solving", "Critical Thinking"]


# ============================================
# ENDPOINT 1: START JOURNEY (FIXED!)
# ============================================

@router.post("/start-journey")
async def start_career_journey(req: CareerGoalRequest):
    """
    Start learning journey - NOW WORKS FOR ANY GOAL!
    """
    try:
        print(f"\n[PEARL] ========== Starting journey ==========")
        print(f"[PEARL] Goal: '{req.goal}'")
        print(f"[PEARL] User ID: {req.user_id}")
        
        # Step 1: Create session
        print(f"[PEARL] Creating session...")
        session = db.create_agent_session(
            user_id=req.user_id, 
            jd_text=req.jd_text or req.goal
        )
        
        if not session or 'id' not in session:
            raise HTTPException(
                status_code=500, 
                detail="Failed to create session - check database connection"
            )
        
        session_id = session['id']
        print(f"[PEARL] ✅ Session created: {session_id}")
        
        # Step 2: Extract skills
        print(f"[PEARL] Extracting skills from goal...")
        required_skills = await extract_skills_from_goal(req.goal)
        target_role = req.goal
        
        print(f"[PEARL] ✅ Skills identified: {required_skills}")
        
        # Step 3: Get user's current skill levels
        print(f"[PEARL] Fetching user skill levels...")
        try:
            user_skills = db.get_user_skills(req.user_id)
            skill_dict = {s['skill_name']: float(s['confidence_score']) for s in user_skills}
            print(f"[PEARL] ✅ User has {len(skill_dict)} existing skills")
        except Exception as e:
            print(f"[PEARL] ⚠️  No existing skills found: {e}")
            skill_dict = {skill: 0.0 for skill in required_skills}
        
        # Step 4: Create learning paths
        print(f"[PEARL] Creating learning paths...")
        learning_paths = {}
        
        for skill in required_skills[:3]:  # Top 3 skills to avoid overload
            current_conf = skill_dict.get(skill, 0.0)
            
            print(f"[PEARL] Creating path for '{skill}' (current: {current_conf})")
            
            try:
                # Use pearl agent to create structured learning path
                path = pearl.create_learning_path(skill, current_conf)
                
                # Enhance with real resources from RAG
                print(f"[PEARL] Enhancing with real resources...")
                for module in path['modules']:
                    for action in module['actions']:
                        if action['type'] in ['byte', 'course', 'taiken']:
                            try:
                                real_resources = enhanced_rag.retrieve_resources(
                                    skill, action['type'], count=1
                                )
                                if real_resources:
                                    action['external_resource'] = real_resources[0]
                            except Exception as e:
                                print(f"[PEARL] ⚠️  Resource retrieval failed: {e}")
                
                learning_paths[skill] = path
                print(f"[PEARL] ✅ Path created for '{skill}' with {len(path['modules'])} modules")
                
                # Save to database
                for module in path['modules']:
                    try:
                        PEARLDatabaseHelper.save_module_progress(
                            session_id, req.user_id, skill, module['module_id'], module
                        )
                    except Exception as e:
                        print(f"[PEARL] ⚠️  Module save failed: {e}")
                
            except Exception as e:
                print(f"[PEARL] ❌ Failed to create path for '{skill}': {e}")
                # Continue with other skills
                continue
        
        # Step 5: Save complete paths to session
        print(f"[PEARL] Saving learning paths to session...")
        PEARLDatabaseHelper.save_learning_paths(session_id, req.user_id, learning_paths)
        
        # Step 6: Build response
        print(f"[PEARL] ========== Journey created successfully! ==========")
        print(f"[PEARL] Session: {session_id}")
        print(f"[PEARL] Skills: {list(learning_paths.keys())}")
        print(f"[PEARL] Modules: {sum(len(p['modules']) for p in learning_paths.values())}")
        
        response = {
            "success": True,
            "session_id": session_id,
            "target_role": target_role,
            "skills_to_learn": list(learning_paths.keys()),
            "learning_paths": learning_paths,
            "total_modules": sum(len(p['modules']) for p in learning_paths.values()),
            "estimated_hours": sum(p.get('estimated_hours', 0) for p in learning_paths.values()),
            "next_action": None
        }
        
        # Get next action if paths exist
        if learning_paths:
            first_skill = list(learning_paths.keys())[0]
            response["next_action"] = pearl.get_next_action(learning_paths[first_skill])
        
        return response
    
    except HTTPException:
        raise
    except Exception as e:
        print(f"[PEARL] ❌ Journey failed with error: {e}")
        print(traceback.format_exc())
        raise HTTPException(
            status_code=500, 
            detail={
                "error": str(e),
                "type": type(e).__name__,
                "traceback": traceback.format_exc()
            }
        )


# ============================================
# ENDPOINT 2: UNLOCK MODULE
# ============================================

@router.post("/unlock-module")
async def unlock_module(req: ModuleActionRequest):
    """Unlock a specific module"""
    try:
        print(f"[PEARL] Unlocking module {req.module_id} for skill: {req.skill}")
        
        # Get session
        session = db.client.table('ai_agent_sessions').select('*').eq(
            'id', req.session_id
        ).single().execute()
        
        if not session.data:
            raise HTTPException(status_code=404, detail="Session not found")
        
        learning_paths = session.data.get('jd_parsed', {}).get('learning_paths', {})
        
        if req.skill not in learning_paths:
            raise HTTPException(status_code=404, detail=f"Skill {req.skill} not found")
        
        path = learning_paths[req.skill]
        
        # Find and unlock module
        for module in path['modules']:
            if module['module_id'] == req.module_id:
                module['status'] = 'active'
                
                # Save to database
                PEARLDatabaseHelper.save_module_progress(
                    req.session_id, req.user_id, req.skill, req.module_id, module
                )
                
                # Update session
                db.client.table('ai_agent_sessions').update({
                    'jd_parsed': {
                        'learning_paths': learning_paths,
                        'updated_at': datetime.now().isoformat()
                    }
                }).eq('id', req.session_id).execute()
                
                return {
                    "success": True,
                    "message": f"Module {req.module_id} unlocked",
                    "module": module
                }
        
        raise HTTPException(status_code=404, detail="Module not found")
    
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Unlock module failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================
# ENDPOINT 3: COMPLETE ACTION
# ============================================

@router.post("/complete-action")
async def complete_action(req: ModuleActionRequest):
    """Mark an action as complete"""
    try:
        print(f"[PEARL] Completing action {req.action_index} in module {req.module_id}")
        
        # Get session
        session = db.client.table('ai_agent_sessions').select('*').eq(
            'id', req.session_id
        ).single().execute()
        
        if not session.data:
            raise HTTPException(status_code=404, detail="Session not found")
        
        learning_paths = session.data.get('jd_parsed', {}).get('learning_paths', {})
        
        if req.skill not in learning_paths:
            raise HTTPException(status_code=404, detail=f"Skill {req.skill} not found")
        
        path = learning_paths[req.skill]
        
        # Mark action complete
        result = pearl.advance_progress(path, req.module_id, req.action_index)
        
        # Update in database
        PEARLDatabaseHelper.save_learning_paths(req.session_id, req.user_id, learning_paths)
        
        # Award points if configured
        try:
            from services.gamification_service import gamification_service
            db.award_plaro_points(
                user_id=req.user_id,
                source='module_action_completed',
                points=10,
                related_content_type='module',
                related_content_id=str(req.module_id),
                reason=f'Completed action in {req.skill} module {req.module_id}'
            )
        except Exception as e:
            print(f"[WARNING] Points award failed: {e}")
        
        return {
            "success": True,
            "result": result,
            "next_action": pearl.get_next_action(path)
        }
    
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Complete action failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================
# ENDPOINT 4: SUBMIT CHECKPOINT
# ============================================

@router.post("/submit-checkpoint")
async def submit_checkpoint(req: CheckpointSubmission):
    """Submit checkpoint answers"""
    try:
        print(f"[PEARL] Submitting checkpoint for module {req.module_id}")
        
        # Get session
        session = db.client.table('ai_agent_sessions').select('*').eq(
            'id', req.session_id
        ).single().execute()
        
        if not session.data:
            raise HTTPException(status_code=404, detail="Session not found")
        
        learning_paths = session.data.get('jd_parsed', {}).get('learning_paths', {})
        
        if req.skill not in learning_paths:
            raise HTTPException(status_code=404, detail=f"Skill {req.skill} not found")
        
        path = learning_paths[req.skill]
        
        # Find checkpoint
        checkpoint_data = None
        for module in path['modules']:
            if module['module_id'] == req.module_id:
                for action in module['actions']:
                    if action['type'] == 'checkpoint':
                        checkpoint_data = action
                        break
        
        if not checkpoint_data:
            raise HTTPException(status_code=404, detail="Checkpoint not found")
        
        # Evaluate answers
        result = pearl.checkpoint.evaluate_checkpoint(checkpoint_data, req.answers)
        
        # Save result
        db.client.table('ai_checkpoint_results').insert({
            'module_progress_id': None,  # Would need to fetch this
            'user_id': req.user_id,
            'questions': checkpoint_data.get('questions', []),
            'answers': req.answers,
            'score': result['score'],
            'passed': result['passed'],
            'submitted_at': datetime.now().isoformat()
        }).execute()
        
        # Award points if passed
        if result['passed']:
            try:
                db.award_plaro_points(
                    user_id=req.user_id,
                    source='checkpoint_passed',
                    points=50,
                    related_content_type='checkpoint',
                    related_content_id=str(req.module_id),
                    reason=f'Passed checkpoint for {req.skill} module {req.module_id}'
                )
            except Exception as e:
                print(f"[WARNING] Points award failed: {e}")
        
        return {
            "success": True,
            "result": result
        }
    
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Submit checkpoint failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================
# HELPER ENDPOINTS
# ============================================

@router.get("/session/{session_id}")
async def get_session(session_id: str):
    """Get session details"""
    try:
        session = db.client.table('ai_agent_sessions').select('*').eq(
            'id', session_id
        ).single().execute()
        
        if not session.data:
            raise HTTPException(status_code=404, detail="Session not found")
        
        return session.data
    
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))