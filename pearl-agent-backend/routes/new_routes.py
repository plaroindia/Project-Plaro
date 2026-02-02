"""
Fixed New Routes with Comprehensive Error Handling
"""
from fastapi import APIRouter, HTTPException, Depends, Header
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import Optional, Dict, List
from datetime import datetime
import traceback

router = APIRouter()

# Import services with error handling
try:
    from database import EnhancedSupabaseHelper
    db = EnhancedSupabaseHelper()
except Exception as e:
    print(f"[ERROR] Failed to import database: {e}")
    db = None

try:
    from services.onboarding_service import onboarding_service
except Exception as e:
    print(f"[ERROR] Failed to import onboarding service: {e}")
    onboarding_service = None

try:
    from services.gamification_service import gamification_service
except Exception as e:
    print(f"[ERROR] Failed to import gamification service: {e}")
    gamification_service = None

try:
    from services.resume_service import resume_service
except Exception as e:
    print(f"[ERROR] Failed to import resume service: {e}")
    resume_service = None

try:
    from config import get_settings
    settings = get_settings()
except Exception as e:
    print(f"[ERROR] Failed to import settings: {e}")
    settings = None


# ========== PYDANTIC MODELS ==========

class OnboardingRequest(BaseModel):
    primary_career_goal: str
    target_role: str
    current_status: str = "student"
    skills: List[str] = []
    time_availability: str = "5-10 hours/week"
    learning_preference: str = "mixed"
    short_term_goal: Optional[str] = None
    constraint_free_only: bool = False
    constraint_heavy_workload: bool = False
    confidence_baseline: Optional[int] = None


class ContentRecommendationRequest(BaseModel):
    skill: str
    content_type: Optional[str] = None
    difficulty: Optional[str] = None


# ========== HELPER FUNCTIONS ==========

def get_user_from_token(authorization: str):
    """Extract user from authorization header"""
    try:
        if not authorization:
            raise HTTPException(status_code=401, detail="No authorization header")
        
        if not db:
            raise HTTPException(status_code=500, detail="Database not available")
        
        token = authorization.replace("Bearer ", "") if authorization.startswith("Bearer ") else authorization
        user_response = db.client.auth.get_user(token)
        
        if not user_response or not user_response.user:
            raise HTTPException(status_code=401, detail="Invalid token")
        
        return user_response.user
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Token validation failed: {e}")
        raise HTTPException(status_code=401, detail=f"Authentication failed: {str(e)}")


# ========== ONBOARDING ROUTES ==========

