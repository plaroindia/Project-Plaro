"""
FIXED Authentication Routes
Properly handles Supabase sessions and matches frontend expectations
"""

from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel, EmailStr
from supabase import create_client, Client
from config import get_settings
from typing import Optional, Dict
from datetime import datetime

settings = get_settings()
router = APIRouter()


# ==================== Pydantic Models ====================

class SignupRequest(BaseModel):
    email: EmailStr
    password: str
    username: str


class SigninRequest(BaseModel):
    email: EmailStr
    password: str


class ProfileUpdateRequest(BaseModel):
    updates: Dict


# ==================== Auth Service ====================

class AuthService:
    """Handles user authentication via Supabase"""
    
    def __init__(self):
        self.client: Client = create_client(settings.SUPABASE_URL, settings.SUPABASE_KEY)
    
    def sign_up_email(self, email: str, password: str, username: str) -> Dict:
        """Sign up with email and password"""
        try:
            print(f"[AUTH] Attempting signup for: {email}")
            
            auth_response = self.client.auth.sign_up({
                "email": email,
                "password": password,
                "options": {
                    "data": {
                        "username": username
                    }
                }
            })
            
            if not auth_response.user:
                print(f"[AUTH] ❌ Signup failed: No user created")
                return {
                    "success": False,
                    "error": "User creation failed"
                }
            
            user = auth_response.user
            user_id = user.id
            print(f"[AUTH] ✅ User created: {user_id}")
            
            try:
                profile_data = {
                    "user_id": user_id,
                    "username": username,
                    "email": email,
                    "role": "learner",
                    "streak_count": 0,
                    "followers_count": 0,
                    "following_count": 0,
                    "onboarding_complete": False,
                    "created_at": datetime.now().isoformat(),
                    "updated_at": datetime.now().isoformat()
                }
                
                self.client.table('user_profiles').insert(profile_data).execute()
                print(f"[AUTH] ✅ Profile created for: {username}")
                
            except Exception as profile_error:
                print(f"[AUTH] ⚠️ Profile creation warning: {profile_error}")
            
            access_token = None
            session_data = None
            
            if auth_response.session:
                access_token = auth_response.session.access_token
                session_data = {
                    "access_token": access_token,
                    "refresh_token": auth_response.session.refresh_token,
                    "expires_at": auth_response.session.expires_at,
                    "token_type": "bearer"
                }
            
            return {
                "success": True,
                "user": {
                    "id": user_id,
                    "email": user.email,
                    "username": username
                },
                "access_token": access_token,
                "session": session_data,
                "requires_verification": user.email_confirmed_at is None
            }
            
        except Exception as e:
            error_msg = str(e)
            print(f"[AUTH] ❌ Signup error: {error_msg}")
            
            if "User already registered" in error_msg or "already been registered" in error_msg:
                return {"success": False, "error": "Email already registered"}
            
            if "Password should be at least" in error_msg:
                return {"success": False, "error": "Password must be at least 6 characters"}
            
            return {"success": False, "error": error_msg}
    
    def sign_in_email(self, email: str, password: str) -> Dict:
        """Sign in with email and password"""
        try:
            print(f"[AUTH] Attempting signin for: {email}")
            
            auth_response = self.client.auth.sign_in_with_password({
                "email": email,
                "password": password
            })
            
            if not auth_response.user or not auth_response.session:
                print(f"[AUTH] ❌ Signin failed: Invalid credentials")
                return {"success": False, "error": "Invalid credentials"}
            
            user = auth_response.user
            print(f"[AUTH] ✅ User authenticated: {user.id}")
            
            profile_data = None
            try:
                profile_response = self.client.table('user_profiles').select('*').eq(
                    'user_id', user.id
                ).single().execute()
                
                profile_data = profile_response.data if profile_response.data else None
                print(f"[AUTH] ✅ Profile loaded: {profile_data.get('username') if profile_data else 'None'}")
                
            except Exception as profile_error:
                print(f"[AUTH] ⚠️ Profile fetch warning: {profile_error}")
            
            access_token = auth_response.session.access_token
            session_data = {
                "access_token": access_token,
                "refresh_token": auth_response.session.refresh_token,
                "expires_at": auth_response.session.expires_at,
                "token_type": "bearer"
            }
            
            return {
                "success": True,
                "user": {
                    "id": user.id,
                    "email": user.email,
                    "username": profile_data.get('username') if profile_data else (user.user_metadata.get('username') if user.user_metadata else user.email.split('@')[0]),
                    "profile": profile_data
                },
                "access_token": access_token,
                "session": session_data,
                "requires_onboarding": not self._check_onboarding_complete(profile_data)
            }
            
        except Exception as e:
            error_msg = str(e)
            print(f"[AUTH] ❌ Signin error: {error_msg}")
            
            if "Invalid login credentials" in error_msg or "invalid_credentials" in error_msg.lower():
                return {"success": False, "error": "Invalid email or password"}
            
            if "Email not confirmed" in error_msg:
                return {"success": False, "error": "Please verify your email first"}
            
            return {"success": False, "error": error_msg}
    
    def sign_out(self) -> Dict:
        """Sign out user"""
        try:
            self.client.auth.sign_out()
            print(f"[AUTH] ✅ User signed out")
            return {"success": True}
        except Exception as e:
            print(f"[AUTH] ❌ Signout error: {e}")
            return {"success": False, "error": str(e)}
    
    def get_user_from_token(self, access_token: str) -> Optional[Dict]:
        """Get user from access token"""
        try:
            user_response = self.client.auth.get_user(access_token)
            
            if not user_response or not user_response.user:
                return None
            
            user = user_response.user
            profile_data = None
            
            try:
                profile_response = self.client.table('user_profiles').select('*').eq(
                    'user_id', user.id
                ).single().execute()
                
                profile_data = profile_response.data if profile_response.data else None
            except Exception:
                pass
            
            return {
                "id": user.id,
                "email": user.email,
                "username": profile_data.get('username') if profile_data else user.user_metadata.get('username'),
                "profile": profile_data
            }
            
        except Exception as e:
            print(f"[AUTH] ❌ Token validation error: {e}")
            return None
    
    def _check_onboarding_complete(self, profile_data: Optional[Dict]) -> bool:
        """Check if user has completed onboarding"""
        if not profile_data:
            return False
        return profile_data.get('onboarding_complete', False) == True
    
    def update_profile(self, user_id: str, updates: Dict) -> Dict:
        """Update user profile"""
        try:
            allowed_fields = ['username', 'bio', 'study', 'location', 'profile_pic', 'role', 'onboarding_complete']
            filtered_updates = {k: v for k, v in updates.items() if k in allowed_fields}
            filtered_updates['updated_at'] = datetime.now().isoformat()
            
            result = self.client.table('user_profiles').update(
                filtered_updates
            ).eq('user_id', user_id).execute()
            
            return {
                "success": True,
                "profile": result.data[0] if result.data else None
            }
            
        except Exception as e:
            print(f"[AUTH] ❌ Profile update error: {e}")
            return {"success": False, "error": str(e)}
    
    def get_user_profile(self, user_id: str) -> Optional[Dict]:
        """Get complete user profile with skills"""
        try:
            profile_response = self.client.table('user_profiles').select('*').eq(
                'user_id', user_id
            ).single().execute()
            
            if not profile_response.data:
                return None
            
            skills_data = []
            try:
                skills_response = self.client.table('user_skill_memory').select('*').eq(
                    'user_id', user_id
                ).order('confidence_score', desc=True).execute()
                
                skills_data = skills_response.data if skills_response.data else []
            except Exception:
                pass
            
            sessions_data = []
            try:
                sessions_response = self.client.table('ai_agent_sessions').select('*').eq(
                    'user_id', user_id
                ).eq('status', 'active').order('created_at', desc=True).limit(5).execute()
                
                sessions_data = sessions_response.data if sessions_response.data else []
            except Exception:
                pass
            
            return {
                "profile": profile_response.data,
                "skills": skills_data,
                "active_sessions": sessions_data
            }
            
        except Exception as e:
            print(f"[AUTH] ❌ Get profile error: {e}")
            return None


