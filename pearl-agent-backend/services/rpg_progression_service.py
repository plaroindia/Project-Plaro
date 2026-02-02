"""
RPG Progression Service
Life/Energy system, XP, Levels, and RPG-style progression
"""
from typing import Dict, Optional
from datetime import datetime
import math

try:
    from database import EnhancedSupabaseHelper
    db = EnhancedSupabaseHelper()
except:
    db = None


class RPGProgressionService:
    """RPG-style progression system"""
    
    # Constants
    MAX_ENERGY = 100
    ENERGY_REGEN_PER_HOUR = 5
    XP_PER_LEVEL = 100
    LEVEL_MULTIPLIER = 1.5
    
    @staticmethod
    def get_user_rpg_stats(user_id: str) -> Dict:
        """Get user's RPG statistics"""
        try:
            if not db:
                return {
                    'level': 1,
                    'current_xp': 0,
                    'current_energy': RPGProgressionService.MAX_ENERGY,
                    'max_energy': RPGProgressionService.MAX_ENERGY
                }
            
            # Get or create RPG profile
            rpg_profile = db.client.table('user_rpg_stats').select('*').eq(
                'user_id', user_id
            ).execute()
            
            if not rpg_profile.data:
                # Create new profile
                new_profile = {
                    'user_id': user_id,
                    'level': 1,
                    'current_xp': 0,
                    'total_xp': 0,
                    'current_energy': RPGProgressionService.MAX_ENERGY,
                    'max_energy': RPGProgressionService.MAX_ENERGY,
                    'last_energy_update': datetime.now().isoformat(),
                    'created_at': datetime.now().isoformat()
                }
                
                db.client.table('user_rpg_stats').insert(new_profile).execute()
                return new_profile
            
            profile = rpg_profile.data[0]
            
            # Regenerate energy
            profile = RPGProgressionService._regenerate_energy(profile)
            
            # Calculate level progress
            xp_for_next_level = RPGProgressionService._calculate_xp_for_level(profile['level'] + 1)
            level_progress = (profile['current_xp'] / xp_for_next_level) * 100
            
            return {
                **profile,
                'xp_for_next_level': xp_for_next_level,
                'level_progress_percentage': round(level_progress, 1)
            }
            
        except Exception as e:
            print(f"[RPG] Get stats failed: {e}")
            return {
                'level': 1,
                'current_xp': 0,
                'current_energy': RPGProgressionService.MAX_ENERGY,
                'max_energy': RPGProgressionService.MAX_ENERGY
            }
    
    @staticmethod
    def _regenerate_energy(profile: Dict) -> Dict:
        """Regenerate energy based on time passed"""
        try:
            last_update_str = profile.get('last_energy_update', '')
            if isinstance(last_update_str, str):
                last_update = datetime.fromisoformat(
                    last_update_str.replace('Z', '+00:00')
                )
            else:
                last_update = last_update_str
            
            now = datetime.now()
            hours_passed = (now - last_update).total_seconds() / 3600
            
            if hours_passed > 0:
                energy_regen = int(hours_passed * RPGProgressionService.ENERGY_REGEN_PER_HOUR)
                new_energy = min(
                    profile.get('max_energy', RPGProgressionService.MAX_ENERGY),
                    profile['current_energy'] + energy_regen
                )
                
                if new_energy != profile['current_energy'] and db:
                    # Update in database
                    db.client.table('user_rpg_stats').update({
                        'current_energy': new_energy,
                        'last_energy_update': now.isoformat()
                    }).eq('user_id', profile['user_id']).execute()
                    
                    profile['current_energy'] = new_energy
                    profile['last_energy_update'] = now.isoformat()
            
            return profile
            
        except Exception as e:
            print(f"[RPG] Energy regen failed: {e}")
            return profile
    
    @staticmethod
    def _calculate_xp_for_level(level: int) -> int:
        """Calculate XP required for a level"""
        return int(RPGProgressionService.XP_PER_LEVEL * math.pow(RPGProgressionService.LEVEL_MULTIPLIER, level - 1))
    
    @staticmethod
    def award_xp(user_id: str, xp_amount: int, reason: str) -> Dict:
        """Award XP to user and handle level ups"""
        try:
            if not db:
                return {"success": False, "error": "Database not available"}
            
            profile = RPGProgressionService.get_user_rpg_stats(user_id)
            
            new_xp = profile['current_xp'] + xp_amount
            new_total_xp = profile['total_xp'] + xp_amount
            current_level = profile['level']
            
            # Check for level up
            leveled_up = False
            new_level = current_level
            
            while new_xp >= RPGProgressionService._calculate_xp_for_level(new_level + 1):
                xp_for_level = RPGProgressionService._calculate_xp_for_level(new_level + 1)
                new_xp -= xp_for_level
                new_level += 1
                leveled_up = True
            
            # Update database
            update_data = {
                'current_xp': new_xp,
                'total_xp': new_total_xp,
                'level': new_level,
                'updated_at': datetime.now().isoformat()
            }
            
            # Bonus max energy on level up
            if leveled_up:
                update_data['max_energy'] = profile.get('max_energy', RPGProgressionService.MAX_ENERGY) + 10
                update_data['current_energy'] = update_data['max_energy']  # Full restore
            
            db.client.table('user_rpg_stats').update(update_data).eq(
                'user_id', user_id
            ).execute()
            
            # Log XP transaction
            db.client.table('xp_transactions').insert({
                'user_id': user_id,
                'xp_amount': xp_amount,
                'reason': reason,
                'created_at': datetime.now().isoformat()
            }).execute()
            
            return {
                "success": True,
                "xp_awarded": xp_amount,
                "new_total_xp": new_total_xp,
                "current_level": new_level,
                "leveled_up": leveled_up,
                "levels_gained": new_level - current_level if leveled_up else 0,
                "current_xp": new_xp,
                "xp_for_next_level": RPGProgressionService._calculate_xp_for_level(new_level + 1)
            }
            
        except Exception as e:
            print(f"[RPG] Award XP failed: {e}")
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def consume_energy(user_id: str, energy_cost: int, activity: str) -> Dict:
        """Consume energy for an activity"""
        try:
            if not db:
                return {"success": False, "error": "Database not available"}
            
            profile = RPGProgressionService.get_user_rpg_stats(user_id)
            
            if profile['current_energy'] < energy_cost:
                return {
                    "success": False,
                    "error": "Not enough energy",
                    "current_energy": profile['current_energy'],
                    "required_energy": energy_cost,
                    "energy_deficit": energy_cost - profile['current_energy']
                }
            
            new_energy = profile['current_energy'] - energy_cost
            
            db.client.table('user_rpg_stats').update({
                'current_energy': new_energy,
                'updated_at': datetime.now().isoformat()
            }).eq('user_id', user_id).execute()
            
            # Log energy transaction
            db.client.table('energy_transactions').insert({
                'user_id': user_id,
                'energy_amount': -energy_cost,
                'activity': activity,
                'created_at': datetime.now().isoformat()
            }).execute()
            
            return {
                "success": True,
                "energy_consumed": energy_cost,
                "remaining_energy": new_energy,
                "activity": activity
            }
            
        except Exception as e:
            print(f"[RPG] Consume energy failed: {e}")
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def get_energy_costs() -> Dict:
        """Get standard energy costs for activities"""
        return {
            "watch_byte": 5,
            "complete_course": 15,
            "practice_set": 10,
            "checkpoint": 20,
            "taiken_module": 25,
            "job_application": 30
        }
    
    @staticmethod
    def get_xp_rewards() -> Dict:
        """Get standard XP rewards for activities"""
        return {
            "watch_byte": 10,
            "complete_course": 50,
            "practice_set_perfect": 30,
            "practice_set_good": 20,
            "checkpoint_pass": 100,
            "module_complete": 150,
            "skill_mastery": 500,
            "roadmap_complete": 1000
        }


# Global instance
rpg_service = RPGProgressionService()