@router.post("/onboarding/start")
async def start_onboarding(request: OnboardingRequest, authorization: str = Header(None)):
    """Start user onboarding"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        if not onboarding_service:
            raise HTTPException(status_code=503, detail="Onboarding service unavailable")
        
        result = onboarding_service.process_onboarding(user_id, request.dict())
        
        if not result.get("success"):
            raise HTTPException(status_code=400, detail=result.get("error", "Onboarding failed"))
        
        # Ensure user_id is included in response
        result["user_id"] = user_id
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Onboarding start failed: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


@router.get("/onboarding/status")
async def get_onboarding_status(authorization: str = Header(None)):
    """Get user onboarding status with graceful fallback"""
    try:
        # If no auth, return default status
        if not authorization:
            return {
                "success": False,
                "onboarding": {
                    "completed": False,
                    "step": 0,
                    "total_steps": 5
                }
            }
        
        # Try to get user
        try:
            user = get_user_from_token(authorization)
            user_id = user.id
        except:
            return {
                "success": False,
                "onboarding": {
                    "completed": False,
                    "step": 0,
                    "total_steps": 5
                }
            }
        
        # Try to get onboarding status
        if not onboarding_service:
            return {
                "success": False,
                "onboarding": {
                    "completed": False,
                    "step": 0,
                    "total_steps": 5,
                    "error": "Onboarding service unavailable"
                }
            }
        
        try:
            status = onboarding_service.get_onboarding_status(user_id)
            return {
                "success": True,
                "onboarding": status
            }
        except Exception as service_err:
            print(f"[ERROR] Onboarding service error: {service_err}")
            return {
                "success": False,
                "onboarding": {
                    "completed": False,
                    "step": 0,
                    "total_steps": 5,
                    "error": str(service_err)
                }
            }
        
    except Exception as e:
        print(f"[ERROR] Onboarding status error: {e}")
        return {
            "success": False,
            "onboarding": {
                "completed": False,
                "step": 0,
                "total_steps": 5,
                "error": str(e)
            }
        }


# ========== GAMIFICATION ROUTES ==========

@router.get("/gamification/summary")
async def get_gamification_summary(authorization: str = Header(None)):
    """Get user gamification summary"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        if not gamification_service:
            # Return default summary
            return {
                "success": False,
                "summary": {
                    "points_summary": {"total_points": 0, "rank_level": "beginner"},
                    "streak": 0,
                    "recent_achievements": []
                },
                "error": "Gamification service unavailable"
            }
        
        summary = gamification_service.get_user_gamification_summary(user_id)
        
        return {
            "success": True,
            "summary": summary
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Gamification summary error: {e}")
        traceback.print_exc()
        return {
            "success": False,
            "summary": {
                "points_summary": {"total_points": 0, "rank_level": "beginner"},
                "streak": 0,
                "recent_achievements": []
            },
            "error": str(e)
        }


@router.get("/gamification/leaderboard")
async def get_leaderboard(limit: int = 20):
    """Get leaderboard"""
    try:
        if not gamification_service:
            return {
                "success": False,
                "leaderboard": [],
                "error": "Gamification service unavailable"
            }
        
        leaderboard = gamification_service.get_leaderboard(limit)
        
        return {
            "success": True,
            "leaderboard": leaderboard
        }
        
    except Exception as e:
        print(f"[ERROR] Leaderboard error: {e}")
        traceback.print_exc()
        return {
            "success": False,
            "leaderboard": [],
            "error": str(e)
        }


@router.post("/gamification/daily-rewards")
async def claim_daily_rewards(authorization: str = Header(None)):
    """Claim daily rewards - one per day only"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        if not gamification_service:
            raise HTTPException(status_code=503, detail="Gamification service unavailable")
        
        # Check if user already claimed today
        from datetime import datetime, timedelta
        profile = db.get_user_profile(user_id)
        
        if profile:
            last_reward = profile.get('last_reward_date')
            if last_reward:
                last_reward_date = datetime.fromisoformat(last_reward.replace('Z', '+00:00')).date()
                today = datetime.now().date()
                
                if last_reward_date == today:
                    return {
                        "success": False,
                        "error": "You've already claimed your daily reward today. Come back tomorrow!"
                    }
        
        # Process the reward
        result = gamification_service.process_daily_rewards(user_id)
        
        if result.get("success"):
            # Update last reward date in profile
            db.update_user_profile(user_id, {
                'last_reward_date': datetime.now().isoformat()
            })
        
        if not result.get("success"):
            raise HTTPException(status_code=400, detail=result.get("error", "Failed to claim rewards"))
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Daily rewards error: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


# ========== RESUME ROUTES ==========

@router.get("/resume/generate")
async def generate_resume(authorization: str = Header(None), target_role: Optional[str] = None):
    """Generate resume for user"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        if not resume_service:
            raise HTTPException(status_code=503, detail="Resume service unavailable")
        
        result = resume_service.generate_resume(user_id, target_role)
        
        if not result.get("success"):
            raise HTTPException(status_code=400, detail=result.get("error", "Resume generation failed"))
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Resume generation error: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


# ========== ANALYTICS ROUTES ==========

@router.get("/analytics/learning")
async def get_learning_analytics(authorization: str = Header(None)):
    """Get learning analytics with graceful fallback"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        if not db:
            return {
                "success": False,
                "analytics": {
                    "total_learning_time_hours": 0,
                    "module_completion_rate": 0,
                    "consistency_score": 0
                },
                "error": "Database unavailable"
            }
        
        # Get basic profile data
        try:
            profile = db.get_user_profile(user_id)
        except Exception as e:
            print(f"[ERROR] Profile fetch failed: {e}")
            profile = None
        
        # Calculate basic analytics
        total_sessions = 0
        completed_modules = 0
        
        try:
            sessions = db.client.table('ai_agent_sessions').select('id, status, created_at').eq(
                'user_id', user_id
            ).execute()
            
            if sessions.data:
                total_sessions = len(sessions.data)
                completed = len([s for s in sessions.data if s.get('status') == 'completed'])
                module_completion_rate = (completed / total_sessions * 100) if total_sessions > 0 else 0
            else:
                module_completion_rate = 0
        except Exception as e:
            print(f"[ERROR] Sessions fetch failed: {e}")
            module_completion_rate = 0
        
        return {
            "success": True,
            "analytics": {
                "total_learning_time_hours": profile.get('total_hours', 0) if profile else 0,
                "module_completion_rate": module_completion_rate,
                "consistency_score": min(100, (profile.get('streak_count', 0) or 0) * 5) if profile else 0,
                "skill_growth_trend": [],
                "content_interactions": {},
                "total_modules_completed": completed_modules,
                "active_sessions": total_sessions
            }
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Analytics error: {e}")
        traceback.print_exc()
        return {
            "success": False,
            "analytics": {
                "total_learning_time_hours": 0,
                "module_completion_rate": 0,
                "consistency_score": 0
            },
            "error": str(e)
        }


@router.get("/analytics/skills")
async def get_skills_analytics(authorization: str = Header(None)):
    """Get skills analytics"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        if not db:
            return {
                "success": False,
                "summary": {},
                "skill_growth": [],
                "total_skills": 0
            }
        
        skills = db.get_user_skills(user_id)
        summary = db.get_skill_progress_summary(user_id)
        
        skill_growth = []
        for skill in skills:
            created_at = skill.get('created_at')
            if created_at:
                try:
                    created_date = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
                    days_since = (datetime.now() - created_date).days
                    confidence = float(skill.get('confidence_score', 0))
                    
                    if days_since > 0:
                        daily_growth = confidence / days_since
                        skill_growth.append({
                            "skill": skill.get('skill_name'),
                            "confidence": confidence,
                            "days_practicing": days_since,
                            "daily_growth": daily_growth,
                            "practice_count": skill.get('practice_count', 0)
                        })
                except Exception as e:
                    print(f"[ERROR] Skill date parsing failed: {e}")
                    continue
        
        skill_growth.sort(key=lambda x: x['daily_growth'], reverse=True)
        
        return {
            "success": True,
            "summary": summary,
            "skill_growth": skill_growth[:10],
            "total_skills": len(skills)
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Skills analytics error: {e}")
        traceback.print_exc()
        return {
            "success": False,
            "summary": {},
            "skill_growth": [],
            "total_skills": 0,
            "error": str(e)
        }


# ========== CONTENT ROUTES ==========

@router.post("/content/recommend")
async def get_content_recommendations(request: ContentRecommendationRequest, authorization: str = Header(None)):
    """Get personalized content recommendations"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        if not db:
            # Fallback: use content provider directly
            try:
                from services.content_provider_service import content_provider
                content = content_provider.get_content_for_skill(
                    skill=request.skill,
                    content_type=request.content_type,
                    difficulty=request.difficulty
                )
                
                recommendations = []
                for item in content[:5]:
                    recommendations.append({
                        "content_type": item.get("content_type", "external"),
                        "title": item.get("title"),
                        "description": item.get("description", ""),
                        "url": item.get("source_url"),
                        "platform": item.get("name", "External"),
                        "duration": item.get("duration", 60),
                        "difficulty": item.get("difficulty", "intermediate"),
                        "relevance_score": 0.7
                    })
                
                return {
                    "success": True,
                    "skill": request.skill,
                    "recommendations": recommendations
                }
            except Exception as e:
                print(f"[ERROR] Content provider failed: {e}")
                return {
                    "success": False,
                    "skill": request.skill,
                    "recommendations": [],
                    "error": str(e)
                }
        
        # Try database recommendations first
        recommendations = db.get_content_recommendations(
            user_id=user_id,
            skill=request.skill,
            limit=10
        )
        
        # If no DB recommendations, use content provider
        if not recommendations:
            from services.content_provider_service import content_provider
            
            content = content_provider.get_content_for_skill(
                skill=request.skill,
                content_type=request.content_type,
                difficulty=request.difficulty
            )
            
            recommendations = []
            for item in content[:5]:
                recommendations.append({
                    "content_type": item.get("content_type", "external"),
                    "title": item.get("title"),
                    "description": item.get("description", ""),
                    "url": item.get("source_url"),
                    "platform": item.get("name", "External"),
                    "duration": item.get("duration", 60),
                    "difficulty": item.get("difficulty", "intermediate"),
                    "relevance_score": 0.7
                })
        
        return {
            "success": True,
            "skill": request.skill,
            "recommendations": recommendations
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Content recommendations error: {e}")
        traceback.print_exc()
        return {
            "success": False,
            "skill": request.skill,
            "recommendations": [],
            "error": str(e)
        }


# ========== PROFILE ROUTES ==========

@router.get("/profile/complete/{user_id}")
async def get_complete_profile(user_id: str):
    """Get complete user profile with all data"""
    try:
        if not db:
            raise HTTPException(status_code=503, detail="Database unavailable")
        
        # Get basic profile
        profile = db.get_user_profile(user_id)
        if not profile:
            raise HTTPException(status_code=404, detail="Profile not found")
        
        # Get additional data with error handling
        skills = []
        onboarding = None
        sessions = []
        gamification = {}
        analytics = {}
        
        try:
            skills = db.get_user_skills(user_id)
        except Exception as e:
            print(f"[ERROR] Skills fetch failed: {e}")
        
        try:
            onboarding = db.get_onboarding_data(user_id)
        except Exception as e:
            print(f"[ERROR] Onboarding fetch failed: {e}")
        
        try:
            sessions = db.get_active_sessions(user_id)
        except Exception as e:
            print(f"[ERROR] Sessions fetch failed: {e}")
        
        if gamification_service:
            try:
                gamification = gamification_service.get_user_gamification_summary(user_id)
            except Exception as e:
                print(f"[ERROR] Gamification fetch failed: {e}")
        
        # Build complete profile
        complete_profile = {
            "basic_info": profile,
            "skills": {
                "list": skills,
                "summary": db.get_skill_progress_summary(user_id) if skills else {}
            },
            "onboarding": onboarding,
            "active_sessions": sessions,
            "gamification": gamification,
            "analytics": analytics,
            "statistics": {
                "total_learning_hours": 0,
                "modules_completed": 0,
                "skills_mastered": len([s for s in skills if s.get('confidence_score', 0) >= 0.8]),
                "current_streak": profile.get('streak_count', 0),
                "plaro_points": gamification.get('points_summary', {}).get('total_points', 0)
            }
        }
        
        return {
            "success": True,
            "profile": complete_profile
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Complete profile error: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


# ========== SESSION ROUTES ==========

@router.get("/learning/session/{session_id}")
async def get_learning_session(session_id: str, authorization: str = Header(None)):
    """Get learning session details"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        if not db:
            raise HTTPException(status_code=503, detail="Database unavailable")
        
        session_response = db.client.table('ai_agent_sessions').select('*').eq(
            'id', session_id
        ).eq('user_id', user_id).single().execute()
        
        if not session_response.data:
            raise HTTPException(status_code=404, detail="Session not found")
        
        session_data = session_response.data
        
        # Parse JD if it's a string
        jd_parsed = session_data.get('jd_parsed', {})
        if isinstance(jd_parsed, str):
            try:
                import json
                jd_parsed = json.loads(jd_parsed)
            except:
                jd_parsed = {}
        
        return {
            "success": True,
            "session": {
                "id": session_data.get('id'),
                "jd_text": session_data.get('jd_text'),
                "jd_parsed": jd_parsed,
                "created_at": session_data.get('created_at'),
                "status": session_data.get('status', 'active')
            }
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Session fetch error: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


# ========== USER DATA ROUTES ==========

@router.get("/user/{user_id}/points")
async def get_user_points(user_id: str, authorization: str = Header(None)):
    """Get user points and streak"""
    try:
        if not db:
            return {
                "total": 0,
                "streak": 0,
                "rank_level": "beginner"
            }
        
        # Get gamification summary
        if gamification_service:
            try:
                summary = gamification_service.get_user_gamification_summary(user_id)
                points_summary = summary.get('points_summary', {})
                return {
                    "total": points_summary.get('total_points', 0),
                    "streak": summary.get('streak', 0),
                    "rank_level": points_summary.get('rank_level', 'beginner')
                }
            except Exception as e:
                print(f"[ERROR] Gamification fetch failed: {e}")
        
        # Fallback: get from profile
        try:
            profile = db.get_user_profile(user_id)
            if profile:
                return {
                    "total": 0,
                    "streak": profile.get('streak_count', 0),
                    "rank_level": "beginner"
                }
        except Exception as e:
            print(f"[ERROR] Profile fetch failed: {e}")
        
        return {
            "total": 0,
            "streak": 0,
            "rank_level": "beginner"
        }
        
    except Exception as e:
        print(f"[ERROR] Get user points error: {e}")
        return {
            "total": 0,
            "streak": 0,
            "rank_level": "beginner"
        }


@router.get("/user/{user_id}/skills")
async def get_user_skills_endpoint(user_id: str, authorization: str = Header(None)):
    """Get user skills"""
    try:
        if not db:
            return []
        
        skills = db.get_user_skills(user_id)
        return skills if skills else []
        
    except Exception as e:
        print(f"[ERROR] Get user skills error: {e}")
        return []


@router.get("/user/{user_id}/profile")
async def get_user_profile_endpoint(user_id: str, authorization: str = Header(None)):
    """Get user profile (alias for /api/profile/complete/{user_id})"""
    try:
        return await get_complete_profile(user_id)
    except Exception as e:
        print(f"[ERROR] Get user profile error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/analytics/track")
async def track_analytics_event(authorization: str = Header(None), event_data: Dict = None):
    """Track analytics event"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        if not db:
            return {"success": False, "error": "Database unavailable"}
        
        event_type = event_data.get('event_type') if event_data else 'unknown'
        
        # Store event in database
        try:
            db.client.table('user_content_events').insert({
                'user_id': user_id,
                'content_type': event_data.get('content_type', 'unknown') if event_data else 'unknown',
                'event_type': event_type,
                'metadata': event_data or {},
                'created_at': datetime.now().isoformat()
            }).execute()
        except Exception as e:
            print(f"[ERROR] Event storage failed: {e}")
        
        return {
            "success": True,
            "event_type": event_type,
            "tracked": True
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Track analytics error: {e}")
        return {
            "success": False,
            "error": str(e)
        }


# ========== FRONTEND-SPECIFIC ENDPOINTS ==========

@router.get("/auth/profile/{user_id}")
async def get_user_profile(user_id: str):
    """Get user profile data for frontend"""
    try:
        if not db:
            raise HTTPException(status_code=500, detail="Database not available")
        
        profile = db.get_user_profile(user_id)
        if not profile:
            raise HTTPException(status_code=404, detail="Profile not found")
        
        # Get user skills
        skills = db.get_user_skills(user_id)
        
        return {
            "profile": profile,
            "skills": skills,
            "success": True
        }
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Get profile error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/user/{user_id}/points")
async def get_user_points(user_id: str):
    """Get user gamification points"""
    try:
        if not db:
            raise HTTPException(status_code=500, detail="Database not available")
        
        points_data = db.get_user_plaro_points(user_id)
        
        return {
            "total": points_data.get('total_points', 0),
            "streak": 0,
            "rank_level": points_data.get('rank_level', 'beginner'),
            "recent_transactions": points_data.get('recent_transactions', []),
            "success": True
        }
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Get points error: {e}")
        return {
            "total": 0,
            "streak": 0,
            "rank_level": "beginner",
            "success": False,
            "error": str(e)
        }


@router.get("/api/user/{user_id}/skills")
async def get_user_skills_endpoint(user_id: str):
    """Get user skills list"""
    try:
        if not db:
            raise HTTPException(status_code=500, detail="Database not available")
        
        skills = db.get_user_skills(user_id)
        
        return {
            "skills": skills,
            "count": len(skills),
            "success": True
        }
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Get skills error: {e}")
        return {
            "skills": [],
            "count": 0,
            "success": False,
            "error": str(e)
        }


@router.get("/api/learning/session/{session_id}")
async def get_learning_session(session_id: str):
    """Get learning session data"""
    try:
        if not db:
            raise HTTPException(status_code=500, detail="Database not available")
        
        session = db.client.table('ai_agent_sessions').select('*').eq('id', session_id).single().execute()
        
        if not session.data:
            raise HTTPException(status_code=404, detail="Session not found")
        
        return {
            "session": session.data,
            "success": True
        }
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Get session error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/user/{user_id}/onboarding")
async def get_user_onboarding(user_id: str):
    """Get user onboarding data"""
    try:
        if not db:
            raise HTTPException(status_code=500, detail="Database not available")
        
        onboarding = db.get_onboarding_data(user_id)
        
        return {
            "onboarding": onboarding,
            "success": True
        }
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Get onboarding error: {e}")
        return {
            "onboarding": None,
            "success": False,
            "error": str(e)
        }


@router.get("/api/jobs/recommendations")
async def get_jobs_recommendations(user_id: str = None, target_role: str = None, location: str = "Chennai"):
    """Get job recommendations"""
    try:
        if not target_role:
            return {"jobs": [], "success": True}
        
        from services.job_retrieval_service import adzuna_service
        
        # Search jobs for target role
        jobs = adzuna_service.search_jobs(query=target_role, location=location, max_results=10)
        
        return {
            "jobs": jobs,
            "count": len(jobs),
            "success": True
        }
    except Exception as e:
        print(f"[ERROR] Get jobs error: {e}")
        return {
            "jobs": [],
            "count": 0,
            "success": False,
            "error": str(e)
        }


@router.get("/agent/jobs/recommendations")
async def get_agent_jobs_recommendations(target_role: str = None, location: str = "Chennai", user_id: str = None):
    """Get job recommendations for agent"""
    try:
        if not target_role:
            return {"jobs": [], "count": 0, "success": True}
        
        from services.job_retrieval_service import adzuna_service
        
        # Search jobs for target role
        jobs = adzuna_service.search_jobs(query=target_role, location=location, max_results=10)
        
        return {
            "jobs": jobs,
            "count": len(jobs),
            "target_role": target_role,
            "success": True
        }
    except Exception as e:
        print(f"[ERROR] Get agent jobs error: {e}")
        return {
            "jobs": [],
            "count": 0,
            "success": False,
            "error": str(e)
        }


@router.get("/agent/onboarding/{user_id}")
async def get_agent_onboarding(user_id: str):
    """Get user onboarding data for agent"""
    try:
        if not db:
            raise HTTPException(status_code=500, detail="Database not available")
        
        onboarding = db.get_onboarding_data(user_id)
        
        return {
            "onboarding": onboarding,
            "has_onboarding": onboarding is not None,
            "success": True
        }
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Get agent onboarding error: {e}")
        return {
            "onboarding": None,
            "has_onboarding": False,
            "success": False,
            "error": str(e)
        }


@router.get("/agent/learning-roadmap/{target_role}")
async def get_learning_roadmap(target_role: str):
    """Generate learning roadmap for target role"""
    try:
        from services.content_provider_service import content_provider
        
        # Get primary skill (usually first mentioned)
        primary_skill = target_role.split()[0] if target_role else "Programming"
        
        # Generate roadmap
        roadmap = content_provider.get_learning_roadmap(
            primary_skill=primary_skill,
            secondary_skills=target_role.split()[1:3] if len(target_role.split()) > 1 else []
        )
        
        return {
            "roadmap": roadmap,
            "target_role": target_role,
            "success": True
        }
    except Exception as e:
        print(f"[ERROR] Get learning roadmap error: {e}")
        return {
            "roadmap": None,
            "target_role": target_role,
            "success": False,
            "error": str(e)
        }


@router.post("/api/analytics/track")
async def track_analytics(data: Dict = None, event_type: str = None, user_id: str = None):
    """Track user analytics events"""
    try:
        if not db or not event_type:
            return {"success": False, "error": "Missing required fields"}
        
        # Log analytics
        logged = db.log_content_event(
            user_id=user_id or "anonymous",
            content_type=data.get("content_type", "unknown") if data else "unknown",
            event_type=event_type,
            metadata=data or {}
        )
        
        return {
            "success": logged,
            "event_type": event_type,
            "tracked": logged
        }
    except Exception as e:
        print(f"[ERROR] Track analytics error: {e}")
        return {
            "success": False,
            "error": str(e)
        }