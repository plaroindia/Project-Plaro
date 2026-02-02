"""
Complete Database Helper with all schema support
"""
from supabase import create_client, Client
from config import get_settings
from typing import Optional, Dict, List, Any
from datetime import datetime, timedelta
from functools import lru_cache
import json
import uuid

settings = get_settings()


@lru_cache()
def get_supabase() -> Client:
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_KEY)


class EnhancedSupabaseHelper:
    """Complete database operations for all tables"""
    
    def __init__(self):
        self.client = get_supabase()
    
    # ========== USERS & AUTH ==========
    
    def get_user_profile(self, user_id: str) -> Optional[Dict]:
        """Get user profile with full details"""
        try:
            response = self.client.table('user_profiles').select('*').eq(
                'user_id', user_id
            ).single().execute()
            return response.data
        except Exception as e:
            print(f"[DB] User profile not found: {e}")
            return None
    
    def update_user_profile(self, user_id: str, updates: Dict) -> bool:
        """Update user profile"""
        try:
            updates['updated_at'] = datetime.now().isoformat()
            response = self.client.table('user_profiles').update(updates).eq(
                'user_id', user_id
            ).execute()
            return bool(response.data)
        except Exception as e:
            print(f"[DB ERROR] Update profile failed: {e}")
            return False
    
    def update_streak(self, user_id: str) -> bool:
        """Update user streak count"""
        try:
            profile = self.get_user_profile(user_id)
            if not profile:
                return False
            
            last_updated = profile.get('updated_at')
            current_streak = profile.get('streak_count', 0)
            
            if last_updated:
                last_date = datetime.fromisoformat(last_updated.replace('Z', '+00:00')).date()
                today = datetime.now().date()
                
                if (today - last_date).days == 1:
                    # Consecutive day
                    new_streak = current_streak + 1
                elif (today - last_date).days == 0:
                    # Same day
                    new_streak = current_streak
                else:
                    # Streak broken
                    new_streak = 1
            else:
                new_streak = 1
            
            response = self.client.table('user_profiles').update({
                'streak_count': new_streak,
                'updated_at': datetime.now().isoformat()
            }).eq('user_id', user_id).execute()
            
            return bool(response.data)
        except Exception as e:
            print(f"[DB ERROR] Update streak failed: {e}")
            return False
    
    # ========== ONBOARDING ==========
    
    def get_onboarding_data(self, user_id: str) -> Optional[Dict]:
        """Get user onboarding data"""
        try:
            response = self.client.table('user_onboarding').select('*').eq(
                'user_id', user_id
            ).single().execute()
            return response.data
        except Exception as e:
            print(f"[DB] Onboarding not found: {e}")
            return None
    
    def save_onboarding(self, user_id: str, onboarding_data: Dict) -> bool:
        """Save onboarding data"""
        try:
            onboarding_data['user_id'] = user_id
            onboarding_data['completed_at'] = datetime.now().isoformat()
            onboarding_data['created_at'] = datetime.now().isoformat()
            onboarding_data['updated_at'] = datetime.now().isoformat()
            
            # Validate skills JSON
            if 'skills' in onboarding_data and isinstance(onboarding_data['skills'], list):
                onboarding_data['skills'] = json.dumps([
                    {'skill': s, 'confidence': 0.0} 
                    for s in onboarding_data['skills']
                ])
            
            response = self.client.table('user_onboarding').upsert(
                onboarding_data
            ).execute()
            
            # Mark profile as onboarded
            if response.data:
                self.client.table('user_profiles').update({
                    'onboarding_complete': True
                }).eq('user_id', user_id).execute()
            
            return bool(response.data)
        except Exception as e:
            print(f"[DB ERROR] Save onboarding failed: {e}")
            return False
    
    # ========== SKILL MANAGEMENT ==========
    
    def get_user_skills(self, user_id: str) -> List[Dict]:
        """Get all user skills with confidence"""
        try:
            response = self.client.table('user_skill_memory').select('*').eq(
                'user_id', user_id
            ).order('confidence_score', desc=True).execute()
            return response.data if response.data else []
        except Exception as e:
            print(f"[DB ERROR] Get skills failed: {e}")
            return []
    
    def update_skill_confidence(self, user_id: str, skill_name: str, 
                               confidence_delta: float = 0.1) -> bool:
        """Update skill confidence"""
        try:
            # Get existing skill
            response = self.client.table('user_skill_memory').select('*').eq(
                'user_id', user_id
            ).eq('skill_name', skill_name).execute()
            
            if response.data:
                # Update existing
                current_conf = float(response.data[0].get('confidence_score', 0.0))
                new_conf = min(1.0, current_conf + confidence_delta)
                
                update_response = self.client.table('user_skill_memory').update({
                    'confidence_score': new_conf,
                    'practice_count': response.data[0].get('practice_count', 0) + 1,
                    'last_practiced_at': datetime.now().isoformat(),
                    'updated_at': datetime.now().isoformat()
                }).eq('id', response.data[0]['id']).execute()
            else:
                # Create new
                update_response = self.client.table('user_skill_memory').insert({
                    'user_id': user_id,
                    'skill_name': skill_name,
                    'confidence_score': min(1.0, confidence_delta),
                    'practice_count': 1,
                    'last_practiced_at': datetime.now().isoformat(),
                    'created_at': datetime.now().isoformat()
                }).execute()
            
            return bool(update_response.data)
        except Exception as e:
            print(f"[DB ERROR] Update skill failed: {e}")
            return False
    
    def get_skill_progress_summary(self, user_id: str) -> Dict:
        """Get skill progress summary"""
        skills = self.get_user_skills(user_id)
        
        summary = {
            'total_skills': len(skills),
            'mastered_skills': len([s for s in skills if s.get('confidence_score', 0) >= 0.8]),
            'intermediate_skills': len([s for s in skills if 0.5 <= s.get('confidence_score', 0) < 0.8]),
            'beginner_skills': len([s for s in skills if s.get('confidence_score', 0) < 0.5]),
            'recently_practiced': [],
            'skills_by_domain': {}
        }
        
        # Get recent practices
        if skills:
            sorted_by_recency = sorted(
                skills, 
                key=lambda x: x.get('last_practiced_at', ''), 
                reverse=True
            )
            summary['recently_practiced'] = sorted_by_recency[:5]
        
        return summary
    
    # ========== SESSIONS & PROGRESS ==========
    
    def create_agent_session(self, user_id: str, jd_text: str, 
                            onboarding_id: Optional[str] = None) -> Optional[Dict]:
        """Create AI agent session"""
        try:
            session_data = {
                'user_id': user_id,
                'jd_text': jd_text,
                'session_type': 'career_guidance',
                'status': 'active',
                'created_at': datetime.now().isoformat(),
                'updated_at': datetime.now().isoformat()
            }
            
            if onboarding_id:
                session_data['onboarding_id'] = onboarding_id
            
            response = self.client.table('ai_agent_sessions').insert(
                session_data
            ).execute()
            
            return response.data[0] if response.data else None
        except Exception as e:
            print(f"[DB ERROR] Create session failed: {e}")
            return None
    
    def get_active_sessions(self, user_id: str) -> List[Dict]:
        """Get active AI sessions for user"""
        try:
            response = self.client.table('ai_agent_sessions').select('*').eq(
                'user_id', user_id
            ).eq('status', 'active').order('created_at', desc=True).execute()
            return response.data if response.data else []
        except Exception as e:
            print(f"[DB ERROR] Get sessions failed: {e}")
            return []
    
    def update_session_parsed_data(self, session_id: str, parsed_data: Dict) -> bool:
        """Update session with parsed JD data"""
        try:
            response = self.client.table('ai_agent_sessions').update({
                'jd_parsed': parsed_data,
                'updated_at': datetime.now().isoformat()
            }).eq('id', session_id).execute()
            return bool(response.data)
        except Exception as e:
            print(f"[DB ERROR] Update session failed: {e}")
            return False
    
    # ========== MODULE PROGRESS ==========
    
    def save_module_progress(self, user_id: str, session_id: str, skill: str, 
                            module_id: int, status: str, 
                            module_data: Optional[Dict] = None) -> Optional[str]:
        """Save module progress"""
        try:
            progress_data = {
                'user_id': user_id,
                'session_id': session_id,
                'skill': skill,
                'module_id': module_id,
                'status': status,
                'updated_at': datetime.now().isoformat()
            }
            
            if status == 'active':
                progress_data['started_at'] = datetime.now().isoformat()
            elif status == 'completed':
                progress_data['completed_at'] = datetime.now().isoformat()
            
            if module_data:
                progress_data['module_name'] = module_data.get('name')
                progress_data['cached_completion_data'] = {
                    'actions': module_data.get('actions', []),
                    'completed_at': datetime.now().isoformat()
                }
                progress_data['last_cache_update'] = datetime.now().isoformat()
            
            # Check if exists
            existing = self.client.table('ai_module_progress').select('*').eq(
                'session_id', session_id
            ).eq('skill', skill).eq('module_id', module_id).execute()
            
            if existing.data:
                # Update
                response = self.client.table('ai_module_progress').update(
                    progress_data
                ).eq('id', existing.data[0]['id']).execute()
                progress_id = existing.data[0]['id']
            else:
                # Create
                response = self.client.table('ai_module_progress').insert(
                    progress_data
                ).execute()
                progress_id = response.data[0]['id'] if response.data else None
            
            return progress_id
        except Exception as e:
            print(f"[DB ERROR] Save module progress failed: {e}")
            return None
    
    def get_module_progress(self, session_id: str, skill: str, module_id: int) -> Optional[Dict]:
        """Get module progress"""
        try:
            response = self.client.table('ai_module_progress').select('*').eq(
                'session_id', session_id
            ).eq('skill', skill).eq('module_id', module_id).single().execute()
            return response.data
        except Exception as e:
            print(f"[DB] Module progress not found: {e}")
            return None
    
    def complete_action(self, module_progress_id: str, action_index: int, 
                       action_type: str, completion_data: Dict) -> bool:
        """Mark action as complete"""
        try:
            action_completion = {
                'module_progress_id': module_progress_id,
                'action_index': action_index,
                'action_type': action_type,
                'completion_data': completion_data,
                'completed_at': datetime.now().isoformat()
            }
            
            response = self.client.table('ai_action_completions').insert(
                action_completion
            ).execute()
            
            # Update actions completed count
            progress_response = self.client.table('ai_module_progress').select(
                'actions_completed'
            ).eq('id', module_progress_id).single().execute()
            
            if progress_response.data:
                current_completed = progress_response.data.get('actions_completed', 0)
                self.client.table('ai_module_progress').update({
                    'actions_completed': current_completed + 1
                }).eq('id', module_progress_id).execute()
            
            return bool(response.data)
        except Exception as e:
            print(f"[DB ERROR] Complete action failed: {e}")
            return False
    
    # ========== CHECKPOINTS ==========
    
    def save_checkpoint_result(self, module_progress_id: str, user_id: str, 
                              questions: List[Dict], answers: List[int], 
                              score: float, passed: bool) -> bool:
        """Save checkpoint results"""
        try:
            checkpoint_data = {
                'module_progress_id': module_progress_id,
                'user_id': user_id,
                'questions': questions,
                'answers': answers,
                'score': float(score),
                'passed': passed,
                'submitted_at': datetime.now().isoformat()
            }
            
            response = self.client.table('ai_checkpoint_results').insert(
                checkpoint_data
            ).execute()
            
            return bool(response.data)
        except Exception as e:
            print(f"[DB ERROR] Save checkpoint failed: {e}")
            return False
    
    # ========== CONTENT & RESOURCES ==========
    
    def save_content_recommendation(self, session_id: str, user_id: str, skill: str,
                                   content_type: str, content_id: str, 
                                   recommendation_reason: str, 
                                   relevance_score: float = 0.5) -> bool:
        """Save content recommendation"""
        try:
            recommendation = {
                'session_id': session_id,
                'user_id': user_id,
                'skill': skill,
                'content_type': content_type,
                'recommendation_reason': recommendation_reason,
                'relevance_score': relevance_score,
                'created_at': datetime.now().isoformat(),
                'expires_at': (datetime.now() + timedelta(days=7)).isoformat()
            }
            
            # Handle different content ID types
            if content_type in ['taiken', 'course']:
                recommendation['content_id_uuid'] = uuid.UUID(content_id)
            else:
                recommendation['external_url'] = content_id
            
            response = self.client.table('pearl_content_recommendations').insert(
                recommendation
            ).execute()
            
            return bool(response.data)
        except Exception as e:
            print(f"[DB ERROR] Save recommendation failed: {e}")
            return False
    
    def get_content_recommendations(self, user_id: str, skill: Optional[str] = None,
                                   limit: int = 10) -> List[Dict]:
        """Get content recommendations for user"""
        try:
            query = self.client.table('pearl_content_recommendations').select('*').eq(
                'user_id', user_id
            ).eq('shown', False).lte('created_at', datetime.now().isoformat()).gt(
                'expires_at', datetime.now().isoformat()
            )
            
            if skill:
                query = query.eq('skill', skill)
            
            query = query.order('relevance_score', desc=True).limit(limit)
            
            response = query.execute()
            return response.data if response.data else []
        except Exception as e:
            print(f"[DB ERROR] Get recommendations failed: {e}")
            return []
    
    # ========== GAMIFICATION ==========
    
    def award_plaro_points(self, user_id: str, source: str, points: int,
                          related_content_type: Optional[str] = None,
                          related_content_id: Optional[str] = None,
                          session_id: Optional[str] = None,
                          reason: Optional[str] = None) -> bool:
        """Award Plaro points to user"""
        try:
            transaction = {
                'user_id': user_id,
                'source': source,
                'points': points,
                'reason': reason,
                'created_at': datetime.now().isoformat()
            }
            
            if session_id:
                transaction['session_id'] = session_id
            
            if related_content_type and related_content_id:
                if related_content_type in ['taiken', 'course']:
                    transaction['related_content_id_uuid'] = uuid.UUID(related_content_id)
                else:
                    transaction['related_content_id_int'] = int(related_content_id)
                transaction['related_content_type'] = related_content_type
            
            response = self.client.table('plaro_transactions').insert(
                transaction
            ).execute()
            
            # Update user's total points
            rank_response = self.client.table('user_profile_rank').select('*').eq(
                'user_id', user_id
            ).execute()
            
            if rank_response.data:
                current_points = rank_response.data[0].get('total_points', 0)
                self.client.table('user_profile_rank').update({
                    'total_points': current_points + points,
                    'last_updated': datetime.now().isoformat()
                }).eq('user_id', user_id).execute()
            else:
                # Create rank entry
                self.client.table('user_profile_rank').insert({
                    'user_id': user_id,
                    'total_points': points,
                    'last_updated': datetime.now().isoformat()
                }).execute()
            
            return bool(response.data)
        except Exception as e:
            print(f"[DB ERROR] Award points failed: {e}")
            return False
    
    def get_user_plaro_points(self, user_id: str) -> Dict:
        """Get user's Plaro points summary"""
        try:
            # Get total points
            rank_response = self.client.table('user_profile_rank').select('*').eq(
                'user_id', user_id
            ).single().execute()
            
            # Get recent transactions
            transactions_response = self.client.table('plaro_transactions').select('*').eq(
                'user_id', user_id
            ).order('created_at', desc=True).limit(20).execute()
            
            return {
                'total_points': rank_response.data.get('total_points', 0) if rank_response.data else 0,
                'rank_level': rank_response.data.get('rank_level', 'beginner') if rank_response.data else 'beginner',
                'recent_transactions': transactions_response.data if transactions_response.data else []
            }
        except Exception as e:
            print(f"[DB ERROR] Get points failed: {e}")
            return {'total_points': 0, 'rank_level': 'beginner', 'recent_transactions': []}
    
    # ========== ANALYTICS ==========
    
    def log_content_event(self, user_id: str, content_type: str, 
                         event_type: str, content_id: Optional[str] = None,
                         session_id: Optional[str] = None, 
                         metadata: Optional[Dict] = None) -> bool:
        """Log user content interaction event"""
        try:
            event = {
                'user_id': user_id,
                'content_type': content_type,
                'event_type': event_type,
                'created_at': datetime.now().isoformat(),
                'metadata': metadata or {}
            }
            
            if session_id:
                event['session_id'] = session_id
            
            if content_id:
                try:
                    uuid_obj = uuid.UUID(content_id)
                    event['content_id_uuid'] = str(uuid_obj)
                except ValueError:
                    try:
                        event['content_id_int'] = int(content_id)
                    except ValueError:
                        event['metadata']['content_id'] = content_id
            
            response = self.client.table('user_content_events').insert(
                event
            ).execute()
            
            return bool(response.data)
        except Exception as e:
            print(f"[DB ERROR] Log event failed: {e}")
            return False
    
    def get_user_learning_analytics(self, user_id: str) -> Dict:
        """Get comprehensive learning analytics for user"""
        try:
            # Get time spent
            events_response = self.client.table('user_content_events').select(
                'event_type, created_at, metadata'
            ).eq('user_id', user_id).gte(
                'created_at', (datetime.now() - timedelta(days=30)).isoformat()
            ).execute()
            
            # Calculate time spent
            total_seconds = 0
            content_interactions = {}
            
            for event in events_response.data or []:
                if event.get('event_type') == 'dwell':
                    total_seconds += event.get('metadata', {}).get('dwell_time_seconds', 0)
                
                content_type = event.get('content_type')
                if content_type:
                    content_interactions[content_type] = content_interactions.get(content_type, 0) + 1
            
            # Get completion stats
            progress_response = self.client.table('ai_module_progress').select(
                'status'
            ).eq('user_id', user_id).execute()
            
            total_modules = len(progress_response.data) if progress_response.data else 0
            completed_modules = len([p for p in (progress_response.data or []) 
                                   if p.get('status') == 'completed'])
            
            # Get skill growth
            skills_response = self.client.table('user_skill_memory').select(
                'skill_name, confidence_score, created_at'
            ).eq('user_id', user_id).execute()
            
            skill_growth = []
            if skills_response.data:
                for skill in skills_response.data:
                    created_at = datetime.fromisoformat(skill['created_at'].replace('Z', '+00:00'))
                    days_old = (datetime.now() - created_at).days
                    skill_growth.append({
                        'skill': skill['skill_name'],
                        'confidence': float(skill['confidence_score']),
                        'days_practicing': max(1, days_old),
                        'growth_per_day': float(skill['confidence_score']) / max(1, days_old)
                    })
            
            return {
                'total_learning_time_hours': round(total_seconds / 3600, 1),
                'avg_daily_minutes': round((total_seconds / 30) / 60, 1),
                'content_interactions': content_interactions,
                'module_completion_rate': (completed_modules / total_modules * 100) if total_modules > 0 else 0,
                'total_modules_completed': completed_modules,
                'skill_growth_trend': skill_growth,
                'most_improved_skill': max(skill_growth, key=lambda x: x['growth_per_day']) if skill_growth else None,
                'consistency_score': self._calculate_consistency_score(user_id)
            }
        except Exception as e:
            print(f"[DB ERROR] Get analytics failed: {e}")
            return {}
    
    def _calculate_consistency_score(self, user_id: str) -> float:
        """Calculate user consistency score"""
        try:
            # Get events from last 30 days
            response = self.client.table('user_content_events').select(
                'created_at'
            ).eq('user_id', user_id).gte(
                'created_at', (datetime.now() - timedelta(days=30)).isoformat()
            ).execute()
            
            if not response.data:
                return 0.0
            
            # Count unique days with activity
            unique_days = set()
            for event in response.data:
                event_date = datetime.fromisoformat(
                    event['created_at'].replace('Z', '+00:00')
                ).date()
                unique_days.add(event_date)
            
            return len(unique_days) / 30.0  # Ratio of active days
            
        except Exception as e:
            print(f"[DB ERROR] Calculate consistency failed: {e}")
            return 0.0
    
    # ========== TAIKEN INTEGRATION ==========
    
    def get_user_taiken_progress(self, user_id: str) -> List[Dict]:
        """Get user's Taiken progress"""
        try:
            response = self.client.table('taiken_progress').select('*').eq(
                'user_id', user_id
            ).order('updated_at', desc=True).execute()
            return response.data if response.data else []
        except Exception as e:
            print(f"[DB ERROR] Get Taiken progress failed: {e}")
            return []
    
    def save_taiken_progress(self, user_id: str, taiken_id: str, 
                            stage_order: int, status: str,
                            correct_answers: int = 0, 
                            wrong_answers: int = 0) -> bool:
        """Save or update Taiken progress"""
        try:
            progress_data = {
                'user_id': user_id,
                'taiken_id': taiken_id,
                'current_stage_order': stage_order,
                'questions_answered': correct_answers + wrong_answers,
                'correct_answers': correct_answers,
                'wrong_answers': wrong_answers,
                'status': status,
                'updated_at': datetime.now().isoformat()
            }
            
            if status == 'completed':
                progress_data['completed_at'] = datetime.now().isoformat()
            
            # Check existing
            existing_response = self.client.table('taiken_progress').select('*').eq(
                'user_id', user_id
            ).eq('taiken_id', taiken_id).execute()
            
            if existing_response.data:
                # Update
                response = self.client.table('taiken_progress').update(
                    progress_data
                ).eq('progress_id', existing_response.data[0]['progress_id']).execute()
            else:
                # Create
                progress_data['created_at'] = datetime.now().isoformat()
                response = self.client.table('taiken_progress').insert(
                    progress_data
                ).execute()
            
            # Award points for completion
            if status == 'completed':
                self.award_plaro_points(
                    user_id=user_id,
                    source='taiken_completed',
                    points=50,
                    related_content_type='taiken',
                    related_content_id=taiken_id,
                    reason='Completed Taiken experience'
                )
            
            return bool(response.data)
        except Exception as e:
            print(f"[DB ERROR] Save Taiken progress failed: {e}")
            return False


# Global instance
db_helper = EnhancedSupabaseHelper()