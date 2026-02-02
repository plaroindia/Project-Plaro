#!/usr/bin/env python3
"""
PEARL Backend Automated Test Suite
Run this to validate all backend functionality
"""

import requests
import json
import sys
from datetime import datetime
from typing import Dict, List, Tuple

# Configuration
BASE_URL = "http://localhost:8000"
DEMO_USER_ID = "56e9193c-25ce-4383-9fe3-4f81c4fa9d83"

# Color codes for terminal output
class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

def print_header(text: str):
    """Print formatted header"""
    print(f"\n{Colors.BOLD}{Colors.BLUE}{'='*60}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{text}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{'='*60}{Colors.RESET}\n")

def print_test(name: str, passed: bool, details: str = ""):
    """Print test result"""
    status = f"{Colors.GREEN}✓ PASS{Colors.RESET}" if passed else f"{Colors.RED}✗ FAIL{Colors.RESET}"
    print(f"{status} | {name}")
    if details:
        print(f"       {details}")

def test_endpoint(method: str, endpoint: str, data: dict = None) -> Tuple[bool, dict, str]:
    """Test a single endpoint"""
    url = f"{BASE_URL}{endpoint}"
    try:
        if method == "GET":
            response = requests.get(url, timeout=10)
        elif method == "POST":
            response = requests.post(url, json=data, timeout=30)
        else:
            return False, {}, "Unsupported method"
        
        response.raise_for_status()
        return True, response.json(), ""
    except requests.exceptions.Timeout:
        return False, {}, "Request timed out"
    except requests.exceptions.ConnectionError:
        return False, {}, "Connection failed - is server running?"
    except requests.exceptions.HTTPError as e:
        return False, {}, f"HTTP {e.response.status_code}"
    except Exception as e:
        return False, {}, str(e)

