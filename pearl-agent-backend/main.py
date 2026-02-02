"""
PEARL API with Built-in Testing Dashboard
Enhanced for comprehensive backend testing without frontend
"""
from fastapi import FastAPI, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel
from typing import Optional, Dict, List
import os
import traceback
import json
from datetime import datetime

# Create app
app = FastAPI(
    title="PEARL Agent API - Testing Edition",
    version="2.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
    description="PEARL Learning Platform API with Built-in Testing Dashboard"
)

# CORS - Essential for Vercel
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"]
)

# Global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    error_detail = {
        "error": str(exc),
        "type": type(exc).__name__,
        "path": str(request.url),
        "method": request.method,
        "traceback": traceback.format_exc()
    }
    
    print(f"[ERROR] Unhandled exception: {exc}")
    print(traceback.format_exc())
    
    return JSONResponse(
        status_code=500,
        content=error_detail
    )

# Import routes with detailed error handling
routes_loaded = {
    'auth': {'loaded': False, 'error': None},
    'pearl': {'loaded': False, 'error': None},
    'api': {'loaded': False, 'error': None}
}

try:
    from routes import auth_routes
    app.include_router(auth_routes.router, prefix="/auth", tags=["auth"])
    routes_loaded['auth']['loaded'] = True
    print("[✓] Auth routes loaded")
except Exception as e:
    routes_loaded['auth']['error'] = str(e)
    print(f"[✗] Failed to load auth routes: {e}")

try:
    from routes import pearl_routes
    app.include_router(pearl_routes.router, prefix="/agent", tags=["pearl"])
    routes_loaded['pearl']['loaded'] = True
    print("[✓] Pearl routes loaded")
except Exception as e:
    routes_loaded['pearl']['error'] = str(e)
    print(f"[✗] Failed to load pearl routes: {e}")

try:
    from routes import new_routes
    app.include_router(new_routes.router, prefix="/api", tags=["api"])
    routes_loaded['api']['loaded'] = True
    print("[✓] API routes loaded")
except Exception as e:
    routes_loaded['api']['error'] = str(e)
    print(f"[✗] Failed to load API routes: {e}")

# Import services for testing
services_loaded = {
    'database': {'loaded': False, 'error': None},
    'auth': {'loaded': False, 'error': None},
    'gemini': {'loaded': False, 'error': None},
    'adzuna': {'loaded': False, 'error': None},
    'gamification': {'loaded': False, 'error': None},
    'rag': {'loaded': False, 'error': None}
}

try:
    from database import EnhancedSupabaseHelper
    db = EnhancedSupabaseHelper()
    services_loaded['database']['loaded'] = True
    print("[✓] Database service loaded")
except Exception as e:
    services_loaded['database']['error'] = str(e)
    print(f"[✗] Failed to load database: {e}")
    db = None

try:
    from services.auth_service import auth_service
    services_loaded['auth']['loaded'] = True
    print("[✓] Auth service loaded")
except Exception as e:
    services_loaded['auth']['error'] = str(e)
    print(f"[✗] Failed to load auth service: {e}")
    auth_service = None

try:
    from services.geminiai_service import GeminiService
    gemini = GeminiService()
    services_loaded['gemini']['loaded'] = True
    print("[✓] Gemini service loaded")
except Exception as e:
    services_loaded['gemini']['error'] = str(e)
    print(f"[✗] Failed to load Gemini service: {e}")
    gemini = None

try:
    from services.job_retrieval_service import adzuna_service
    services_loaded['adzuna']['loaded'] = True
    print("[✓] Adzuna service loaded")
except Exception as e:
    services_loaded['adzuna']['error'] = str(e)
    print(f"[✗] Failed to load Adzuna service: {e}")
    adzuna_service = None

try:
    from services.gamification_service import gamification_service
    services_loaded['gamification']['loaded'] = True
    print("[✓] Gamification service loaded")
except Exception as e:
    services_loaded['gamification']['error'] = str(e)
    print(f"[✗] Failed to load gamification service: {e}")
    gamification_service = None

