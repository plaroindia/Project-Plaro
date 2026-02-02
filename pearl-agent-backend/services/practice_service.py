"""
Practice Sets Service
Generates and manages topic-wise practice questions
"""
from typing import List, Dict, Optional
import json
from datetime import datetime

try:
    import google.generativeai as genai
    from config import get_settings
    settings = get_settings()
    genai.configure(api_key=settings.GEMINI_API_KEY)
except:
    genai = None
    settings = None

try:
    from database import EnhancedSupabaseHelper
    db = EnhancedSupabaseHelper()
except:
    db = None


class PracticeSetService:
    """Manages practice sets for skills"""
    
    @staticmethod
    def generate_practice_set(
        skill: str,
        topic: str,
        difficulty: str = "medium",
        question_count: int = 5
    ) -> Dict:
        """Generate practice questions for a skill/topic"""
        
        prompt = f"""
Generate {question_count} practice questions for {skill} - {topic}.

Difficulty: {difficulty}
Question types: Multiple choice (4 options each)

Requirements:
- Questions must test practical understanding
- Options should include common misconceptions
- Explanations should teach, not just confirm answers
- Progress from easier to harder within the set

Return ONLY valid JSON:
{{
    "skill": "{skill}",
    "topic": "{topic}",
    "difficulty": "{difficulty}",
    "questions": [
        {{
            "question": "Question text here",
            "options": ["Option A", "Option B", "Option C", "Option D"],
            "correct_index": 0,
            "explanation": "Why this is correct and others are wrong",
            "topic_tags": ["subtopic1", "subtopic2"]
        }}
    ]
}}
"""
        
        try:
            if not genai:
                return PracticeSetService._get_fallback_practice(skill, topic, difficulty, question_count)
            
            model = genai.GenerativeModel(
                'gemini-2.5-flash',
                generation_config={
                    "temperature": 0.7,
                    "response_mime_type": "application/json"
                }
            )
            
            response = model.generate_content(prompt)
            practice_set = json.loads(response.text)
            
            # Add metadata
            practice_set['created_at'] = datetime.now().isoformat()
            practice_set['total_questions'] = len(practice_set.get('questions', []))
            
            return practice_set
            
        except Exception as e:
            print(f"[PRACTICE] Generation failed: {e}")
            return PracticeSetService._get_fallback_practice(skill, topic, difficulty, question_count)
    
    @staticmethod
    def _get_fallback_practice(skill: str, topic: str, difficulty: str, count: int) -> Dict:
        """Fallback practice set"""
        return {
            "skill": skill,
            "topic": topic,
            "difficulty": difficulty,
            "questions": [
                {
                    "question": f"What is a fundamental concept in {topic}?",
                    "options": [
                        f"Understanding core {topic} principles",
                        "Ignoring best practices",
                        "Skipping fundamentals",
                        "Memorizing without understanding"
                    ],
                    "correct_index": 0,
                    "explanation": f"Mastering {topic} requires understanding core principles first.",
                    "topic_tags": [topic, "fundamentals"]
                }
                for _ in range(count)
            ],
            "total_questions": count,
            "created_at": datetime.now().isoformat()
        }
    
    @staticmethod
    def save_practice_attempt(
        user_id: str,
        skill: str,
        topic: str,
        questions: List[Dict],
        answers: List[int],
        time_taken_seconds: int
    ) -> Dict:
        """Save practice attempt and calculate score"""
        
        correct_count = 0
        results = []
        
        for i, (question, answer) in enumerate(zip(questions, answers)):
            is_correct = answer == question.get('correct_index', 0)
            if is_correct:
                correct_count += 1
            
            results.append({
                "question_index": i,
                "user_answer": answer,
                "correct_answer": question.get('correct_index', 0),
                "is_correct": is_correct,
                "explanation": question.get('explanation', '')
            })
        
        score = (correct_count / len(questions)) * 100 if questions else 0
        
        # Save to database
        try:
            if db:
                attempt_data = {
                    'user_id': user_id,
                    'skill': skill,
                    'topic': topic,
                    'questions': questions,
                    'answers': answers,
                    'score': score,
                    'correct_count': correct_count,
                    'total_questions': len(questions),
                    'time_taken_seconds': time_taken_seconds,
                    'submitted_at': datetime.now().isoformat()
                }
                
                db.client.table('practice_attempts').insert(attempt_data).execute()
        
        except Exception as e:
            print(f"[PRACTICE] Save failed: {e}")
        
        return {
            "score": score,
            "correct_count": correct_count,
            "total_questions": len(questions),
            "results": results,
            "performance": "excellent" if score >= 80 else "good" if score >= 60 else "needs_improvement"
        }
    
    @staticmethod
    def get_practice_history(user_id: str, skill: Optional[str] = None) -> List[Dict]:
        """Get user's practice history"""
        try:
            if not db:
                return []
            
            query = db.client.table('practice_attempts').select('*').eq('user_id', user_id)
            
            if skill:
                query = query.eq('skill', skill)
            
            response = query.order('submitted_at', desc=True).limit(20).execute()
            
            return response.data if response.data else []
            
        except Exception as e:
            print(f"[PRACTICE] History fetch failed: {e}")
            return []
    
    @staticmethod
    def get_practice_analytics(user_id: str) -> Dict:
        """Get practice performance analytics"""
        try:
            attempts = PracticeSetService.get_practice_history(user_id)
            
            if not attempts:
                return {
                    "total_attempts": 0,
                    "average_score": 0,
                    "skills_practiced": []
                }
            
            total_score = sum(a.get('score', 0) for a in attempts)
            avg_score = total_score / len(attempts)
            
            skills_practiced = {}
            for attempt in attempts:
                skill = attempt.get('skill', 'Unknown')
                if skill not in skills_practiced:
                    skills_practiced[skill] = {
                        "attempts": 0,
                        "total_score": 0,
                        "best_score": 0
                    }
                
                skills_practiced[skill]["attempts"] += 1
                skills_practiced[skill]["total_score"] += attempt.get('score', 0)
                skills_practiced[skill]["best_score"] = max(
                    skills_practiced[skill]["best_score"],
                    attempt.get('score', 0)
                )
            
            # Calculate averages
            for skill_data in skills_practiced.values():
                skill_data["average_score"] = skill_data["total_score"] / skill_data["attempts"]
            
            return {
                "total_attempts": len(attempts),
                "average_score": round(avg_score, 1),
                "skills_practiced": [
                    {
                        "skill": skill,
                        **data,
                        "average_score": round(data["average_score"], 1)
                    }
                    for skill, data in skills_practiced.items()
                ],
                "recent_attempts": attempts[:5]
            }
            
        except Exception as e:
            print(f"[PRACTICE] Analytics failed: {e}")
            return {
                "total_attempts": 0,
                "average_score": 0,
                "skills_practiced": []
            }


# Global instance
practice_service = PracticeSetService()
