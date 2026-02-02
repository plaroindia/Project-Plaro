"""
Feedback Service
User reviews, ratings, and improvement suggestions
"""
from typing import Dict, List, Optional
from datetime import datetime

try:
    from database import EnhancedSupabaseHelper
    db = EnhancedSupabaseHelper()
except:
    db = None


class FeedbackService:
    """Handles user feedback and reviews"""
    
    @staticmethod
    def submit_module_feedback(
        user_id: str,
        module_id: str,
        skill: str,
        rating: int,
        feedback_text: Optional[str] = None,
        tags: Optional[List[str]] = None
    ) -> Dict:
        """Submit feedback for a module"""
        try:
            if rating < 1 or rating > 5:
                return {
                    "success": False,
                    "error": "Rating must be between 1 and 5"
                }
            
            if not db:
                return {"success": False, "error": "Database not available"}
            
            feedback_data = {
                'user_id': user_id,
                'module_id': module_id,
                'skill': skill,
                'rating': rating,
                'feedback_text': feedback_text,
                'tags': tags or [],
                'feedback_type': 'module',
                'submitted_at': datetime.now().isoformat()
            }
            
            result = db.client.table('user_feedback').insert(feedback_data).execute()
            
            return {
                "success": True,
                "feedback_id": result.data[0]['id'] if result.data else None,
                "message": "Thank you for your feedback!"
            }
            
        except Exception as e:
            print(f"[FEEDBACK] Submit failed: {e}")
            return {
                "success": False,
                "error": str(e)
            }
    
    @staticmethod
    def submit_course_feedback(
        user_id: str,
        course_id: str,
        rating: int,
        usefulness_rating: int,
        feedback_text: Optional[str] = None
    ) -> Dict:
        """Submit feedback for a course"""
        try:
            if not db:
                return {"success": False, "error": "Database not available"}
            
            feedback_data = {
                'user_id': user_id,
                'course_id': course_id,
                'rating': rating,
                'usefulness_rating': usefulness_rating,
                'feedback_text': feedback_text,
                'feedback_type': 'course',
                'submitted_at': datetime.now().isoformat()
            }
            
            result = db.client.table('user_feedback').insert(feedback_data).execute()
            
            return {
                "success": True,
                "feedback_id": result.data[0]['id'] if result.data else None
            }
            
        except Exception as e:
            print(f"[FEEDBACK] Course feedback failed: {e}")
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def submit_improvement_suggestion(
        user_id: str,
        suggestion_type: str,
        suggestion_text: str,
        priority: str = "medium"
    ) -> Dict:
        """Submit improvement suggestion"""
        try:
            if not db:
                return {"success": False, "error": "Database not available"}
            
            suggestion_data = {
                'user_id': user_id,
                'suggestion_type': suggestion_type,
                'suggestion_text': suggestion_text,
                'priority': priority,
                'status': 'submitted',
                'submitted_at': datetime.now().isoformat()
            }
            
            result = db.client.table('improvement_suggestions').insert(
                suggestion_data
            ).execute()
            
            return {
                "success": True,
                "suggestion_id": result.data[0]['id'] if result.data else None,
                "message": "Your suggestion has been recorded. Thank you!"
            }
            
        except Exception as e:
            print(f"[FEEDBACK] Suggestion failed: {e}")
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def get_module_ratings(module_id: str) -> Dict:
        """Get aggregated ratings for a module"""
        try:
            if not db:
                return {
                    "module_id": module_id,
                    "average_rating": 0,
                    "total_ratings": 0
                }
            
            feedback = db.client.table('user_feedback').select('rating').eq(
                'module_id', module_id
            ).eq('feedback_type', 'module').execute()
            
            if not feedback.data:
                return {
                    "module_id": module_id,
                    "average_rating": 0,
                    "total_ratings": 0
                }
            
            ratings = [f['rating'] for f in feedback.data]
            average = sum(ratings) / len(ratings)
            
            return {
                "module_id": module_id,
                "average_rating": round(average, 2),
                "total_ratings": len(ratings),
                "rating_distribution": {
                    "5_star": ratings.count(5),
                    "4_star": ratings.count(4),
                    "3_star": ratings.count(3),
                    "2_star": ratings.count(2),
                    "1_star": ratings.count(1)
                }
            }
            
        except Exception as e:
            print(f"[FEEDBACK] Get ratings failed: {e}")
            return {
                "module_id": module_id,
                "average_rating": 0,
                "total_ratings": 0
            }
    
    @staticmethod
    def get_user_feedback_history(user_id: str) -> List[Dict]:
        """Get user's feedback history"""
        try:
            if not db:
                return []
            
            feedback = db.client.table('user_feedback').select('*').eq(
                'user_id', user_id
            ).order('submitted_at', desc=True).execute()
            
            return feedback.data if feedback.data else []
            
        except Exception as e:
            print(f"[FEEDBACK] History fetch failed: {e}")
            return []
    
    @staticmethod
    def get_popular_tags() -> Dict:
        """Get most common feedback tags"""
        try:
            if not db:
                return {"tags": {}}
            
            feedback = db.client.table('user_feedback').select('tags').execute()
            
            if not feedback.data:
                return {"tags": {}}
            
            tag_counts = {}
            for f in feedback.data:
                tags = f.get('tags', [])
                for tag in tags:
                    tag_counts[tag] = tag_counts.get(tag, 0) + 1
            
            sorted_tags = sorted(tag_counts.items(), key=lambda x: x[1], reverse=True)
            
            return {
                "tags": dict(sorted_tags[:20]),
                "most_common": sorted_tags[0][0] if sorted_tags else None
            }
            
        except Exception as e:
            print(f"[FEEDBACK] Tags fetch failed: {e}")
            return {"tags": {}}


# Global instance
feedback_service = FeedbackService()
