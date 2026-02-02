"""
Agent 4: Learning Path Optimizer
Optimizes learning sequences based on user profile and constraints
Uses Gemini 2.5 Flash for intelligent path orchestration
"""

import google.generativeai as genai
from config import get_settings
import json
from typing import Dict, List

settings = get_settings()
genai.configure(api_key=settings.GEMINI_API_KEY)


class LearningPathOptimizer:
    """
    Agent 4: Optimizes learning sequences based on user profile
    - Re-orders modules by priority and dependencies
    - Suggests module skips based on existing confidence
    - Adjusts difficulty based on user capability
    - Recommends content mix based on learning preference
    """
    
    @staticmethod
    def optimize_learning_sequence(
        user_skills: dict,
        required_skills: list,
        time_constraint_weeks: int,
        learning_preference: str
    ) -> dict:
        """
        Analyzes user profile and optimizes the learning path
        
        Args:
            user_skills: Dict of {skill_name: confidence_score (0-1)}
            required_skills: List of skills needed for target role
            time_constraint_weeks: Available time to upskill
            learning_preference: 'video', 'reading', 'hands_on', or 'mixed'
        
        Returns:
            Dict with optimized sequence, estimates, and recommendations
        """
        
        prompt = f"""
You are a Learning Path Optimization AI Agent specializing in career development.

Analyze the user profile and create an optimized learning path:

USER PROFILE:
- Current Skills with Confidence: {json.dumps(user_skills)}
- Required Skills for Target: {required_skills}
- Available Time: {time_constraint_weeks} weeks
- Preferred Learning Style: {learning_preference}

YOUR TASK:
1. Identify skill gaps (required but low confidence)
2. Prioritize skills by:
   - Relevance to target role (higher = earlier)
   - Dependency chain (prerequisites first)
   - Confidence gap severity
3. Group skills for parallel learning where possible
4. Suggest skipping modules for high-confidence skills (>0.7)
5. Adjust difficulty progressively
6. Optimize content mix based on learning preference

LEARNING PREFERENCE IMPLICATIONS:
- 'video': 70% video, 20% hands-on, 10% reading
- 'reading': 60% text/theory, 20% video, 20% hands-on
- 'hands_on': 60% practice, 30% video, 10% reading
- 'mixed': 40% video, 40% hands-on, 20% reading

Return ONLY this valid JSON (no markdown, no extra text):
{{
    "optimized_sequence": [
        {{
            "priority": 1,
            "skill": "skill_name",
            "current_confidence": 0.3,
            "target_confidence": 1.0,
            "gap_severity": 0.7,
            "reason": "Why this comes first",
            "estimated_weeks": 2,
            "parallel_with": ["skill2", "skill3"],
            "skip_modules": [],
            "content_mix": {{"video": 0.6, "practice": 0.3, "reading": 0.1}},
            "difficulty_progression": "beginner -> intermediate -> advanced",
            "prerequisite_skills": [],
            "success_criteria": "Complete all modules with 70%+ checkpoint score"
        }}
    ],
    "learning_strategy": "sequential|parallel|hybrid",
    "estimated_completion_weeks": 8,
    "total_learning_hours": 60,
    "difficulty_adjustment": "increase|decrease|maintain",
    "risk_factors": ["time constraint", "skill complexity"],
    "recommendations": [
        "Start with foundational skills first",
        "Use spaced repetition for complex topics",
        "Practice hands-on projects immediately after theory"
    ],
    "success_probability": 0.85
}}
"""
        
        try:
            print(f"[OPTIMIZER] 🧠 Optimizing path for {len(required_skills)} skills with {time_constraint_weeks} weeks available")
            
            model = genai.GenerativeModel(
                'gemini-2.5-flash',
                generation_config={
                    "temperature": 0.4,
                    "response_mime_type": "application/json",
                    "top_p": 0.9,
                    "top_k": 40
                }
            )
            
            response = model.generate_content(prompt)
            
            if not response.text:
                print(f"[ERROR] Empty response from Gemini")
                return LearningPathOptimizer._fallback_optimization(
                    user_skills, required_skills, time_constraint_weeks, learning_preference
                )
            
            result = json.loads(response.text)
            
            # Validate response structure
            if not isinstance(result, dict) or 'optimized_sequence' not in result:
                print(f"[ERROR] Invalid response structure")
                return LearningPathOptimizer._fallback_optimization(
                    user_skills, required_skills, time_constraint_weeks, learning_preference
                )
            
            print(f"[OPTIMIZER] ✅ Successfully optimized learning path")
            print(f"   - Sequence: {len(result['optimized_sequence'])} skills")
            print(f"   - Strategy: {result.get('learning_strategy', 'unknown')}")
            print(f"   - Estimated weeks: {result.get('estimated_completion_weeks', '?')}")
            
            return result
        
        except json.JSONDecodeError as e:
            print(f"[ERROR] JSON parsing failed: {e}")
            return LearningPathOptimizer._fallback_optimization(
                user_skills, required_skills, time_constraint_weeks, learning_preference
            )
        except Exception as e:
            print(f"[ERROR] Optimization failed: {e}")
            return LearningPathOptimizer._fallback_optimization(
                user_skills, required_skills, time_constraint_weeks, learning_preference
            )
    
    @staticmethod
    def _fallback_optimization(user_skills: dict, required_skills: list, weeks: int, pref: str) -> dict:
        """Fallback optimization if Gemini fails"""
        
        print(f"[OPTIMIZER] 🔄 Using fallback optimization")
        
        # Sort by confidence gap
        scored_skills = [
            (skill, user_skills.get(skill, 0.0), 1.0 - user_skills.get(skill, 0.0))
            for skill in required_skills
        ]
        scored_skills.sort(key=lambda x: x[2], reverse=True)  # Sort by gap
        
        # Content mix preference mapping
        mix_map = {
            "video": {"video": 0.7, "practice": 0.2, "reading": 0.1},
            "reading": {"text": 0.6, "video": 0.2, "practice": 0.2},
            "hands_on": {"practice": 0.6, "video": 0.3, "text": 0.1},
            "mixed": {"video": 0.4, "practice": 0.4, "text": 0.2}
        }
        
        pref_mix = mix_map.get(pref, mix_map["mixed"])
        
        # Estimate hours per skill (3-6 hours per skill depending on gap)
        hours_per_skill = weeks * 7 / len(required_skills) if required_skills else 0
        
        sequence = []
        for i, (skill, current_conf, gap) in enumerate(scored_skills[:5]):  # Top 5 skills
            sequence.append({
                "priority": i + 1,
                "skill": skill,
                "current_confidence": round(current_conf, 2),
                "target_confidence": 1.0,
                "gap_severity": round(gap, 2),
                "reason": f"Gap severity: {round(gap * 100, 0)}%" if gap > 0.5 else "Foundational skill",
                "estimated_weeks": 2,
                "parallel_with": [],
                "skip_modules": [] if gap > 0.3 else [1, 2],  # Skip for high confidence
                "content_mix": pref_mix,
                "difficulty_progression": "beginner -> intermediate",
                "prerequisite_skills": [],
                "success_criteria": "70%+ on checkpoint assessments"
            })
        
        return {
            "optimized_sequence": sequence,
            "learning_strategy": "sequential",
            "estimated_completion_weeks": weeks,
            "total_learning_hours": int(hours_per_skill * len(required_skills)),
            "difficulty_adjustment": "maintain",
            "risk_factors": ["Using fallback optimization"],
            "recommendations": [
                f"Focus on {scored_skills[0][0]} first (highest gap)",
                f"Use {pref} learning materials when available",
                f"Plan {int(hours_per_skill)} hours per skill"
            ],
            "success_probability": 0.75
        }


# Global instance
learning_optimizer = LearningPathOptimizer()
