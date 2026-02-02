"""
Enhanced Routes - Practice, RPG, Feedback, Notifications
Adds: Practice Sets, RPG Mechanics, Feedback, Notifications
"""
from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel
from typing import List, Optional, Dict
from datetime import datetime

router = APIRouter()

# Import all services
try:
    from database import EnhancedSupabaseHelper
    from services.practice_service import practice_service
    from services.rpg_progression_service import rpg_service
    from services.feedback_service import feedback_service
    from services.notification_service import notification_service
    
    db = EnhancedSupabaseHelper()
except Exception as e:
    print(f"[ERROR] Service import failed: {e}")
    db = None


# ==================== REQUEST MODELS ====================

class PracticeSetRequest(BaseModel):
    skill: str
    topic: str
    difficulty: str = "medium"
    question_count: int = 5


class PracticeSubmission(BaseModel):
    skill: str
    topic: str
    questions: List[Dict]
    answers: List[int]
    time_taken_seconds: int


class FeedbackRequest(BaseModel):
    module_id: Optional[str] = None
    course_id: Optional[str] = None
    skill: Optional[str] = None
    rating: int
    usefulness_rating: Optional[int] = None
    feedback_text: Optional[str] = None
    tags: Optional[List[str]] = None


class SuggestionRequest(BaseModel):
    suggestion_type: str
    suggestion_text: str
    priority: str = "medium"


class EnergyConsumption(BaseModel):
    activity: str
    energy_cost: int


# ==================== HELPER ====================

def get_user_from_token(authorization: str):
    """Extract user from auth header"""
    if not authorization:
        raise HTTPException(status_code=401, detail="No authorization")
    
    if not db:
        raise HTTPException(status_code=503, detail="Service unavailable")
    
    token = authorization.replace("Bearer ", "")
    try:
        user_response = db.client.auth.get_user(token)
        
        if not user_response or not user_response.user:
            raise HTTPException(status_code=401, detail="Invalid token")
        
        return user_response.user
    except:
        raise HTTPException(status_code=401, detail="Invalid token")


# ==================== PRACTICE SETS ====================

