"""
Job Retrieval Service using Adzuna API
Retrieves real job descriptions from Adzuna and matches to user skills
"""

import requests
from config import get_settings
from typing import List, Dict, Optional

settings = get_settings()


class AdzunaJobService:
    """
    Retrieves real job descriptions from Adzuna API
    Supports job search, filtering, and skill-based matching
    """
    
    BASE_URL = "https://api.adzuna.com/v1/api/jobs"
    
    def __init__(self):
        self.app_id = settings.ADZUNA_APP_ID
        self.app_key = settings.ADZUNA_APP_KEY
        self.country = "in"  # India
        self.timeout = 10
        
        if not self.app_id or not self.app_key:
            print("[WARNING] Adzuna API credentials not configured. Job search will not work.")
    
    def search_jobs(
        self,
        query: str,
        location: str = "Chennai",
        max_results: int = 10
    ) -> List[Dict]:
        """
        Search for jobs matching a query
        
        Args:
            query: Job title or skill to search for
            location: City/location for job search
            max_results: Maximum number of results to return
        
        Returns:
            List of job dictionaries with metadata
        """
        
        if not self.app_id or not self.app_key:
            print("[ERROR] Adzuna credentials not configured")
            return []
        
        url = f"{self.BASE_URL}/{self.country}/search/1"
        
        params = {
            "app_id": self.app_id,
            "app_key": self.app_key,
            "results_per_page": max_results,
            "what": query,
            "where": location,
            "content-type": "application/json"
        }
        
        try:
            print(f"[ADZUNA] 🔍 Searching jobs: '{query}' in {location}")
            
            response = requests.get(url, params=params, timeout=self.timeout)
            response.raise_for_status()
            data = response.json()
            
            jobs = []
            for result in data.get("results", []):
                job = {
                    "job_id": result.get("id"),
                    "title": result.get("title"),
                    "company": result.get("company", {}).get("display_name"),
                    "location": result.get("location", {}).get("display_name"),
                    "description": result.get("description"),
                    "salary_min": result.get("salary_min"),
                    "salary_max": result.get("salary_max"),
                    "url": result.get("redirect_url"),
                    "created": result.get("created"),
                    "category": result.get("category", {}).get("label")
                }
                jobs.append(job)
            
            print(f"[ADZUNA] ✅ Found {len(jobs)} jobs")
            return jobs
        
        except requests.exceptions.RequestException as e:
            print(f"[ERROR] Adzuna API request failed: {e}")
            return []
        except Exception as e:
            print(f"[ERROR] Job search failed: {e}")
            return []
    
    def get_job_details(self, job_id: str) -> Optional[Dict]:
        """
        Get full details of a specific job
        
        Args:
            job_id: Unique identifier for the job
        
        Returns:
            Full job details or None if not found
        """
        
        if not self.app_id or not self.app_key:
            return None
        
        url = f"{self.BASE_URL}/{self.country}/jobs/{job_id}"
        
        params = {
            "app_id": self.app_id,
            "app_key": self.app_key
        }
        
        try:
            response = requests.get(url, params=params, timeout=self.timeout)
            response.raise_for_status()
            return response.json()
        
        except Exception as e:
            print(f"[ERROR] Job details fetch failed: {e}")
            return None
    
    def match_jobs_to_skills(
        self,
        user_skills: dict,
        target_role: str,
        location: str = "Chennai"
    ) -> List[Dict]:
        """
        Find jobs that match user's current skills
        Performs keyword matching between job descriptions and user skills
        
        Args:
            user_skills: Dict of {skill_name: confidence_score}
            target_role: Target job role/title to search for
            location: Location for job search
        
        Returns:
            List of matched jobs sorted by match percentage
        """
        
        # Search for target role
        jobs = self.search_jobs(query=target_role, location=location, max_results=20)
        
        if not jobs:
            print(f"[ADZUNA] No jobs found for '{target_role}'")
            return []
        
        matched_jobs = []
        
        for job in jobs:
            description_lower = (job.get("description") or "").lower()
            title_lower = (job.get("title") or "").lower()
            combined_text = f"{title_lower} {description_lower}"
            
            match_count = 0
            matched_skills = []
            
            # Check for skill mentions in job description
            for skill in user_skills.keys():
                skill_lower = skill.lower()
                # Search for exact skill or common variations
                if skill_lower in combined_text:
                    match_count += 1
                    matched_skills.append(skill)
            
            # Calculate match percentage
            match_percentage = (match_count / len(user_skills)) * 100 if user_skills else 0
            
            # Include jobs with at least 30% skill overlap
            if match_percentage >= 30:
                job["match_percentage"] = round(match_percentage, 1)
                job["matched_skills"] = matched_skills
                job["missing_skills"] = [s for s in user_skills.keys() if s not in matched_skills]
                job["skill_gap"] = len(job["missing_skills"]) / len(user_skills) if user_skills else 0
                matched_jobs.append(job)
        
        # Sort by match percentage (descending)
        matched_jobs.sort(key=lambda x: x["match_percentage"], reverse=True)
        
        print(f"[ADZUNA] ✅ Matched {len(matched_jobs)} jobs with >30% skill overlap")
        
        return matched_jobs
    
    def get_skill_demand(self, location: str = "Chennai") -> Dict[str, int]:
        """
        Analyze job market to find most in-demand skills
        
        Args:
            location: Location to analyze
        
        Returns:
            Dict of {skill: job_count}
        """
        
        if not self.app_id or not self.app_key:
            print("[WARNING] Adzuna credentials not configured for skill demand analysis")
            return {}
        
        try:
            # Search for popular tech skills with better sample size
            top_skills = ["Python", "JavaScript", "SQL", "React", "AWS", "Machine Learning"]
            skill_demand = {}
            
            for skill in top_skills:
                try:
                    jobs = self.search_jobs(query=skill, location=location, max_results=5)
                    if jobs:
                        skill_demand[skill] = len(jobs)
                    else:
                        print(f"[ADZUNA] No jobs found for {skill}, skipping")
                except Exception as skill_error:
                    print(f"[WARNING] Failed to get demand for {skill}: {skill_error}")
                    continue
            
            if skill_demand:
                print(f"[ADZUNA] 📊 Skill demand analysis complete: {len(skill_demand)} skills analyzed")
            else:
                print(f"[ADZUNA] ⚠️  No skill demand data retrieved (API may be unavailable)")
            
            return skill_demand
        
        except Exception as e:
            print(f"[ERROR] Skill demand analysis failed: {e}")
            return {}


# Global instance for use across the application
adzuna_service = AdzunaJobService()