# Global instance
auth_service = AuthService()


# ==================== API Routes ====================

@router.post("/signup")
async def signup(request: SignupRequest):
    """Sign up a new user with email and password"""
    try:
        print(f"\n[API] POST /auth/signup - {request.email}")
        
        result = auth_service.sign_up_email(
            request.email, 
            request.password, 
            request.username
        )
        
        if not result.get("success"):
            print(f"[API] ❌ Signup failed: {result.get('error')}")
            raise HTTPException(
                status_code=400, 
                detail=result.get("error", "Signup failed")
            )
        
        print(f"[API] ✅ Signup successful")
        
        return {
            "success": True,
            "user": result["user"],
            "access_token": result["access_token"],
            "session": result.get("session"),
            "requires_verification": result.get("requires_verification", False)
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[API] ❌ Signup exception: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/signin")
async def signin(request: SigninRequest):
    """Sign in user with email and password"""
    try:
        print(f"\n[API] POST /auth/signin - {request.email}")
        
        result = auth_service.sign_in_email(request.email, request.password)
        
        if not result.get("success"):
            print(f"[API] ❌ Signin failed: {result.get('error')}")
            raise HTTPException(
                status_code=401, 
                detail=result.get("error", "Invalid credentials")
            )
        
        print(f"[API] ✅ Signin successful")
        
        return {
            "success": True,
            "user": result["user"],
            "access_token": result["access_token"],
            "session": result.get("session"),
            "requires_onboarding": result.get("requires_onboarding", False)
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[API] ❌ Signin exception: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/signout")
async def signout(authorization: Optional[str] = Header(None)):
    """Sign out current user"""
    try:
        print(f"\n[API] POST /auth/signout")
        result = auth_service.sign_out()
        print(f"[API] ✅ Signout successful")
        return result
    except Exception as e:
        print(f"[API] ❌ Signout exception: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/me")
async def get_current_user(authorization: Optional[str] = Header(None)):
    """Get current user from access token"""
    try:
        if not authorization:
            raise HTTPException(status_code=401, detail="No authorization header")
        
        token = authorization.replace("Bearer ", "") if authorization.startswith("Bearer ") else authorization
        
        user = auth_service.get_user_from_token(token)
        if not user:
            raise HTTPException(status_code=401, detail="Invalid token")
        
        return {
            "success": True, 
            "user": {
                "id": user.get("id"),
                "email": user.get("email"),
                "username": user.get("username")
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/profile/{user_id}")
async def get_user_profile(user_id: str):
    """Get user profile with skills and sessions"""
    try:
        print(f"\n[API] GET /auth/profile/{user_id}")
        
        profile = auth_service.get_user_profile(user_id)
        if not profile:
            raise HTTPException(status_code=404, detail="Profile not found")
        
        print(f"[API] ✅ Profile retrieved")
        return profile
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[API] ❌ Profile exception: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/profile/{user_id}")
async def update_user_profile(user_id: str, request: ProfileUpdateRequest):
    """Update user profile"""
    try:
        print(f"\n[API] PUT /auth/profile/{user_id}")
        
        result = auth_service.update_profile(user_id, request.updates)
        
        if not result.get("success"):
            raise HTTPException(
                status_code=400, 
                detail=result.get("error", "Update failed")
            )
        
        print(f"[API] ✅ Profile updated")
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[API] ❌ Update exception: {e}")
        raise HTTPException(status_code=500, detail=str(e))