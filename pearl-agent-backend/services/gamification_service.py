"""
Gamification Service - FIXED
Handles points, streaks, achievements with proper database integration
Uses: plaro_transactions, user_profile_rank, user_profiles
"""
from typing import Dict, List, Optional
from datetime import datetime, timedelta
from supabase import create_client
from config import get_settings
import json

settings = get_settings()


class GamificationService:
    """Handles all gamification features with database persistence"""
    
    def __init__(self):
        self.client = create_client(settings.SUPABASE_URL, settings.SUPABASE_KEY)
    
    # Achievement definitions (could be moved to database table later)
    ACHIEVEMENTS = {
        "first_module": {
            "title": "First Step",
            "description": "Complete your first learning module",
            "points": 100,
            "icon": "🥇"
        },
        "week_streak": {
            "title": "Week Warrior",
            "description": "Maintain a 7-day learning streak",
            "points": 250,
            "icon": "🔥"
        },
        "skill_master": {
            "title": "Skill Master",
            "description": "Reach 80% confidence in any skill",
            "points": 300,
            "icon": "🎯"
        },
        "first_post": {
            "title": "Voice Heard",
            "description": "Create your first post",
            "points": 50,
            "icon": "📢"
        },
        "taiken_creator": {
            "title": "Experience Creator",
            "description": "Create your first Taiken",
            "points": 500,
            "icon": "🎮"
        },
        "first_follower": {
            "title": "Making Connections",
            "description": "Get your first follower",
            "points": 100,
            "icon": "👥"
        },
        "community_helper": {
            "title": "Community Helper",
            "description": "Help 10 other learners",
            "points": 400,
            "icon": "🤝"
        },
        "roadmap_complete": {
            "title": "Journey Complete",
            "description": "Complete a full learning roadmap",
            "points": 1000,
            "icon": "🏆"
        },
        "freelance_ready": {
            "title": "Freelance Ready",
            "description": "Become eligible for freelance work",
            "points": 1500,
            "icon": "💼"
        }
    }
    
    def award_plaro_points(
        self,
        user_id: str,
        source: str,
        points: int,
        related_content_type: Optional[str] = None,
        related_content_id: Optional[str] = None,
        session_id: Optional[str] = None,
        reason: Optional[str] = None,
        metadata: Optional[Dict] = None
    ) -> bool:
        """Award Plaro points to user and update rank"""
        try:
            # Parse content_id (could be UUID or int)
            content_id_uuid = None
            content_id_int = None
            
            if related_content_id:
                try:
                    content_id_int = int(related_content_id)
                except:
                    content_id_uuid = related_content_id
            
            # Create transaction
            transaction = {
                "user_id": user_id,
                "source": source,
                "points": points,
                "related_content_type": related_content_type,
                "related_content_id_uuid": content_id_uuid,
                "related_content_id_int": content_id_int,
                "session_id": session_id,
                "reason": reason,
                "metadata": metadata or {}
            }
            
            self.client.table('plaro_transactions').insert(transaction).execute()
            
            # Update user_profile_rank
            self._update_user_rank(user_id, points)
            
            print(f"[GAMIFICATION] ✅ Awarded {points} points to {user_id} ({source})")
            return True
            
        except Exception as e:
            print(f"[GAMIFICATION ERROR] Award points failed: {e}")
            return False
    
    def _update_user_rank(self, user_id: str, points_delta: int):
        """Update user rank and check for level ups"""
        try:
            # Get current rank
            rank_result = self.client.table('user_profile_rank').select('*').eq(
                'user_id', user_id
            ).single().execute()
            
            if not rank_result.data:
                # Create initial rank
                self.client.table('user_profile_rank').insert({
                    "user_id": user_id,
                    "total_points": points_delta,
                    "rank_level": "beginner"
                }).execute()
                return
            
            current_rank = rank_result.data
            new_total = current_rank.get('total_points', 0) + points_delta
            
            # Determine new rank level
            new_rank_level = self._calculate_rank_level(new_total)
            
            # Update rank history if level changed
            rank_history = current_rank.get('rank_history', [])
            if new_rank_level != current_rank.get('rank_level'):
                rank_history.append({
                    "from": current_rank.get('rank_level'),
                    "to": new_rank_level,
                    "at": datetime.now().isoformat(),
                    "points": new_total
                })
            
            # Update rank
            self.client.table('user_profile_rank').update({
                "total_points": new_total,
                "rank_level": new_rank_level,
                "rank_history": rank_history,
                "last_updated": datetime.now().isoformat()
            }).eq('user_id', user_id).execute()
            
            if new_rank_level != current_rank.get('rank_level'):
                print(f"[GAMIFICATION] 🎉 User {user_id} leveled up to {new_rank_level}!")
            
        except Exception as e:
            print(f"[GAMIFICATION ERROR] Update rank failed: {e}")
    
    def _calculate_rank_level(self, total_points: int) -> str:
        """Calculate rank level from points"""
        if total_points < 1000:
            return "beginner"
        elif total_points < 5000:
            return "intermediate"
        elif total_points < 15000:
            return "advanced"
        elif total_points < 30000:
            return "expert"
        else:
            return "master"
    
    def award_achievement(self, user_id: str, achievement_key: str, 
                         metadata: Optional[Dict] = None) -> bool:
        """Award achievement to user"""
        if achievement_key not in self.ACHIEVEMENTS:
            print(f"[GAMIFICATION] Unknown achievement: {achievement_key}")
            return False
        
        achievement = self.ACHIEVEMENTS[achievement_key]
        
        try:
            # Check if already earned (check in transactions)
            existing = self.client.table('plaro_transactions').select('id').eq(
                'user_id', user_id
            ).eq('source', 'achievement').eq('reason', f"Achievement: {achievement['title']}").execute()
            
            if existing.data:
                print(f"[GAMIFICATION] Achievement {achievement_key} already earned")
                return False
            
            # Award points
            self.award_plaro_points(
                user_id=user_id,
                source='achievement',
                points=achievement['points'],
                related_content_type='achievement',
                reason=f"Achievement: {achievement['title']}",
                metadata={
                    "achievement_key": achievement_key,
                    "description": achievement['description'],
                    "icon": achievement['icon'],
                    **(metadata or {})
                }
            )
            
            print(f"[GAMIFICATION] 🏆 Awarded {achievement['title']} to {user_id}")
            return True
            
        except Exception as e:
            print(f"[GAMIFICATION ERROR] Award achievement failed: {e}")
            return False
    
    def check_learning_achievements(self, user_id: str) -> List[str]:
        """Check and award learning-related achievements"""
        awarded = []
        
        try:
            # Check first module
            module_progress = self.client.table('ai_module_progress').select('*').eq(
                'user_id', user_id
            ).eq('status', 'completed').execute()
            
            if module_progress.data and len(module_progress.data) >= 1:
                if self.award_achievement(user_id, "first_module"):
                    awarded.append("first_module")
            
            # Check streak
            profile = self.client.table('user_profiles').select('streak_count').eq(
                'user_id', user_id
            ).single().execute()
            
            if profile.data and profile.data.get('streak_count', 0) >= 7:
                if self.award_achievement(user_id, "week_streak"):
                    awarded.append("week_streak")
            
            # Check skill mastery
            skills = self.client.table('user_skill_memory').select('*').eq(
                'user_id', user_id
            ).gte('confidence_score', 0.8).execute()
            
            if skills.data:
                if self.award_achievement(user_id, "skill_master", 
                                         {"skill": skills.data[0].get('skill_name')}):
                    awarded.append("skill_master")
            
            return awarded
            
        except Exception as e:
            print(f"[GAMIFICATION ERROR] Check achievements failed: {e}")
            return []
    
    def get_leaderboard(self, limit: int = 20) -> List[Dict]:
        """Get leaderboard of top users"""
        try:
            # Join user_profile_rank with user_profiles
            response = self.client.table('user_profile_rank').select(
                'user_id, total_points, rank_level, user_profiles(username, profile_pic)'
            ).order('total_points', desc=True).limit(limit).execute()
            
            leaderboard = []
            for rank, entry in enumerate(response.data or [], 1):
                profile = entry.get('user_profiles', {})
                leaderboard.append({
                    'rank': rank,
                    'user_id': entry['user_id'],
                    'username': profile.get('username', 'Anonymous') if profile else 'Anonymous',
                    'points': entry.get('total_points', 0),
                    'rank_level': entry.get('rank_level', 'beginner'),
                    'profile_pic': profile.get('profile_pic') if profile else None
                })
            
            return leaderboard
            
        except Exception as e:
            print(f"[GAMIFICATION ERROR] Get leaderboard failed: {e}")
            return []
    
    def get_user_plaro_points(self, user_id: str) -> Dict:
        """Get user's Plaro points summary"""
        try:
            # Get total from rank
            rank = self.client.table('user_profile_rank').select('*').eq(
                'user_id', user_id
            ).single().execute()
            
            # Get recent transactions
            transactions = self.client.table('plaro_transactions').select('*').eq(
                'user_id', user_id
            ).order('created_at', desc=True).limit(10).execute()
            
            # Get breakdown by source
            all_transactions = self.client.table('plaro_transactions').select('source, points').eq(
                'user_id', user_id
            ).execute()
            
            breakdown = {}
            for txn in all_transactions.data or []:
                source = txn.get('source', 'other')
                breakdown[source] = breakdown.get(source, 0) + txn.get('points', 0)
            
            return {
                "total_points": rank.data.get('total_points', 0) if rank.data else 0,
                "rank_level": rank.data.get('rank_level', 'beginner') if rank.data else 'beginner',
                "recent_transactions": transactions.data or [],
                "breakdown": breakdown
            }
            
        except Exception as e:
            print(f"[GAMIFICATION ERROR] Get points failed: {e}")
            return {
                "total_points": 0,
                "rank_level": "beginner",
                "recent_transactions": [],
                "breakdown": {}
            }
    
    def update_streak(self, user_id: str) -> bool:
        """Update user's learning streak"""
        try:
            profile = self.client.table('user_profiles').select('streak_count, updated_at').eq(
                'user_id', user_id
            ).single().execute()
            
            if not profile.data:
                return False
            
            current_streak = profile.data.get('streak_count', 0)
            last_update = profile.data.get('updated_at')
            
            if last_update:
                last_update_date = datetime.fromisoformat(last_update.replace('Z', '+00:00')).date()
                today = datetime.now().date()
                days_diff = (today - last_update_date).days
                
                if days_diff == 1:
                    # Continue streak
                    new_streak = current_streak + 1
                elif days_diff > 1:
                    # Streak broken, reset
                    new_streak = 1
                else:
                    # Same day, no change
                    return True
            else:
                new_streak = 1
            
            # Update profile
            self.client.table('user_profiles').update({
                'streak_count': new_streak,
                'updated_at': datetime.now().isoformat()
            }).eq('user_id', user_id).execute()
            
            print(f"[GAMIFICATION] 🔥 Streak updated: {new_streak} days for {user_id}")
            return True
            
        except Exception as e:
            print(f"[GAMIFICATION ERROR] Update streak failed: {e}")
            return False
    
    def get_user_gamification_summary(self, user_id: str) -> Dict:
        """Get complete gamification summary for user"""
        try:
            # Get points summary
            points_summary = self.get_user_plaro_points(user_id)
            
            # Get streak
            profile = self.client.table('user_profiles').select('streak_count').eq(
                'user_id', user_id
            ).single().execute()
            streak = profile.data.get('streak_count', 0) if profile.data else 0
            
            # Calculate daily progress
            today = datetime.now().date()
            today_start = datetime.combine(today, datetime.min.time())
            
            today_events = self.client.table('user_content_events').select('*').eq(
                'user_id', user_id
            ).gte('created_at', today_start.isoformat()).execute()
            
            daily_tasks = {
                'complete_module': len([e for e in (today_events.data or []) 
                                      if e.get('event_type') == 'complete' 
                                      and e.get('content_type') == 'module']) > 0,
                'practice_skill': len([e for e in (today_events.data or []) 
                                     if e.get('event_type') == 'practice_submit']) > 0,
                'engage_content': len([e for e in (today_events.data or []) 
                                     if e.get('event_type') in ['like', 'comment', 'share']]) > 0
            }
            
            daily_progress = sum(1 for completed in daily_tasks.values() if completed)
            
            # Get leaderboard position
            leaderboard_pos = self._get_user_leaderboard_position(user_id)
            
            return {
                'points_summary': points_summary,
                'streak': streak,
                'daily_challenge': {
                    'progress': daily_progress,
                    'total': 3,
                    'percentage': (daily_progress / 3) * 100,
                    'tasks': daily_tasks
                },
                'leaderboard_position': leaderboard_pos
            }
            
        except Exception as e:
            print(f"[GAMIFICATION ERROR] Get summary failed: {e}")
            return {}
    
    def _get_user_leaderboard_position(self, user_id: str) -> Optional[int]:
        """Get user's position on leaderboard"""
        try:
            leaderboard = self.get_leaderboard(limit=100)
            for i, entry in enumerate(leaderboard, 1):
                if entry['user_id'] == user_id:
                    return i
            return None
        except:
            return None


# Global instance
gamification_service = GamificationService()