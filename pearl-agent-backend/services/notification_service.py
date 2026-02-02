"""
Notification Service
Smart notifications for module unlocks, progress, jobs, and AI guidance
"""
from typing import Dict, List, Optional
from datetime import datetime

try:
    from database import EnhancedSupabaseHelper
    db = EnhancedSupabaseHelper()
except:
    db = None


class NotificationService:
    """Manages user notifications"""
    
    NOTIFICATION_TYPES = {
        "module_unlock": {
            "icon": "🔓",
            "priority": "high",
            "category": "learning"
        },
        "checkpoint_ready": {
            "icon": "✅",
            "priority": "high",
            "category": "assessment"
        },
        "skill_mastery": {
            "icon": "🎯",
            "priority": "high",
            "category": "achievement"
        },
        "job_match": {
            "icon": "💼",
            "priority": "medium",
            "category": "jobs"
        },
        "streak_reminder": {
            "icon": "🔥",
            "priority": "medium",
            "category": "engagement"
        },
        "energy_restored": {
            "icon": "⚡",
            "priority": "low",
            "category": "rpg"
        },
        "level_up": {
            "icon": "🆙",
            "priority": "high",
            "category": "rpg"
        },
        "ai_tip": {
            "icon": "💡",
            "priority": "low",
            "category": "guidance"
        }
    }
    
    @staticmethod
    def create_notification(
        user_id: str,
        notification_type: str,
        title: str,
        message: str,
        action_url: Optional[str] = None,
        metadata: Optional[Dict] = None
    ) -> Dict:
        """Create a notification"""
        try:
            if not db:
                return {"success": False, "error": "Database not available"}
            
            if notification_type not in NotificationService.NOTIFICATION_TYPES:
                notification_type = "ai_tip"
            
            type_config = NotificationService.NOTIFICATION_TYPES[notification_type]
            
            notification_data = {
                'user_id': user_id,
                'notification_type': notification_type,
                'title': title,
                'message': message,
                'icon': type_config['icon'],
                'priority': type_config['priority'],
                'category': type_config['category'],
                'action_url': action_url,
                'metadata': metadata or {},
                'read': False,
                'created_at': datetime.now().isoformat()
            }
            
            result = db.client.table('user_notifications').insert(
                notification_data
            ).execute()
            
            return {
                "success": True,
                "notification_id": result.data[0]['id'] if result.data else None
            }
            
        except Exception as e:
            print(f"[NOTIFICATION] Create failed: {e}")
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def notify_module_unlock(user_id: str, skill: str, module_name: str, module_id: int) -> Dict:
        """Notify user of module unlock"""
        return NotificationService.create_notification(
            user_id=user_id,
            notification_type="module_unlock",
            title=f"New Module Unlocked! 🔓",
            message=f"You've unlocked: {module_name} in {skill}",
            action_url=f"/learning/module/{module_id}",
            metadata={"skill": skill, "module_id": module_id}
        )
    
    @staticmethod
    def notify_checkpoint_ready(user_id: str, skill: str, module_name: str) -> Dict:
        """Notify user checkpoint is ready"""
        return NotificationService.create_notification(
            user_id=user_id,
            notification_type="checkpoint_ready",
            title="Ready for Assessment ✅",
            message=f"Complete the checkpoint for {module_name}",
            action_url="/learning/checkpoint",
            metadata={"skill": skill, "module_name": module_name}
        )
    
    @staticmethod
    def notify_skill_mastery(user_id: str, skill: str, confidence: float) -> Dict:
        """Notify user of skill mastery"""
        return NotificationService.create_notification(
            user_id=user_id,
            notification_type="skill_mastery",
            title=f"Skill Mastered! 🎯",
            message=f"You've mastered {skill} ({int(confidence*100)}% confidence)",
            metadata={"skill": skill, "confidence": confidence}
        )
    
    @staticmethod
    def notify_job_match(user_id: str, job_title: str, match_percentage: float) -> Dict:
        """Notify user of job match"""
        return NotificationService.create_notification(
            user_id=user_id,
            notification_type="job_match",
            title="Job Match Found! 💼",
            message=f"{job_title} - {int(match_percentage)}% match",
            action_url="/jobs",
            metadata={"job_title": job_title, "match": match_percentage}
        )
    
    @staticmethod
    def notify_level_up(user_id: str, new_level: int, xp_earned: int) -> Dict:
        """Notify user of level up"""
        return NotificationService.create_notification(
            user_id=user_id,
            notification_type="level_up",
            title=f"Level Up! 🆙",
            message=f"You've reached Level {new_level}! (+{xp_earned} XP)",
            metadata={"level": new_level, "xp": xp_earned}
        )
    
    @staticmethod
    def send_ai_guidance(user_id: str, tip: str, context: str) -> Dict:
        """Send AI guidance tip"""
        return NotificationService.create_notification(
            user_id=user_id,
            notification_type="ai_tip",
            title="AI Tip 💡",
            message=tip,
            metadata={"context": context}
        )
    
    @staticmethod
    def get_user_notifications(
        user_id: str,
        unread_only: bool = False,
        limit: int = 20
    ) -> List[Dict]:
        """Get user notifications"""
        try:
            if not db:
                return []
            
            query = db.client.table('user_notifications').select('*').eq(
                'user_id', user_id
            )
            
            if unread_only:
                query = query.eq('read', False)
            
            result = query.order('created_at', desc=True).limit(limit).execute()
            
            return result.data if result.data else []
            
        except Exception as e:
            print(f"[NOTIFICATION] Get failed: {e}")
            return []
    
    @staticmethod
    def mark_as_read(notification_id: str) -> Dict:
        """Mark notification as read"""
        try:
            if not db:
                return {"success": False, "error": "Database not available"}
            
            db.client.table('user_notifications').update({
                'read': True,
                'read_at': datetime.now().isoformat()
            }).eq('id', notification_id).execute()
            
            return {"success": True}
            
        except Exception as e:
            print(f"[NOTIFICATION] Mark read failed: {e}")
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def get_notification_summary(user_id: str) -> Dict:
        """Get notification summary"""
        try:
            all_notifications = NotificationService.get_user_notifications(
                user_id, unread_only=False, limit=100
            )
            
            unread_count = len([n for n in all_notifications if not n.get('read', False)])
            
            # Group by category
            by_category = {}
            for notif in all_notifications:
                category = notif.get('category', 'other')
                if category not in by_category:
                    by_category[category] = []
                by_category[category].append(notif)
            
            return {
                "total_notifications": len(all_notifications),
                "unread_count": unread_count,
                "by_category": {cat: len(notifs) for cat, notifs in by_category.items()},
                "recent_unread": [n for n in all_notifications if not n.get('read', False)][:5]
            }
            
        except Exception as e:
            print(f"[NOTIFICATION] Summary failed: {e}")
            return {
                "total_notifications": 0,
                "unread_count": 0,
                "by_category": {}
            }


# Global instance
notification_service = NotificationService()
