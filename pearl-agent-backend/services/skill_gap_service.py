"""
Skill Gap Service - First-Class Computed Entity
Aggregates skill data from multiple sources to provide accurate gap analysis
"""
from typing import Dict, List, Optional
from datetime import datetime
import json

try:
    from database import EnhancedSupabaseHelper
    db = EnhancedSupabaseHelper()
except:
    db = None


class SkillGapService:
    """
    Computes skill gaps by aggregating:
    - user_onboarding.skills (baseline)
    - user_skill_memory (current confidence)
    - ai_checkpoint_results (evidence)
    - ai_task_results (practice evidence)
    - taiken_progress (experiential evidence)
    """
    
    @staticmethod
    def compute_skill_gap(user_id: str, target_role: Optional[str] = None) -> Dict:
        """
        MAIN SKILL GAP COMPUTATION
        Returns complete skill gap analysis with evidence
        """
        try:
            print(f"[SKILL GAP] Computing for user: {user_id}")
            
            # 1. Get target skills from onboarding or roadmap
            target_skills = SkillGapService._get_target_skills(user_id, target_role)
            
            # 2. Get current skill confidence from memory
            current_skills = SkillGapService._get_current_skills(user_id)
            
            # 3. Get evidence from multiple sources
            evidence = SkillGapService._get_skill_evidence(user_id)
            
            # 4. Compute gaps
            skill_gaps = []
            
            for skill in target_skills:
                current_confidence = current_skills.get(skill, 0.0)
                skill_evidence = evidence.get(skill, {})
                
                gap_severity = max(0.0, 0.8 - current_confidence)  # Target: 80%
                
                skill_gap = {
                    "skill": skill,
                    "target_confidence": 0.8,
                    "current_confidence": round(current_confidence, 2),
                    "gap_severity": round(gap_severity, 2),
                    "status": SkillGapService._get_skill_status(current_confidence),
                    "evidence": skill_evidence,
                    "recommendations": SkillGapService._get_recommendations(
                        skill, current_confidence, skill_evidence
                    )
                }
                
                skill_gaps.append(skill_gap)
            
            # 5. Sort by gap severity (highest first)
            skill_gaps.sort(key=lambda x: x['gap_severity'], reverse=True)
            
            # 6. Calculate overall readiness
            overall_readiness = SkillGapService._calculate_readiness(skill_gaps)
            
            print(f"[SKILL GAP] ✅ Computed {len(skill_gaps)} skill gaps")
            
            return {
                "user_id": user_id,
                "target_role": target_role or "Career Goal",
                "total_skills": len(skill_gaps),
                "skill_gaps": skill_gaps,
                "overall_readiness": round(overall_readiness, 2),
                "readiness_level": SkillGapService._get_readiness_level(overall_readiness),
                "critical_gaps": [s for s in skill_gaps if s['gap_severity'] >= 0.5],
                "mastered_skills": [s for s in skill_gaps if s['current_confidence'] >= 0.8],
                "computed_at": datetime.now().isoformat()
            }
            
        except Exception as e:
            print(f"[SKILL GAP ERROR] {e}")
            return {
                "user_id": user_id,
                "total_skills": 0,
                "skill_gaps": [],
                "overall_readiness": 0.0,
                "error": str(e)
            }
    
    @staticmethod
    def _get_target_skills(user_id: str, target_role: Optional[str]) -> List[str]:
        """Get target skills from onboarding or roadmap"""
        try:
            if not db:
                return []
            
            # First try onboarding
            onboarding = db.client.table('user_onboarding').select('skills, target_role').eq(
                'user_id', user_id
            ).execute()
            
            if onboarding.data:
                skills_data = onboarding.data[0].get('skills')
                
                # Handle different skill formats
                if isinstance(skills_data, str):
                    skills_data = json.loads(skills_data)
                
                if isinstance(skills_data, list):
                    # Could be list of strings or list of dicts
                    if skills_data and isinstance(skills_data[0], dict):
                        return [s['skill'] for s in skills_data if 'skill' in s]
                    else:
                        return skills_data
            
            # Fallback: try active roadmap
            roadmap = db.client.table('ai_roadmap').select('roadmap_data').eq(
                'user_id', user_id
            ).eq('status', 'active').order('created_at', desc=True).limit(1).execute()
            
            if roadmap.data:
                roadmap_data = roadmap.data[0].get('roadmap_data', {})
                return roadmap_data.get('skills', [])
            
            # Last resort: extract from skill memory
            skills = db.client.table('user_skill_memory').select('skill_name').eq(
                'user_id', user_id
            ).execute()
            
            return [s['skill_name'] for s in (skills.data or [])]
            
        except Exception as e:
            print(f"[SKILL GAP] Target skills error: {e}")
            return []
    
    @staticmethod
    def _get_current_skills(user_id: str) -> Dict[str, float]:
        """Get current skill confidence from user_skill_memory"""
        try:
            if not db:
                return {}
            
            skills = db.client.table('user_skill_memory').select(
                'skill_name, confidence_score'
            ).eq('user_id', user_id).execute()
            
            return {
                s['skill_name']: float(s.get('confidence_score', 0.0))
                for s in (skills.data or [])
            }
            
        except Exception as e:
            print(f"[SKILL GAP] Current skills error: {e}")
            return {}
    
    @staticmethod
    def _get_skill_evidence(user_id: str) -> Dict[str, Dict]:
        """
        Aggregate evidence from:
        - Checkpoints passed
        - Practice tasks completed
        - Taikens completed
        - Modules completed
        """
        evidence = {}
        
        try:
            if not db:
                return evidence
            
            # 1. Checkpoint evidence
            checkpoints = db.client.table('ai_checkpoint_results').select(
                'questions, score, passed'
            ).eq('user_id', user_id).execute()
            
            checkpoint_count = len(checkpoints.data or [])
            passed_count = len([c for c in (checkpoints.data or []) if c.get('passed')])
            
            # 2. Practice task evidence
            tasks = db.client.table('ai_task_results').select(
                'score'
            ).eq('user_id', user_id).execute()
            
            task_count = len(tasks.data or [])
            avg_task_score = sum(t.get('score', 0) for t in (tasks.data or [])) / task_count if task_count > 0 else 0
            
            # 3. Taiken evidence
            taikens = db.client.table('taiken_progress').select(
                'correct_answers, wrong_answers, status'
            ).eq('user_id', user_id).execute()
            
            taiken_completed = len([t for t in (taikens.data or []) if t.get('status') == 'completed'])
            
            # 4. Module evidence
            modules = db.client.table('ai_module_progress').select(
                'skill, status, actions_completed'
            ).eq('user_id', user_id).execute()
            
            # Group by skill
            for module in (modules.data or []):
                skill = module.get('skill')
                if not skill:
                    continue
                
                if skill not in evidence:
                    evidence[skill] = {
                        'modules_completed': 0,
                        'modules_active': 0,
                        'checkpoints_passed': 0,
                        'practice_tasks': 0,
                        'taikens_completed': 0,
                        'total_actions': 0
                    }
                
                if module.get('status') == 'completed':
                    evidence[skill]['modules_completed'] += 1
                elif module.get('status') == 'active':
                    evidence[skill]['modules_active'] += 1
                
                evidence[skill]['total_actions'] += module.get('actions_completed', 0)
            
            # Add global evidence
            for skill in evidence:
                evidence[skill]['checkpoints_passed'] = passed_count
                evidence[skill]['practice_tasks'] = task_count
                evidence[skill]['taikens_completed'] = taiken_completed
            
            return evidence
            
        except Exception as e:
            print(f"[SKILL GAP] Evidence aggregation error: {e}")
            return {}
    
    @staticmethod
    def _get_skill_status(confidence: float) -> str:
        """Determine skill status from confidence"""
        if confidence >= 0.8:
            return "mastered"
        elif confidence >= 0.5:
            return "intermediate"
        elif confidence >= 0.2:
            return "beginner"
        else:
            return "not_started"
    
    @staticmethod
    def _get_recommendations(skill: str, confidence: float, evidence: Dict) -> List[str]:
        """Generate recommendations based on skill gap"""
        recommendations = []
        
        if confidence < 0.2:
            recommendations.append(f"Start with foundational {skill} modules")
            recommendations.append("Watch introductory video content")
        elif confidence < 0.5:
            recommendations.append(f"Practice {skill} with hands-on exercises")
            recommendations.append("Complete intermediate modules")
        elif confidence < 0.8:
            recommendations.append(f"Take advanced {skill} challenges")
            recommendations.append("Build real-world projects")
        else:
            recommendations.append(f"Maintain {skill} mastery with regular practice")
            recommendations.append("Consider teaching or mentoring others")
        
        # Evidence-based recommendations
        if evidence.get('modules_completed', 0) == 0:
            recommendations.append("Begin learning modules for this skill")
        
        if evidence.get('practice_tasks', 0) == 0:
            recommendations.append("Try practice exercises to reinforce learning")
        
        if evidence.get('checkpoints_passed', 0) == 0:
            recommendations.append("Take skill assessments to validate progress")
        
        return recommendations[:3]  # Top 3 recommendations
    
    @staticmethod
    def _calculate_readiness(skill_gaps: List[Dict]) -> float:
        """Calculate overall readiness percentage"""
        if not skill_gaps:
            return 0.0
        
        total_confidence = sum(s['current_confidence'] for s in skill_gaps)
        target_confidence = len(skill_gaps) * 0.8
        
        return (total_confidence / target_confidence) * 100 if target_confidence > 0 else 0.0
    
    @staticmethod
    def _get_readiness_level(readiness: float) -> str:
        """Convert readiness to level"""
        if readiness >= 90:
            return "job_ready"
        elif readiness >= 70:
            return "nearly_ready"
        elif readiness >= 50:
            return "progressing_well"
        elif readiness >= 30:
            return "building_foundation"
        else:
            return "getting_started"
    
    @staticmethod
    def update_skill_on_completion(user_id: str, skill: str, evidence_type: str, 
                                   score: float = 0.0) -> bool:
        """
        UPDATE SKILL MEMORY ON COMPLETION EVENTS
        Called automatically when:
        - Taiken completed
        - Checkpoint passed
        - Practice task submitted
        - Module completed
        """
        try:
            if not db:
                return False
            
            print(f"[SKILL UPDATE] {skill} - {evidence_type} - score: {score}")
            
            # Calculate confidence delta based on evidence type
            delta_map = {
                'taiken_completed': 0.15,
                'checkpoint_passed': 0.10,
                'practice_task': min(0.05, score / 100 * 0.1),
                'module_completed': 0.08
            }
            
            confidence_delta = delta_map.get(evidence_type, 0.05)
            
            # Get or create skill memory
            existing = db.client.table('user_skill_memory').select('*').eq(
                'user_id', user_id
            ).eq('skill_name', skill).execute()
            
            if existing.data:
                current = existing.data[0]
                new_confidence = min(1.0, float(current.get('confidence_score', 0)) + confidence_delta)
                
                # Update evidence
                evidence = current.get('evidence', {})
                if not isinstance(evidence, dict):
                    evidence = {}
                
                evidence[evidence_type] = evidence.get(evidence_type, 0) + 1
                evidence['last_update'] = datetime.now().isoformat()
                evidence['last_score'] = score
                
                db.client.table('user_skill_memory').update({
                    'confidence_score': new_confidence,
                    'evidence': evidence,
                    'practice_count': current.get('practice_count', 0) + 1,
                    'last_practiced_at': datetime.now().isoformat(),
                    'updated_at': datetime.now().isoformat()
                }).eq('id', current['id']).execute()
                
                print(f"[SKILL UPDATE] ✅ Updated {skill}: {new_confidence:.2f}")
            else:
                # Create new
                db.client.table('user_skill_memory').insert({
                    'user_id': user_id,
                    'skill_name': skill,
                    'confidence_score': confidence_delta,
                    'evidence': {
                        evidence_type: 1,
                        'created': datetime.now().isoformat()
                    },
                    'practice_count': 1,
                    'last_practiced_at': datetime.now().isoformat(),
                    'created_at': datetime.now().isoformat()
                }).execute()
                
                print(f"[SKILL UPDATE] ✅ Created {skill}: {confidence_delta:.2f}")
            
            return True
            
        except Exception as e:
            print(f"[SKILL UPDATE ERROR] {e}")
            return False


# Global instance
skill_gap_service = SkillGapService()