try:
    from services.enhanced_rag_service import enhanced_rag
    services_loaded['rag']['loaded'] = True
    print("[✓] RAG service loaded")
except Exception as e:
    services_loaded['rag']['error'] = str(e)
    print(f"[✗] Failed to load RAG service: {e}")
    enhanced_rag = None

try:
    from config import get_settings
    settings = get_settings()
    print("[✓] Config loaded")
except Exception as e:
    print(f"[✗] Failed to load config: {e}")
    settings = None


# ============================================
# TESTING ENDPOINTS
# ============================================

@app.get("/", response_class=HTMLResponse)
async def serve_testing_dashboard():
    """Comprehensive testing dashboard"""
    
    # Check which services are working
    routes_status = []
    for route, status in routes_loaded.items():
        routes_status.append({
            'name': route,
            'status': '✓' if status['loaded'] else '✗',
            'error': status['error']
        })
    
    services_status = []
    for service, status in services_loaded.items():
        services_status.append({
            'name': service,
            'status': '✓' if status['loaded'] else '✗',
            'error': status['error']
        })
    
    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>PEARL Backend Testing Dashboard</title>
        <style>
            * {{ margin: 0; padding: 0; box-sizing: border-box; }}
            body {{
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: #333;
                line-height: 1.6;
            }}
            .container {{
                max-width: 1400px;
                margin: 0 auto;
                padding: 20px;
            }}
            .header {{
                background: white;
                padding: 30px;
                border-radius: 15px;
                box-shadow: 0 10px 30px rgba(0,0,0,0.3);
                margin-bottom: 30px;
                text-align: center;
            }}
            .header h1 {{
                color: #667eea;
                font-size: 2.5em;
                margin-bottom: 10px;
            }}
            .header p {{
                color: #666;
                font-size: 1.1em;
            }}
            .grid {{
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
                gap: 20px;
                margin-bottom: 30px;
            }}
            .card {{
                background: white;
                padding: 25px;
                border-radius: 15px;
                box-shadow: 0 10px 30px rgba(0,0,0,0.2);
                transition: transform 0.3s;
            }}
            .card:hover {{
                transform: translateY(-5px);
                box-shadow: 0 15px 40px rgba(0,0,0,0.3);
            }}
            .card h2 {{
                color: #667eea;
                margin-bottom: 15px;
                font-size: 1.5em;
                border-bottom: 2px solid #667eea;
                padding-bottom: 10px;
            }}
            .status-item {{
                display: flex;
                justify-content: space-between;
                align-items: center;
                padding: 10px;
                margin: 5px 0;
                background: #f5f5f5;
                border-radius: 8px;
            }}
            .status-ok {{
                color: #27ae60;
                font-weight: bold;
                font-size: 1.3em;
            }}
            .status-error {{
                color: #e74c3c;
                font-weight: bold;
                font-size: 1.3em;
            }}
            .test-section {{
                background: white;
                padding: 25px;
                border-radius: 15px;
                box-shadow: 0 10px 30px rgba(0,0,0,0.2);
                margin-bottom: 20px;
            }}
            .test-section h3 {{
                color: #667eea;
                margin-bottom: 15px;
                font-size: 1.3em;
            }}
            .test-button {{
                display: inline-block;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                padding: 12px 25px;
                border: none;
                border-radius: 8px;
                cursor: pointer;
                font-size: 1em;
                margin: 5px;
                text-decoration: none;
                transition: all 0.3s;
            }}
            .test-button:hover {{
                transform: scale(1.05);
                box-shadow: 0 5px 15px rgba(102, 126, 234, 0.4);
            }}
            .api-link {{
                display: block;
                color: #667eea;
                text-decoration: none;
                padding: 8px;
                margin: 5px 0;
                background: #f0f0f0;
                border-radius: 5px;
                transition: background 0.3s;
            }}
            .api-link:hover {{
                background: #e0e0e0;
            }}
            .error-details {{
                background: #fee;
                border-left: 4px solid #e74c3c;
                padding: 10px;
                margin-top: 10px;
                border-radius: 5px;
                font-size: 0.9em;
                color: #c0392b;
            }}
            textarea {{
                width: 100%;
                min-height: 120px;
                padding: 10px;
                border: 2px solid #ddd;
                border-radius: 8px;
                font-family: monospace;
                resize: vertical;
                margin: 10px 0;
            }}
            input[type="text"] {{
                width: 100%;
                padding: 10px;
                border: 2px solid #ddd;
                border-radius: 8px;
                margin: 10px 0;
            }}
            .result-box {{
                background: #f9f9f9;
                border: 2px solid #ddd;
                border-radius: 8px;
                padding: 15px;
                margin: 10px 0;
                max-height: 400px;
                overflow-y: auto;
            }}
            .result-box pre {{
                white-space: pre-wrap;
                word-wrap: break-word;
                font-size: 0.9em;
            }}
            .quick-tests {{
                display: flex;
                flex-wrap: wrap;
                gap: 10px;
                margin: 15px 0;
            }}
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>🔬 PEARL Backend Testing Dashboard</h1>
                <p>Comprehensive testing interface for PEARL Learning Platform</p>
                <p><strong>Time:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
            </div>

            <div class="grid">
                <div class="card">
                    <h2>📊 System Status</h2>
                    <div class="status-item">
                        <span>API Server</span>
                        <span class="status-ok">✓ Running</span>
                    </div>
                    <div class="status-item">
                        <span>Environment</span>
                        <span>{settings.ENVIRONMENT if settings else 'Unknown'}</span>
                    </div>
                    <div class="status-item">
                        <span>Version</span>
                        <span>2.1.0</span>
                    </div>
                </div>

                <div class="card">
                    <h2>🛣️ Routes Status</h2>
                    {"".join([f'''
                    <div class="status-item">
                        <span>{r['name'].upper()}</span>
                        <span class="{'status-ok' if r['status'] == '✓' else 'status-error'}">{r['status']}</span>
                    </div>
                    {f'<div class="error-details">{r["error"]}</div>' if r['error'] else ''}
                    ''' for r in routes_status])}
                </div>

                <div class="card">
                    <h2>🔧 Services Status</h2>
                    {"".join([f'''
                    <div class="status-item">
                        <span>{s['name'].capitalize()}</span>
                        <span class="{'status-ok' if s['status'] == '✓' else 'status-error'}">{s['status']}</span>
                    </div>
                    {f'<div class="error-details">{s["error"]}</div>' if s['error'] else ''}
                    ''' for s in services_status])}
                </div>
            </div>

            <div class="test-section">
                <h3>🚀 Quick API Tests</h3>
                <div class="quick-tests">
                    <a href="/health" class="test-button" target="_blank">Health Check</a>
                    <a href="/system-diagnostics" class="test-button" target="_blank">System Diagnostics</a>
                    <a href="/test-database" class="test-button" target="_blank">Test Database</a>
                    <a href="/test-gemini" class="test-button" target="_blank">Test Gemini AI</a>
                    <a href="/test-adzuna" class="test-button" target="_blank">Test Adzuna Jobs</a>
                    <a href="/test-rag" class="test-button" target="_blank">Test RAG Service</a>
                    <a href="/docs" class="test-button" target="_blank">📚 API Documentation</a>
                </div>
            </div>

            <div class="test-section">
                <h3>🎯 Sample Test Queries</h3>
                
                <h4>1. Test Career Journey Start</h4>
                <p><strong>Endpoint:</strong> POST /agent/start-journey</p>
                <textarea id="journeyTest">{{
    "goal": "I want to become a Backend Developer",
    "user_id": "${settings.DEMO_USER_ID if settings else 'demo-user'}",
    "jd_text": "Backend developer needed with Python, SQL, REST APIs experience"
}}</textarea>
                <button class="test-button" onclick="testAPI('/agent/start-journey', 'journeyTest', 'journeyResult')">Run Test</button>
                <div id="journeyResult" class="result-box" style="display:none;"></div>

                <h4>2. Test JD Parsing</h4>
                <p><strong>Endpoint:</strong> POST /test-jd-parse</p>
                <textarea id="jdTest">{{
    "jd_text": "We need a Python developer with 2 years experience in FastAPI, PostgreSQL, and Docker"
}}</textarea>
                <button class="test-button" onclick="testAPI('/test-jd-parse', 'jdTest', 'jdResult')">Run Test</button>
                <div id="jdResult" class="result-box" style="display:none;"></div>

                <h4>3. Test Skill Gap Analysis</h4>
                <p><strong>Endpoint:</strong> POST /test-skill-gap</p>
                <textarea id="skillTest">{{
    "required_skills": ["Python", "SQL", "REST APIs", "Docker"],
    "user_skills": {{"Python": 0.6, "SQL": 0.3}}
}}</textarea>
                <button class="test-button" onclick="testAPI('/test-skill-gap', 'skillTest', 'skillResult')">Run Test</button>
                <div id="skillResult" class="result-box" style="display:none;"></div>

                <h4>4. Test Onboarding</h4>
                <p><strong>Endpoint:</strong> POST /test-onboarding</p>
                <textarea id="onboardTest">{{
    "user_id": "${settings.DEMO_USER_ID if settings else 'demo-user'}",
    "primary_career_goal": "Become a Full Stack Developer",
    "target_role": "Full Stack Developer",
    "current_status": "student",
    "skills": ["JavaScript", "HTML", "CSS"],
    "time_availability": "10-15 hours/week",
    "learning_preference": "hands_on"
}}</textarea>
                <button class="test-button" onclick="testAPI('/test-onboarding', 'onboardTest', 'onboardResult')">Run Test</button>
                <div id="onboardResult" class="result-box" style="display:none;"></div>
            </div>

            <div class="test-section">
                <h3>📖 Available API Endpoints</h3>
                <div>
                    <strong>Authentication:</strong>
                    <a href="/docs#/auth" class="api-link" target="_blank">POST /auth/signup - User Registration</a>
                    <a href="/docs#/auth" class="api-link" target="_blank">POST /auth/signin - User Login</a>
                    <a href="/docs#/auth" class="api-link" target="_blank">POST /auth/signout - User Logout</a>
                    
                    <strong>PEARL Agent:</strong>
                    <a href="/docs#/pearl" class="api-link" target="_blank">POST /agent/start-journey - Start Learning Journey</a>
                    <a href="/docs#/pearl" class="api-link" target="_blank">POST /agent/unlock-module - Unlock Learning Module</a>
                    <a href="/docs#/pearl" class="api-link" target="_blank">POST /agent/complete-action - Complete Module Action</a>
                    
                    <strong>User Features:</strong>
                    <a href="/docs#/api" class="api-link" target="_blank">POST /api/onboarding/start - Start Onboarding</a>
                    <a href="/docs#/api" class="api-link" target="_blank">GET /api/gamification/summary - Get Gamification Status</a>
                    <a href="/docs#/api" class="api-link" target="_blank">GET /api/gamification/leaderboard - Get Leaderboard</a>
                </div>
            </div>
        </div>

        <script>
            async function testAPI(endpoint, inputId, resultId) {{
                const inputElem = document.getElementById(inputId);
                const resultElem = document.getElementById(resultId);
                
                try {{
                    resultElem.style.display = 'block';
                    resultElem.innerHTML = '<p>🔄 Testing...</p>';
                    
                    const data = JSON.parse(inputElem.value);
                    
                    const response = await fetch(endpoint, {{
                        method: 'POST',
                        headers: {{
                            'Content-Type': 'application/json'
                        }},
                        body: JSON.stringify(data)
                    }});
                    
                    const result = await response.json();
                    
                    resultElem.innerHTML = `
                        <p><strong>Status:</strong> ${{response.status}} ${{response.ok ? '✓' : '✗'}}</p>
                        <pre>${{JSON.stringify(result, null, 2)}}</pre>
                    `;
                }} catch (error) {{
                    resultElem.innerHTML = `
                        <p style="color: red;"><strong>Error:</strong> ${{error.message}}</p>
                        <pre>${{error.stack}}</pre>
                    `;
                }}
            }}
        </script>
    </body>
    </html>
    """
    
    return HTMLResponse(content=html_content)


@app.get("/health")
async def health_check():
    """Detailed health check"""
    return {
        "status": "healthy",
        "service": "PEARL API",
        "version": "2.1.0",
        "timestamp": datetime.now().isoformat(),
        "routes": {
            "auth": routes_loaded['auth']['loaded'],
            "pearl": routes_loaded['pearl']['loaded'],
            "api": routes_loaded['api']['loaded']
        },
        "services": {
            "database": services_loaded['database']['loaded'],
            "auth": services_loaded['auth']['loaded'],
            "gemini": services_loaded['gemini']['loaded'],
            "adzuna": services_loaded['adzuna']['loaded'],
            "gamification": services_loaded['gamification']['loaded'],
            "rag": services_loaded['rag']['loaded']
        }
    }


@app.get("/system-diagnostics")
async def system_diagnostics():
    """Comprehensive system diagnostics"""
    diagnostics = {
        "timestamp": datetime.now().isoformat(),
        "routes": {},
        "services": {},
        "config": {},
        "recommendations": []
    }
    
    # Routes diagnostics
    for route, status in routes_loaded.items():
        diagnostics["routes"][route] = {
            "loaded": status['loaded'],
            "error": status['error']
        }
        if not status['loaded']:
            diagnostics["recommendations"].append(f"Fix {route} routes: {status['error']}")
    
    # Services diagnostics
    for service, status in services_loaded.items():
        diagnostics["services"][service] = {
            "loaded": status['loaded'],
            "error": status['error']
        }
        if not status['loaded']:
            diagnostics["recommendations"].append(f"Fix {service} service: {status['error']}")
    
    # Config check
    if settings:
        diagnostics["config"] = {
            "supabase_configured": bool(settings.SUPABASE_URL and settings.SUPABASE_KEY),
            "gemini_configured": bool(settings.GEMINI_API_KEY),
            "adzuna_configured": bool(settings.ADZUNA_APP_ID and settings.ADZUNA_APP_KEY),
            "environment": settings.ENVIRONMENT
        }
    else:
        diagnostics["config"] = {"error": "Settings not loaded"}
        diagnostics["recommendations"].append("Check .env file and config.py")
    
    return diagnostics


@app.get("/test-database")
async def test_database():
    """Test database connectivity"""
    if not db:
        raise HTTPException(status_code=500, detail="Database service not loaded")
    
    try:
        # Test basic query
        result = db.client.table('user_profiles').select('user_id').limit(1).execute()
        
        return {
            "status": "success",
            "message": "Database connection working",
            "test_query": "user_profiles table accessible",
            "sample_data": len(result.data) if result.data else 0
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e),
            "traceback": traceback.format_exc()
        }


@app.get("/test-gemini")
async def test_gemini():
    """Test Gemini AI service"""
    if not gemini:
        raise HTTPException(status_code=500, detail="Gemini service not loaded")
    
    try:
        # Test JD parsing
        test_jd = "Backend developer needed with Python, FastAPI, SQL experience"
        result = gemini.parse_jd(test_jd)
        
        return {
            "status": "success",
            "message": "Gemini AI working",
            "test_input": test_jd,
            "parsed_output": result
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e),
            "traceback": traceback.format_exc()
        }


@app.get("/test-adzuna")
async def test_adzuna():
    """Test Adzuna job service"""
    if not adzuna_service:
        raise HTTPException(status_code=500, detail="Adzuna service not loaded")
    
    try:
        # Test job search
        jobs = adzuna_service.search_jobs(
            query="Python developer",
            location="Chennai",
            max_results=3
        )
        
        return {
            "status": "success",
            "message": "Adzuna API working",
            "jobs_found": len(jobs),
            "sample_jobs": jobs[:2] if jobs else []
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e),
            "traceback": traceback.format_exc()
        }


@app.get("/test-rag")
async def test_rag():
    """Test RAG service for learning resources"""
    if not enhanced_rag:
        raise HTTPException(status_code=500, detail="RAG service not loaded")
    
    try:
        # Test resource retrieval
        resources = enhanced_rag.retrieve_resources("Python", "byte", count=3)
        available_skills = enhanced_rag.get_available_skills()
        
        return {
            "status": "success",
            "message": "RAG service working",
            "available_skills": available_skills,
            "sample_resources": resources
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e),
            "traceback": traceback.format_exc()
        }


# Test models
class JDParseTest(BaseModel):
    jd_text: str

class SkillGapTest(BaseModel):
    required_skills: List[str]
    user_skills: Dict[str, float]

class OnboardingTest(BaseModel):
    user_id: str
    primary_career_goal: str
    target_role: str
    current_status: str = "student"
    skills: List[str] = []
    time_availability: str = "10-15 hours/week"
    learning_preference: str = "mixed"


@app.post("/test-jd-parse")
async def test_jd_parse(request: JDParseTest):
    """Test JD parsing"""
    if not gemini:
        raise HTTPException(status_code=500, detail="Gemini service not available")
    
    try:
        parsed = gemini.parse_jd(request.jd_text)
        return {
            "status": "success",
            "input": request.jd_text,
            "parsed": parsed
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/test-skill-gap")
async def test_skill_gap(request: SkillGapTest):
    """Test skill gap analysis"""
    if not gemini:
        raise HTTPException(status_code=500, detail="Gemini service not available")
    
    try:
        analysis = gemini.analyze_skill_gap(request.required_skills, request.user_skills)
        return {
            "status": "success",
            "input": {
                "required": request.required_skills,
                "current": request.user_skills
            },
            "analysis": analysis
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/test-onboarding")
async def test_onboarding_flow(request: OnboardingTest):
    """Test onboarding flow"""
    if not db:
        raise HTTPException(status_code=500, detail="Database not available")
    
    try:
        # Test data structure
        onboarding_data = {
            "primary_career_goal": request.primary_career_goal,
            "target_role": request.target_role,
            "current_status": request.current_status,
            "skills": request.skills,
            "time_availability": request.time_availability,
            "learning_preference": request.learning_preference
        }
        
        # Try to save (will fail if user doesn't exist, which is ok for testing)
        try:
            success = db.save_onboarding(request.user_id, onboarding_data)
            message = "Onboarding data saved successfully" if success else "Save failed (user may not exist)"
        except Exception as e:
            message = f"Expected error (testing without auth): {str(e)}"
        
        return {
            "status": "success",
            "message": message,
            "data_structure": onboarding_data,
            "note": "Full onboarding requires authenticated user"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api-status")
async def api_status():
    """API status overview"""
    return {
        "status": "online",
        "service": "PEARL API",
        "version": "2.1.0",
        "timestamp": datetime.now().isoformat(),
        "routes": {k: v['loaded'] for k, v in routes_loaded.items()},
        "services": {k: v['loaded'] for k, v in services_loaded.items()},
        "endpoints": {
            "testing_dashboard": "/",
            "health": "/health",
            "diagnostics": "/system-diagnostics",
            "docs": "/docs",
            "auth": "/auth/*",
            "agent": "/agent/*",
            "api": "/api/*"
        }
    }


# Vercel requires a named handler
handler = app

# For local development
if __name__ == "__main__":
    import uvicorn
    
    print("\n" + "="*60)
    print("PEARL Learning Platform - Testing Edition")
    print("="*60)
    print("🚀 Starting server with testing dashboard...")
    print("🔬 Testing Dashboard: http://localhost:8000/")
    print("📚 API Docs: http://localhost:8000/docs")
    print("💚 Health Check: http://localhost:8000/health")
    print("🔍 Diagnostics: http://localhost:8000/system-diagnostics")
    print("="*60 + "\n")
    
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True
    )