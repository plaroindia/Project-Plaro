"""
Content Provider Service - FIXED
Manages content from database tables: courses, bytes, taikens
Provides structured learning paths from actual platform content
"""

from typing import List, Dict, Optional
from supabase import create_client
from config import get_settings

settings = get_settings()


class ContentProviderService:
    """
    Manages platform content from database
    Queries: courses, bytes, taikens tables
    """
    
    def __init__(self):
        self.client = create_client(settings.SUPABASE_URL, settings.SUPABASE_KEY)
    
    def get_content_for_skill(
        self,
        skill: str,
        content_type: Optional[str] = None,
        difficulty: Optional[str] = None,
        limit: int = 10
    ) -> List[Dict]:
        """
        Retrieve content for a skill from database
        
        Args:
            skill: Skill name (searches in domain/category)
            content_type: Filter by type ('video', 'task', 'text')
            difficulty: Filter by difficulty
            limit: Maximum results
        
        Returns:
            List of content items from database
        """
        
        try:
            all_content = []
            
            # Search bytes (short videos)
            if not content_type or content_type == 'video':
                bytes_query = self.client.table('bytes').select('*').eq('domain', skill)
                
                if difficulty:
                    bytes_query = bytes_query.eq('difficulty', difficulty)
                
                bytes_result = bytes_query.order('educational_value', desc=True).limit(limit).execute()
                
                for byte in bytes_result.data or []:
                    all_content.append({
                        "provider_id": f"byte_{byte['byte_id']}",
                        "name": "PEARL Byte",
                        "content_type": "video",
                        "title": byte.get('caption', 'Learning Byte'),
                        "difficulty": byte.get('difficulty', 'beginner'),
                        "duration": 5,  # Bytes are short
                        "source_url": byte.get('byte'),
                        "content_id": byte['byte_id'],
                        "metadata": {
                            "likes": byte.get('like_count', 0),
                            "educational_value": byte.get('educational_value', 0.5),
                            "creator_id": byte.get('user_id')
                        }
                    })
            
            # Search courses
            if not content_type or content_type == 'course':
                courses_query = self.client.table('courses').select('*, course_videos(count)').eq('domain', skill)
                
                if difficulty:
                    courses_query = courses_query.eq('difficulty', difficulty)
                
                courses_result = courses_query.order('created_at', desc=True).limit(limit).execute()
                
                for course in courses_result.data or []:
                    all_content.append({
                        "provider_id": f"course_{course['course_id']}",
                        "name": "PEARL Course",
                        "content_type": "course",
                        "title": course.get('title'),
                        "difficulty": course.get('difficulty', 'intermediate'),
                        "duration": 60,  # Estimate
                        "source_url": f"/courses/{course['course_id']}",
                        "content_id": course['course_id'],
                        "metadata": {
                            "description": course.get('description'),
                            "category": course.get('category'),
                            "creator_id": course.get('user_id'),
                            "thumbnail": course.get('thumbnail_url')
                        }
                    })
            
            # Search taikens (interactive experiences)
            if not content_type or content_type == 'taiken':
                taikens_query = self.client.table('taikens').select('*').eq('domain', skill).eq('is_published', True)
                
                if difficulty:
                    taikens_query = taikens_query.eq('difficulty', difficulty)
                
                taikens_result = taikens_query.order('average_rating', desc=True).limit(limit).execute()
                
                for taiken in taikens_result.data or []:
                    all_content.append({
                        "provider_id": f"taiken_{taiken['taiken_id']}",
                        "name": "PEARL Taiken",
                        "content_type": "taiken",
                        "title": taiken.get('title'),
                        "difficulty": taiken.get('difficulty'),
                        "duration": taiken.get('total_stages', 1) * 10,  # ~10 min per stage
                        "source_url": f"/taikens/{taiken['taiken_id']}",
                        "content_id": taiken['taiken_id'],
                        "metadata": {
                            "description": taiken.get('description'),
                            "stages": taiken.get('total_stages'),
                            "questions": taiken.get('total_questions'),
                            "rating": taiken.get('average_rating', 0),
                            "plays": taiken.get('play_count', 0)
                        }
                    })
            
            # Search posts (text/articles)
            if not content_type or content_type == 'text':
                posts_query = self.client.table('post').select('*').eq('domain', skill).eq('is_published', True).eq('is_hidden', False)
                
                if difficulty:
                    posts_query = posts_query.eq('difficulty', difficulty)
                
                posts_result = posts_query.order('educational_value', desc=True).limit(limit).execute()
                
                for post in posts_result.data or []:
                    all_content.append({
                        "provider_id": f"post_{post['post_id']}",
                        "name": "PEARL Article",
                        "content_type": "text",
                        "title": post.get('title', 'Learning Article'),
                        "difficulty": post.get('difficulty', 'beginner'),
                        "duration": 15,  # Reading time estimate
                        "source_url": f"/posts/{post['post_id']}",
                        "content_id": post['post_id'],
                        "metadata": {
                            "content": post.get('content'),
                            "tags": post.get('tags', []),
                            "likes": post.get('like_count', 0),
                            "educational_value": post.get('educational_value', 0.5)
                        }
                    })
            
            print(f"[CONTENT] 📚 Found {len(all_content)} resources for {skill} from database")
            return all_content[:limit]
        
        except Exception as e:
            print(f"[CONTENT] ERROR: Failed to get content for {skill}: {e}")
            return []
    
    def get_mixed_learning_path(
        self,
        skill: str,
        learning_preference: str = "mixed"
    ) -> List[Dict]:
        """
        Create a balanced content mix based on user's learning preference
        
        Args:
            skill: Skill to learn
            learning_preference: 'video', 'reading', 'hands_on', or 'mixed'
        
        Returns:
            List of content items optimized for the preference
        """
        
        # Preference weight mappings
        weights = {
            "video": {"video": 2, "course": 1, "taiken": 1, "text": 0},
            "reading": {"text": 2, "course": 1, "video": 1, "taiken": 0},
            "hands_on": {"taiken": 3, "course": 1, "video": 1, "text": 0},
            "mixed": {"video": 1, "course": 1, "taiken": 1, "text": 1}
        }
        
        pref_weights = weights.get(learning_preference, weights["mixed"])
        
        content = []
        
        # Get content based on weights
        for content_type, weight in pref_weights.items():
            if weight > 0:
                items = self.get_content_for_skill(
                    skill, 
                    content_type=content_type,
                    limit=weight * 2  # Get more than needed
                )
                content.extend(items[:weight])
        
        print(f"[CONTENT] 🎯 Created {learning_preference} learning path with {len(content)} items for {skill}")
        return content
    
    def get_learning_roadmap(
        self,
        primary_skill: str,
        secondary_skills: List[str],
        learning_preference: str = "mixed"
    ) -> Dict:
        """
        Create a comprehensive learning roadmap for multiple related skills
        """
        
        roadmap = {
            "primary_skill": primary_skill,
            "phases": []
        }
        
        # Phase 1: Primary skill fundamentals
        phase1_content = self.get_mixed_learning_path(primary_skill, learning_preference)
        
        if phase1_content:
            roadmap["phases"].append({
                "phase": 1,
                "title": f"Master {primary_skill}",
                "duration_weeks": 4,
                "content": phase1_content[:5],
                "focus": "fundamentals"
            })
        
        # Phase 2: Secondary skills
        if secondary_skills:
            phase2_content = []
            for skill in secondary_skills[:2]:
                items = self.get_content_for_skill(skill, limit=3)
                phase2_content.extend(items)
            
            if phase2_content:
                roadmap["phases"].append({
                    "phase": 2,
                    "title": f"Build Supporting Skills: {', '.join(secondary_skills[:2])}",
                    "duration_weeks": 3,
                    "content": phase2_content[:4],
                    "focus": "supporting"
                })
        
        # Phase 3: Advanced practice
        phase3_content = self.get_content_for_skill(
            primary_skill, 
            content_type="taiken",
            difficulty="advanced",
            limit=3
        )
        
        if phase3_content:
            roadmap["phases"].append({
                "phase": 3,
                "title": f"Advanced {primary_skill} & Real Projects",
                "duration_weeks": 3,
                "content": phase3_content,
                "focus": "advanced"
            })
        
        roadmap["total_duration_weeks"] = sum(p.get("duration_weeks", 0) for p in roadmap["phases"])
        roadmap["estimated_hours"] = len([c for p in roadmap["phases"] for c in p.get("content", [])]) * 30
        
        print(f"[CONTENT] 🗺️ Created learning roadmap for {primary_skill} with {len(roadmap['phases'])} phases")
        return roadmap
    
    def search_content(self, query: str, limit: int = 20) -> List[Dict]:
        """
        Search across all content types
        """
        try:
            results = []
            
            # Search bytes
            bytes_result = self.client.table('bytes').select('*').ilike('caption', f'%{query}%').limit(limit).execute()
            for byte in bytes_result.data or []:
                results.append({
                    "type": "byte",
                    "id": byte['byte_id'],
                    "title": byte.get('caption'),
                    "url": byte.get('byte'),
                    "domain": byte.get('domain')
                })
            
            # Search courses
            courses_result = self.client.table('courses').select('*').or_(
                f'title.ilike.%{query}%,description.ilike.%{query}%'
            ).limit(limit).execute()
            for course in courses_result.data or []:
                results.append({
                    "type": "course",
                    "id": course['course_id'],
                    "title": course.get('title'),
                    "url": f"/courses/{course['course_id']}",
                    "domain": course.get('domain')
                })
            
            # Search taikens
            taikens_result = self.client.table('taikens').select('*').or_(
                f'title.ilike.%{query}%,description.ilike.%{query}%'
            ).eq('is_published', True).limit(limit).execute()
            for taiken in taikens_result.data or []:
                results.append({
                    "type": "taiken",
                    "id": taiken['taiken_id'],
                    "title": taiken.get('title'),
                    "url": f"/taikens/{taiken['taiken_id']}",
                    "domain": taiken.get('domain')
                })
            
            # Search posts
            posts_result = self.client.table('post').select('*').or_(
                f'title.ilike.%{query}%,content.ilike.%{query}%'
            ).eq('is_published', True).limit(limit).execute()
            for post in posts_result.data or []:
                results.append({
                    "type": "post",
                    "id": post['post_id'],
                    "title": post.get('title'),
                    "url": f"/posts/{post['post_id']}",
                    "domain": post.get('domain')
                })
            
            return results[:limit]
            
        except Exception as e:
            print(f"[CONTENT] Search error: {e}")
            return []


# Global instance
content_provider = ContentProviderService()