@router.post("/practice/generate")
async def generate_practice_set(
    request: PracticeSetRequest,
    authorization: str = Header(None)
):
    """Generate practice questions"""
    try:
        user = get_user_from_token(authorization)
        
        practice_set = practice_service.generate_practice_set(
            skill=request.skill,
            topic=request.topic,
            difficulty=request.difficulty,
            question_count=request.question_count
        )
        
        return {
            "success": True,
            "practice_set": practice_set
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Practice generation failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/practice/submit")
async def submit_practice_set(
    submission: PracticeSubmission,
    authorization: str = Header(None)
):
    """Submit practice attempt"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        result = practice_service.save_practice_attempt(
            user_id=user_id,
            skill=submission.skill,
            topic=submission.topic,
            questions=submission.questions,
            answers=submission.answers,
            time_taken_seconds=submission.time_taken_seconds
        )
        
        # Award XP based on performance
        xp_result = None
        if result['score'] >= 80:
            xp_result = rpg_service.award_xp(user_id, rpg_service.get_xp_rewards()['practice_set_perfect'], 
                                            f"Perfect practice: {submission.skill}")
        elif result['score'] >= 60:
            xp_result = rpg_service.award_xp(user_id, rpg_service.get_xp_rewards()['practice_set_good'],
                                            f"Good practice: {submission.skill}")
        
        return {
            "success": True,
            "result": result,
            "xp_awarded": xp_result if xp_result and xp_result.get('success') else None
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Practice submission failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/practice/history")
async def get_practice_history(
    authorization: str = Header(None),
    skill: Optional[str] = None
):
    """Get practice history"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        history = practice_service.get_practice_history(user_id, skill)
        analytics = practice_service.get_practice_analytics(user_id)
        
        return {
            "success": True,
            "history": history,
            "analytics": analytics
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Practice history failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ==================== RPG SYSTEM ====================

@router.get("/rpg/stats")
async def get_rpg_stats(authorization: str = Header(None)):
    """Get user RPG statistics"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        stats = rpg_service.get_user_rpg_stats(user_id)
        energy_costs = rpg_service.get_energy_costs()
        xp_rewards = rpg_service.get_xp_rewards()
        
        return {
            "success": True,
            "stats": stats,
            "energy_costs": energy_costs,
            "xp_rewards": xp_rewards
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] RPG stats failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/rpg/consume-energy")
async def consume_energy(
    consumption: EnergyConsumption,
    authorization: str = Header(None)
):
    """Consume energy for activity"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        result = rpg_service.consume_energy(
            user_id=user_id,
            energy_cost=consumption.energy_cost,
            activity=consumption.activity
        )
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Energy consumption failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/rpg/award-xp/{xp_amount}")
async def award_xp_manual(
    xp_amount: int,
    reason: str,
    authorization: str = Header(None)
):
    """Award XP (for testing/admin)"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        result = rpg_service.award_xp(user_id, xp_amount, reason)
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Award XP failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ==================== FEEDBACK & REVIEWS ====================

@router.post("/feedback/submit")
async def submit_feedback(
    feedback: FeedbackRequest,
    authorization: str = Header(None)
):
    """Submit feedback"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        if feedback.module_id and feedback.skill:
            result = feedback_service.submit_module_feedback(
                user_id=user_id,
                module_id=feedback.module_id,
                skill=feedback.skill,
                rating=feedback.rating,
                feedback_text=feedback.feedback_text,
                tags=feedback.tags
            )
        elif feedback.course_id:
            result = feedback_service.submit_course_feedback(
                user_id=user_id,
                course_id=feedback.course_id,
                rating=feedback.rating,
                usefulness_rating=feedback.usefulness_rating or feedback.rating,
                feedback_text=feedback.feedback_text
            )
        else:
            raise HTTPException(status_code=400, detail="Must provide module_id+skill OR course_id")
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Feedback submission failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/feedback/suggestion")
async def submit_suggestion(
    suggestion: SuggestionRequest,
    authorization: str = Header(None)
):
    """Submit improvement suggestion"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        result = feedback_service.submit_improvement_suggestion(
            user_id=user_id,
            suggestion_type=suggestion.suggestion_type,
            suggestion_text=suggestion.suggestion_text,
            priority=suggestion.priority
        )
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Suggestion failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/feedback/module/{module_id}/ratings")
async def get_module_ratings(module_id: str):
    """Get module ratings"""
    try:
        ratings = feedback_service.get_module_ratings(module_id)
        return {
            "success": True,
            "ratings": ratings
        }
        
    except Exception as e:
        print(f"[ERROR] Get ratings failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/feedback/history")
async def get_feedback_history(authorization: str = Header(None)):
    """Get user feedback history"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        history = feedback_service.get_user_feedback_history(user_id)
        
        return {
            "success": True,
            "history": history
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Feedback history failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ==================== NOTIFICATIONS ====================

@router.get("/notifications")
async def get_notifications(authorization: str = Header(None)):
    """Get user notifications"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        notifications = notification_service.get_user_notifications(user_id)
        summary = notification_service.get_notification_summary(user_id)
        
        return {
            "success": True,
            "notifications": notifications,
            "summary": summary
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Get notifications failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/notifications/{notification_id}/mark-read")
async def mark_notification_read(
    notification_id: str,
    authorization: str = Header(None)
):
    """Mark notification as read"""
    try:
        user = get_user_from_token(authorization)
        
        result = notification_service.mark_as_read(notification_id)
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Mark read failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/notifications/summary")
async def get_notification_summary(authorization: str = Header(None)):
    """Get notification summary"""
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        summary = notification_service.get_notification_summary(user_id)
        
        return {
            "success": True,
            "summary": summary
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Notification summary failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))
