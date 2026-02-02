"""
Skill Gap Routes - Explicit API Endpoints
Makes skill gap a first-class computed entity
"""
from fastapi import APIRouter, HTTPException, Header
from typing import Optional

router = APIRouter()

# Import skill gap service
try:
    from services.skill_gap_service import skill_gap_service
    from database import EnhancedSupabaseHelper
    db = EnhancedSupabaseHelper()
except Exception as e:
    print(f"[ERROR] Failed to import skill gap service: {e}")
    skill_gap_service = None
    db = None


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


# ==================== SKILL GAP ENDPOINTS ====================

@router.get("/skill-gap")
async def get_skill_gap_analysis(
    authorization: str = Header(None),
    target_role: Optional[str] = None
):
    """
    PRIMARY SKILL GAP ENDPOINT
    Returns complete skill gap analysis with evidence
    """
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        if not skill_gap_service:
            raise HTTPException(status_code=503, detail="Skill gap service unavailable")
        
        print(f"[SKILL GAP API] Computing for user: {user_id}")
        
        skill_gap = skill_gap_service.compute_skill_gap(user_id, target_role)
        
        return {
            "success": True,
            "skill_gap_analysis": skill_gap
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Skill gap API failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/skill-gap/summary")
async def get_skill_gap_summary(authorization: str = Header(None)):
    """
    Quick skill gap summary
    Returns only critical metrics without full details
    """
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        if not skill_gap_service:
            raise HTTPException(status_code=503, detail="Service unavailable")
        
        full_analysis = skill_gap_service.compute_skill_gap(user_id)
        
        return {
            "success": True,
            "summary": {
                "total_skills": full_analysis.get('total_skills', 0),
                "overall_readiness": full_analysis.get('overall_readiness', 0),
                "readiness_level": full_analysis.get('readiness_level', 'getting_started'),
                "critical_gaps_count": len(full_analysis.get('critical_gaps', [])),
                "mastered_skills_count": len(full_analysis.get('mastered_skills', [])),
                "top_priority_skills": [
                    {
                        "skill": gap['skill'],
                        "gap_severity": gap['gap_severity'],
                        "current_confidence": gap['current_confidence']
                    }
                    for gap in full_analysis.get('skill_gaps', [])[:3]
                ]
            }
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Skill gap summary failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/skill-gap/skill/{skill_name}")
async def get_single_skill_gap(
    skill_name: str,
    authorization: str = Header(None)
):
    """
    Get detailed gap analysis for a single skill
    Includes all evidence and recommendations
    """
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        if not skill_gap_service:
            raise HTTPException(status_code=503, detail="Service unavailable")
        
        # Get full analysis and filter for this skill
        full_analysis = skill_gap_service.compute_skill_gap(user_id)
        
        skill_detail = None
        for gap in full_analysis.get('skill_gaps', []):
            if gap['skill'].lower() == skill_name.lower():
                skill_detail = gap
                break
        
        if not skill_detail:
            raise HTTPException(
                status_code=404,
                detail=f"Skill '{skill_name}' not found in target skills"
            )
        
        # Get detailed evidence
        if db:
            evidence = db.get_skill_evidence(user_id, skill_name)
        else:
            evidence = {}
        
        return {
            "success": True,
            "skill": skill_name,
            "gap_analysis": skill_detail,
            "detailed_evidence": evidence
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Single skill gap failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/skill-gap/recommendations/{skill_name}")
async def get_skill_recommendations(
    skill_name: str,
    authorization: str = Header(None)
):
    """
    Get learning recommendations for a specific skill gap
    """
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        # Get skill gap
        full_analysis = skill_gap_service.compute_skill_gap(user_id)
        
        skill_gap = None
        for gap in full_analysis.get('skill_gaps', []):
            if gap['skill'].lower() == skill_name.lower():
                skill_gap = gap
                break
        
        if not skill_gap:
            return {
                "success": False,
                "error": f"Skill '{skill_name}' not found"
            }
        
        difficulty = "beginner" if skill_gap['current_confidence'] < 0.3 else \
                    "intermediate" if skill_gap['current_confidence'] < 0.7 else "advanced"
        
        return {
            "success": True,
            "skill": skill_name,
            "current_confidence": skill_gap['current_confidence'],
            "gap_severity": skill_gap['gap_severity'],
            "recommendations": skill_gap['recommendations'],
            "suggested_difficulty": difficulty
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Skill recommendations failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/learning-context")
async def get_learning_context(authorization: str = Header(None)):
    """
    OPTIMIZED: Get user's complete learning context
    Used by frontend to initialize learning views
    """
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        if not db:
            raise HTTPException(status_code=503, detail="Service unavailable")
        
        context = db.get_user_learning_context(user_id)
        
        return {
            "success": True,
            "context": context
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Learning context failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/skill-evidence/{skill_name}")
async def get_skill_evidence_detail(
    skill_name: str,
    authorization: str = Header(None)
):
    """
    Get all evidence for a skill
    Shows checkpoints, practice, modules, taikens
    """
    try:
        user = get_user_from_token(authorization)
        user_id = user.id
        
        if not db:
            raise HTTPException(status_code=503, detail="Service unavailable")
        
        evidence = db.get_skill_evidence(user_id, skill_name)
        
        return {
            "success": True,
            "skill": skill_name,
            "evidence": evidence,
            "summary": {
                "checkpoints_passed": len([c for c in evidence.get('checkpoints', []) if c.get('passed')]),
                "practice_tasks_completed": len(evidence.get('practice_tasks', [])),
                "modules_completed": len([m for m in evidence.get('modules', []) if m.get('status') == 'completed']),
                "taikens_completed": len([t for t in evidence.get('taikens', []) if t.get('status') == 'completed'])
            }
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Skill evidence failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))
