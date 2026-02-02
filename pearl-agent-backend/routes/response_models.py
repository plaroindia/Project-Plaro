"""
Standardized Response Models for API
Ensures consistent JSON structure across all endpoints
"""

from pydantic import BaseModel
from typing import Optional, Dict, List, Any
from enum import Enum


class ResponseStatus(str, Enum):
    """Standard response statuses"""
    SUCCESS = "success"
    ERROR = "error"
    PENDING = "pending"


class ApiResponse(BaseModel):
    """Standard API response wrapper"""
    status: ResponseStatus
    message: Optional[str] = None
    data: Optional[Dict[str, Any]] = None
    error: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None

    class Config:
        json_schema_extra = {
            "example": {
                "status": "success",
                "message": "Operation completed successfully",
                "data": {"key": "value"},
                "metadata": {"timestamp": "2024-01-24T10:00:00Z"}
            }
        }


# ==================== Auth Response Models ====================

class UserData(BaseModel):
    """User information"""
    id: str
    email: str
    username: str
    profile: Optional[Dict[str, Any]] = None


class AuthResponse(BaseModel):
    """Authentication response"""
    success: bool
    user: UserData
    access_token: str
    refresh_token: Optional[str] = None
    expires_at: Optional[int] = None


class SignupResponse(BaseModel):
    """Signup response"""
    success: bool
    user: UserData
    access_token: str
    requires_verification: bool = False


class SigninResponse(BaseModel):
    """Signin response"""
    success: bool
    user: UserData
    access_token: str
    requires_onboarding: bool = False


# ==================== Learning Path Models ====================

class Skill(BaseModel):
    """Skill with proficiency level"""
    name: str
    confidence: float  # 0.0 to 1.0


class Module(BaseModel):
    """Learning module"""
    id: str
    name: str
    description: str
    estimated_hours: float
    difficulty: str  # beginner, intermediate, advanced
    status: str  # locked, active, completed
    type: str  # byte, course, project, checkpoint
    completion_percentage: float = 0.0


class LearningPath(BaseModel):
    """Complete learning path for a skill"""
    skill: str
    modules: List[Module]
    total_hours: float
    difficulty_level: str
    prerequisites: List[str] = []


class CareerGoalResponse(BaseModel):
    """Response from career goal parsing"""
    success: bool
    session_id: str
    skills_identified: List[Skill]
    learning_paths: Dict[str, LearningPath]
    estimated_weeks: int
    job_market_insight: Optional[str] = None


# ==================== Job Recommendation Models ====================

class Job(BaseModel):
    """Job opportunity"""
    id: str
    title: str
    company: str
    location: str
    salary_min: Optional[float] = None
    salary_max: Optional[float] = None
    description: str
    url: str
    posted_date: Optional[str] = None


class JobMatch(BaseModel):
    """Job with match information"""
    job: Job
    match_percentage: float  # 0-100
    matched_skills: List[str]
    missing_skills: List[str]
    match_reason: str


class JobRecommendationsResponse(BaseModel):
    """Job recommendations response"""
    success: bool
    total_matches: int
    matched_jobs: List[JobMatch]
    search_query: Optional[str] = None


# ==================== Content Resource Models ====================

class ContentResource(BaseModel):
    """Learning content resource"""
    id: str
    provider: str  # youtube, freecodecamp, mit_ocw
    title: str
    description: Optional[str] = None
    url: str
    difficulty: str  # beginner, intermediate, advanced
    duration_minutes: float
    tags: List[str] = []
    thumbnail_url: Optional[str] = None
    completion_status: str = "not_started"  # not_started, in_progress, completed


class ContentResponse(BaseModel):
    """Content resources response"""
    success: bool
    skill: str
    content_count: int
    resources: List[ContentResource]
    learning_preference: Optional[str] = None  # video, text, hands-on, mixed


class LearningRoadmapResponse(BaseModel):
    """Structured learning roadmap"""
    success: bool
    skill: str
    phases: List[Dict[str, Any]]  # Phase with content resources
    total_weeks: int
    difficulty_progression: List[str]


# ==================== Progress & Session Models ====================

class SessionProgress(BaseModel):
    """User progress in learning session"""
    session_id: str
    user_id: str
    skill: str
    total_modules: int
    completed_modules: int
    completion_percentage: float
    time_spent_minutes: float
    started_at: str
    last_activity: str


class CheckpointResult(BaseModel):
    """Checkpoint/quiz results"""
    success: bool
    score: float  # 0-100
    passed: bool
    correct_answers: int
    total_questions: int
    explanation: Optional[str] = None
    next_action: Optional[str] = None
    rewards: Optional[Dict[str, Any]] = None


# ==================== Error Response Models ====================

class ErrorDetail(BaseModel):
    """Error details"""
    error_code: str
    message: str
    details: Optional[Dict[str, Any]] = None
    timestamp: str
    path: str


class ValidationError(BaseModel):
    """Validation error"""
    field: str
    message: str
    value: Any


# ==================== Helper Functions ====================

def success_response(
    data: Optional[Dict[str, Any]] = None,
    message: str = "Operation successful",
    metadata: Optional[Dict[str, Any]] = None
) -> ApiResponse:
    """Create success response"""
    return ApiResponse(
        status=ResponseStatus.SUCCESS,
        message=message,
        data=data,
        metadata=metadata
    )


def error_response(
    error: str,
    message: str = "Operation failed",
    data: Optional[Dict[str, Any]] = None
) -> ApiResponse:
    """Create error response"""
    return ApiResponse(
        status=ResponseStatus.ERROR,
        message=message,
        error=error,
        data=data
    )


def pending_response(
    data: Optional[Dict[str, Any]] = None,
    message: str = "Operation pending"
) -> ApiResponse:
    """Create pending response"""
    return ApiResponse(
        status=ResponseStatus.PENDING,
        message=message,
        data=data
    )