def run_test_suite():
    """Run complete test suite"""
    
    print_header("🔬 PEARL Backend Automated Test Suite")
    print(f"Target: {BASE_URL}")
    print(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
    
    results = {
        "total": 0,
        "passed": 0,
        "failed": 0,
        "tests": []
    }
    
    # Test 1: Server Health
    print_header("1️⃣  Server Health Tests")
    
    passed, data, error = test_endpoint("GET", "/health")
    results["total"] += 1
    if passed and data.get("status") == "healthy":
        results["passed"] += 1
        print_test("Health Check", True, "Server is running")
        
        # Check route status
        routes = data.get("routes", {})
        for route, status in routes.items():
            results["total"] += 1
            if status:
                results["passed"] += 1
                print_test(f"Route: {route}", True)
            else:
                results["failed"] += 1
                print_test(f"Route: {route}", False, "Not loaded")
        
        # Check service status
        services = data.get("services", {})
        for service, status in services.items():
            results["total"] += 1
            if status:
                results["passed"] += 1
                print_test(f"Service: {service}", True)
            else:
                results["failed"] += 1
                print_test(f"Service: {service}", False, "Not loaded")
    else:
        results["failed"] += 1
        print_test("Health Check", False, error)
        print(f"\n{Colors.RED}Server is not responding. Please start the server first.{Colors.RESET}\n")
        return results
    
    # Test 2: Database
    print_header("2️⃣  Database Tests")
    
    passed, data, error = test_endpoint("GET", "/test-database")
    results["total"] += 1
    if passed and data.get("status") == "success":
        results["passed"] += 1
        print_test("Database Connection", True, data.get("message"))
    else:
        results["failed"] += 1
        print_test("Database Connection", False, error)
    
    # Test 3: Gemini AI
    print_header("3️⃣  Gemini AI Tests")
    
    # Test JD parsing
    jd_test = {
        "jd_text": "Backend developer with Python, FastAPI, SQL, Docker. 2 years experience."
    }
    passed, data, error = test_endpoint("POST", "/test-jd-parse", jd_test)
    results["total"] += 1
    if passed and data.get("status") == "success":
        results["passed"] += 1
        parsed = data.get("parsed", {})
        print_test("JD Parsing", True, f"Extracted role: {parsed.get('role')}")
        print(f"       Skills found: {', '.join(parsed.get('required_skills', []))}")
    else:
        results["failed"] += 1
        print_test("JD Parsing", False, error)
    
    # Test skill gap analysis
    skill_test = {
        "required_skills": ["Python", "SQL", "Docker"],
        "user_skills": {"Python": 0.6, "SQL": 0.3}
    }
    passed, data, error = test_endpoint("POST", "/test-skill-gap", skill_test)
    results["total"] += 1
    if passed and data.get("status") == "success":
        results["passed"] += 1
        analysis = data.get("analysis", {})
        print_test("Skill Gap Analysis", True, 
                   f"Readiness: {analysis.get('overall_readiness', 0)*100:.1f}%")
    else:
        results["failed"] += 1
        print_test("Skill Gap Analysis", False, error)
    
    # Test 4: Adzuna Jobs
    print_header("4️⃣  Job Retrieval Tests")
    
    passed, data, error = test_endpoint("GET", "/test-adzuna")
    results["total"] += 1
    if passed and data.get("status") == "success":
        results["passed"] += 1
        jobs_count = data.get("jobs_found", 0)
        print_test("Adzuna Job Search", True, f"Found {jobs_count} jobs")
        if jobs_count > 0:
            sample = data.get("sample_jobs", [{}])[0]
            print(f"       Sample: {sample.get('title')} at {sample.get('company')}")
    else:
        results["failed"] += 1
        print_test("Adzuna Job Search", False, error)
    
    # Test 5: RAG Service
    print_header("5️⃣  Learning Resources Tests")
    
    passed, data, error = test_endpoint("GET", "/test-rag")
    results["total"] += 1
    if passed and data.get("status") == "success":
        results["passed"] += 1
        skills = data.get("available_skills", [])
        print_test("RAG Service", True, f"Available skills: {len(skills)}")
        print(f"       Sample skills: {', '.join(skills[:5])}")
        
        resources = data.get("sample_resources", [])
        if resources:
            print(f"       Sample resource: {resources[0].get('title')}")
    else:
        results["failed"] += 1
        print_test("RAG Service", False, error)
    
    # Test 6: PEARL Agent Journey
    print_header("6️⃣  PEARL Agent Tests")
    
    journey_test = {
        "goal": "I want to become a Backend Developer",
        "user_id": DEMO_USER_ID,
        "jd_text": "Backend developer with Python, SQL, REST APIs experience"
    }
    passed, data, error = test_endpoint("POST", "/agent/start-journey", journey_test)
    results["total"] += 1
    if passed and data.get("session_id"):
        results["passed"] += 1
        session_id = data.get("session_id")
        print_test("Start Learning Journey", True, f"Session: {session_id[:8]}...")
        
        # Show extracted skills
        parsed = data.get("parsed_jd", {})
        print(f"       Required skills: {', '.join(parsed.get('required_skills', []))}")
        
        # Show learning paths
        paths = data.get("learning_paths", {})
        print(f"       Learning paths created: {len(paths)}")
    else:
        results["failed"] += 1
        print_test("Start Learning Journey", False, error)
    
    # Test 7: Onboarding
    print_header("7️⃣  Onboarding Tests")
    
    onboard_test = {
        "user_id": DEMO_USER_ID,
        "primary_career_goal": "Become a Full Stack Developer",
        "target_role": "Full Stack Developer",
        "current_status": "student",
        "skills": ["JavaScript", "HTML", "CSS"],
        "time_availability": "10-15 hours/week",
        "learning_preference": "hands_on"
    }
    passed, data, error = test_endpoint("POST", "/test-onboarding", onboard_test)
    results["total"] += 1
    if passed and data.get("status") == "success":
        results["passed"] += 1
        print_test("Onboarding Flow", True, "Data structure validated")
    else:
        results["failed"] += 1
        print_test("Onboarding Flow", False, error)
    
    # Print Summary
    print_header(" Test Summary")
    
    pass_rate = (results["passed"] / results["total"] * 100) if results["total"] > 0 else 0
    
    print(f"Total Tests: {results['total']}")
    print(f"{Colors.GREEN}Passed: {results['passed']}{Colors.RESET}")
    print(f"{Colors.RED}Failed: {results['failed']}{Colors.RESET}")
    print(f"Pass Rate: {pass_rate:.1f}%\n")
    
    if results["failed"] == 0:
        print(f"{Colors.GREEN}{Colors.BOLD}✓ All tests passed! Backend is working correctly.{Colors.RESET}\n")
        return 0
    else:
        print(f"{Colors.YELLOW}⚠ Some tests failed. Check the details above.{Colors.RESET}\n")
        return 1

def check_server_running():
    """Check if server is running"""
    try:
        response = requests.get(f"{BASE_URL}/health", timeout=3)
        return True
    except:
        return False

if __name__ == "__main__":
    print(f"\n{Colors.BOLD}Starting PEARL Backend Tests...{Colors.RESET}\n")
    
    # Check if server is running
    if not check_server_running():
        print(f"{Colors.RED} Server is not running at {BASE_URL}{Colors.RESET}")
        print(f"{Colors.YELLOW}Please start the server first:{Colors.RESET}")
        print(f"   python main_enhanced.py\n")
        sys.exit(1)
    
    # Run tests
    exit_code = run_test_suite()
    
    # Additional info
    print_header(" Next Steps")
    print("1. Open testing dashboard: http://localhost:8000/")
    print("2. View API documentation: http://localhost:8000/docs")
    print("3. Check system diagnostics: http://localhost:8000/system-diagnostics")
    print("4. Review TESTING_GUIDE.md for detailed testing procedures\n")
    
    sys.exit(exit_code)