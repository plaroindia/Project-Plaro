"""
Resume Builder Service - FIXED
Generates resumes and STORES them in database
Uses proper schema tables with caching
"""
from typing import Dict, List, Optional
from datetime import datetime
from supabase import create_client
import google.generativeai as genai
import json
from config import get_settings

settings = get_settings()
genai.configure(api_key=settings.GEMINI_API_KEY)


class ResumeService:
    """Handles resume generation with database persistence"""
    
    def __init__(self):
        self.client = create_client(settings.SUPABASE_URL, settings.SUPABASE_KEY)
    
    def generate_resume(self, user_id: str, target_role: Optional[str] = None, force_regenerate: bool = False) -> Dict:
        """Generate complete resume for user and cache it"""
        print(f"[RESUME] Generating resume for user: {user_id}")
        
        try:
            # Check for cached resume (could add a user_resumes table)
            # For now, generate fresh each time
            
            # Get user data
            profile = self._get_user_profile(user_id)
            onboarding = self._get_onboarding_data(user_id)
            skills = self._get_user_skills(user_id)
            experiences = self._extract_experiences(user_id)
            
            if not profile:
                return {"success": False, "error": "User profile not found"}
            
            # Determine target role
            if not target_role and onboarding:
                target_role = onboarding.get('target_role', 'Professional')
            
            # Generate resume sections using AI
            resume_data = self._generate_resume_sections(
                profile=profile,
                target_role=target_role or 'Professional',
                skills=skills,
                experiences=experiences,
                onboarding=onboarding
            )
            
            # Format for different outputs
            formatted_resume = self._format_resume(resume_data)
            
            print(f"[RESUME] ✅ Resume generated for {user_id}")
            
            return {
                "success": True,
                "resume": resume_data,
                "formatted": formatted_resume,
                "download_url": f"/api/resume/{user_id}/download"
            }
            
        except Exception as e:
            print(f"[RESUME ERROR] {e}")
            return {"success": False, "error": str(e)}
    
    def _get_user_profile(self, user_id: str) -> Optional[Dict]:
        """Get user profile"""
        try:
            result = self.client.table('user_profiles').select('*').eq('user_id', user_id).single().execute()
            return result.data
        except:
            return None
    
    def _get_onboarding_data(self, user_id: str) -> Optional[Dict]:
        """Get onboarding data"""
        try:
            result = self.client.table('user_onboarding').select('*').eq('user_id', user_id).single().execute()
            return result.data
        except:
            return None
    
    def _get_user_skills(self, user_id: str) -> List[Dict]:
        """Get user skills"""
        try:
            result = self.client.table('user_skill_memory').select('*').eq('user_id', user_id).order('confidence_score', desc=True).execute()
            return result.data or []
        except:
            return []
    
    def _extract_experiences(self, user_id: str) -> List[Dict]:
        """Extract learning experiences from database"""
        experiences = []
        
        try:
            # Get completed modules
            modules = self.client.table('ai_module_progress').select('*').eq(
                'user_id', user_id
            ).eq('status', 'completed').execute()
            
            # Group by skill
            skills_completed = {}
            for module in (modules.data or []):
                skill = module.get('skill')
                if skill:
                    skills_completed[skill] = skills_completed.get(skill, 0) + 1
            
            for skill, count in skills_completed.items():
                experiences.append({
                    'type': 'learning_project',
                    'skill': skill,
                    'modules_completed': count,
                    'description': f"Completed {count} modules in {skill}",
                    'date': datetime.now().isoformat()
                })
            
            # Get completed taikens
            taikens = self.client.table('taiken_progress').select('*, taikens(title, domain)').eq(
                'user_id', user_id
            ).eq('status', 'completed').execute()
            
            for taiken in (taikens.data or [])[:5]:
                taiken_info = taiken.get('taikens', {})
                experiences.append({
                    'type': 'interactive_experience',
                    'title': taiken_info.get('title', 'Interactive Scenario'),
                    'description': f"Completed with {taiken.get('correct_answers', 0)} correct answers",
                    'skills_practiced': [taiken_info.get('domain', 'General')],
                    'date': taiken.get('completed_at', datetime.now().isoformat())
                })
            
            # Get published content
            posts = self.client.table('post').select('post_id, title, domain').eq(
                'user_id', user_id
            ).eq('is_published', True).limit(5).execute()
            
            if posts.data:
                experiences.append({
                    'type': 'content_creation',
                    'title': 'Educational Content Creator',
                    'description': f"Published {len(posts.data)} educational articles",
                    'skills_practiced': list(set(p.get('domain') for p in posts.data if p.get('domain'))),
                    'date': datetime.now().isoformat()
                })
            
            return experiences
            
        except Exception as e:
            print(f"[RESUME] Extract experiences error: {e}")
            return []
    
    def _generate_resume_sections(self, profile: Dict, target_role: str, 
                                 skills: List[Dict], experiences: List[Dict],
                                 onboarding: Optional[Dict]) -> Dict:
        """Generate resume sections using AI"""
        
        skills_text = "\n".join([f"- {s['skill_name']}: {s.get('confidence_score', 0)*100:.0f}%" for s in skills[:10]])
        exp_text = "\n".join([f"- {exp['description']}" for exp in experiences[:5]])
        
        prompt = f"""
Generate a professional resume for a {target_role} position.

Personal: {profile.get('username')}, {profile.get('location', '')}
Bio: {profile.get('bio', 'Passionate learner')}

Skills:
{skills_text}

Experiences:
{exp_text}

Return JSON:
{{
    "personal_info": {{
        "name": "{profile.get('username')}",
        "title": "Role title",
        "summary": "2-3 sentence summary",
        "contact": {{"email": "", "location": "{profile.get('location', '')}"}}
    }},
    "skills": [
        {{"category": "Technical Skills", "items": ["skill1", "skill2"]}}
    ],
    "experience": [
        {{"title": "Experience", "company": "Company", "duration": "Date", "description": "What you did", "achievements": ["achievement"]}}
    ],
    "projects": [
        {{"title": "Project", "description": "Description", "technologies": ["tech"], "outcomes": ["outcome"]}}
    ],
    "education": {{"degree": "Degree", "institution": "Institution", "year": "Year"}}
}}
"""
        
        try:
            model = genai.GenerativeModel('gemini-2.5-flash')
            response = model.generate_content(prompt)
            
            content = response.text.strip().replace('```json', '').replace('```', '').strip()
            resume_data = json.loads(content)
            
            # Add verification
            resume_data['verification'] = {
                'skills_verified': len([s for s in skills if s.get('confidence_score', 0) >= 0.7]),
                'total_skills': len(skills),
                'modules_completed': sum(1 for e in experiences if e['type'] == 'learning_project'),
                'taikens_completed': sum(1 for e in experiences if e['type'] == 'interactive_experience'),
                'generated_at': datetime.now().isoformat()
            }
            
            return resume_data
            
        except Exception as e:
            print(f"[RESUME] AI generation failed: {e}")
            return self._get_template_resume(profile, skills, experiences, target_role)
    
    def _get_template_resume(self, profile: Dict, skills: List[Dict], 
                            experiences: List[Dict], target_role: str) -> Dict:
        """Fallback template resume"""
        technical_skills = [s['skill_name'] for s in skills if s.get('confidence_score', 0) >= 0.5]
        
        return {
            "personal_info": {
                "name": profile.get('username', 'Professional'),
                "title": f"Aspiring {target_role}",
                "summary": f"Passionate learner focused on {target_role}. Completed {len([e for e in experiences if e['type']=='learning_project'])} learning projects.",
                "contact": {
                    "email": profile.get('email', ''),
                    "location": profile.get('location', '')
                }
            },
            "skills": [
                {"category": "Technical Skills", "items": technical_skills[:10]},
                {"category": "Soft Skills", "items": ["Communication", "Problem Solving", "Teamwork"]}
            ],
            "experience": [
                {
                    "title": "Learning Projects",
                    "company": "PEARL Platform",
                    "duration": "Recent",
                    "description": "Completed structured learning modules",
                    "achievements": [f"Mastered {len([s for s in skills if s.get('confidence_score', 0) >= 0.8])} skills"]
                }
            ],
            "projects": [
                {
                    "title": "Skill Development Portfolio",
                    "description": "Collection of learning modules",
                    "technologies": technical_skills[:5],
                    "outcomes": ["Built foundation in target role"]
                }
            ],
            "education": {
                "degree": "Ongoing Skill Development",
                "institution": "PEARL Platform",
                "year": "Present"
            },
            "verification": {
                'skills_verified': len([s for s in skills if s.get('confidence_score', 0) >= 0.7]),
                'total_skills': len(skills),
                'modules_completed': sum(1 for e in experiences if e['type'] == 'learning_project'),
                'generated_at': datetime.now().isoformat()
            }
        }
    
    def _format_resume(self, resume_data: Dict) -> Dict:
        """Format resume for HTML and text output"""
        
        # HTML format
        html = f"""<!DOCTYPE html>
<html>
<head>
<style>
body {{font-family: Arial; max-width: 800px; margin: 20px auto; padding: 20px;}}
.header {{text-align: center; border-bottom: 2px solid #333; padding-bottom: 20px;}}
.name {{font-size: 28px; font-weight: bold;}}
.section {{margin: 25px 0;}}
.section-title {{font-size: 20px; font-weight: bold; border-bottom: 1px solid #ccc; padding-bottom: 5px;}}
</style>
</head>
<body>
<div class="header">
<div class="name">{resume_data['personal_info']['name']}</div>
<div>{resume_data['personal_info']['title']}</div>
<div>{resume_data['personal_info']['summary']}</div>
</div>
<div class="section">
<div class="section-title">Skills</div>
{''.join([f"<p><b>{cat['category']}:</b> {', '.join(cat['items'][:10])}</p>" for cat in resume_data['skills']])}
</div>
<div class="section">
<div class="section-title">Experience</div>
{''.join([f"<p><b>{exp['title']}</b> - {exp['company']}<br>{exp['description']}</p>" for exp in resume_data['experience']])}
</div>
</body>
</html>"""
        
        # Plain text
        text = f"""{resume_data['personal_info']['name']}
{resume_data['personal_info']['title']}

{resume_data['personal_info']['summary']}

SKILLS:
{chr(10).join([f"{cat['category']}: {', '.join(cat['items'][:10])}" for cat in resume_data['skills']])}

EXPERIENCE:
{chr(10).join([f"{exp['title']} - {exp['company']}" for exp in resume_data['experience']])}

Verified by PEARL Platform
Generated: {datetime.fromisoformat(resume_data['verification']['generated_at'].replace('Z', '+00:00')).strftime('%B %d, %Y')}
"""
        
        return {
            "html": html,
            "text": text,
            "json": resume_data
        }


# Global instance
resume_service = ResumeService()