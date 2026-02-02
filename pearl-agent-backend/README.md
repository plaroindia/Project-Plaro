# 🚀 PEARL – From Skills to Jobs, Intelligently
💡 What is Pearl?

Pearl is an AI-powered web & mobile platform(Plaro) that guides users from:
skill assessment → learning → real-world projects → resume → job recommendations.
A working MVP already exists.

## Problem

### Learners struggle to:

Identify missing skills

Follow a clear career roadmap

Gain real-world project experience

Build industry-ready resumes

Find jobs aligned with their skills

## Our Solution (End-to-End Career Journey)

Assess user skills & career goals

Identify skill gaps using AI

Generate a personalized career roadmap

Provide real-world project experience

Auto-build resumes

Recommend skill-matched jobs

## ✨ Key Innovations (Why Pearl is Different)
🤖 1. AI Skill Gap Analysis

Compares user skills with industry requirements and shows what to retain, improve, and acquire.

🗺️ 2. Personalized Career Roadmap

Adaptive roadmap with milestones based on user progress and feedback.

🛠️ 3. Project Suggestion Engine

After 2–3 weeks of learning, users receive real-world, role-specific projects to gain hands-on experience.

🎭 4. Taiken – Real-Time Role-Based Scenario Learning

Users learn by stepping into real job roles (HR, Developer, Analyst) and experiencing real workplace scenarios that motivate learning.

📄 5. Auto Resume Builder

Resumes are automatically generated and updated using skills, projects, and assessments.

💼 6. Real-Time Job Recommendations

Jobs are recommended based on completed roadmap, projects, and resume readiness.

## 🏗️ Architecture

```
┌──────────────────────────────┐
│           USER                │
│ • Enter Skills                │
│ • Career Goal                 │
│ • Feedback (stress, interest) │
└─────────────┬────────────────┘
              │
              ▼
┌──────────────────────────────┐
│        PEARL PLATFORM         │
│ • Central orchestration       │
│ • Routes data to AI Agents    │
│ • Manages learning & projects │
└─────────────┬────────────────┘
              │
              ▼
┌──────────────────────────────┐
│        AI AGENT LAYER        │
│ • Skill Gap Agent            │
│ • Project Suggestion Agent   │
│ • Job Recommendation Agent   │
└─────────────┬────────────────┘
              │
              ▼
┌──────────────────────────────┐
│    LEARNING & PROJECTS        │
│ • Taiken: Role-based Scenarios│
│ • Courses & Practice Modules  │
│ • Real-World Projects         │
└─────────────┬────────────────┘
              │
              ▼
┌──────────────────────────────┐
│       AUTO RESUME BUILDER     │
│ • Generates Resume from Skills│
│   Projects & Assessments      │
│ • Updates Dynamically         │
└─────────────┬────────────────┘
              │
              ▼
┌──────────────────────────────┐
│       JOB RECOMMENDATIONS     │
│ • Personalized Jobs           │
│ • Matches Skills, Projects,   │
│   Resume                      │
└──────────────────────────────┘


```

## 🛠️ Tech Stack

### AI & Intelligence
- **Pearl AI Engine** – Core intelligence layer for skill analysis, roadmap generation, and job matching  
- **Google Gemini API** – Natural language understanding, content generation, and learning recommendations  

### APIs & Integrations
- **Adzuna API** – Real-time job market data and personalized job recommendations  
- **edX API** – Access to structured learning resources and course metadata  

### Backend
- **Python** – Core backend logic and AI orchestration  
- **FastAPI** – High-performance API framework for agent-based workflows  
- **Supabase (PostgreSQL)** – Authentication, database, and real-time data storage  

### Frontend
- **HTML5** – Semantic structure  
- **CSS3** – Responsive and modern UI styling  
- **JavaScript** – Dynamic user interactions and data handling  

### Mobile Application
- **Dart** – Cross-platform mobile development language  
- **Flutter** – Mobile app framework for Android and iOS  

### Development Tools
- **VS Code** – Primary development environment  
- **Git & GitHub** – Version control and collaboration  

### Deployment & Hosting
- **Vercel** – Serverless deployment for web services  
- **Environment-Based Configuration** – Secure and scalable deployment setup  

## 📦 Installation

### Prerequisites
Ensure you have the following installed and configured:
- Python 3.12+
- Supabase account
- Google Gemini API key
- Adzuna API access

### Setup

1. **Clone the repository**
```bash
git clone https://github.com/plaroindia/Pearl.git
cd Pearl
```

2. **Install dependencies**
```bash
pip install -r requirements.txt
```

3. **Configure environment variables**
```bash
cp .env.example .env
# Edit .env with your credentials
```

Required variables:
```env
SUPABASE_URL=your_supabase_project_url
SUPABASE_KEY=your_supabase_anon_key
GEMINI_API_KEY=your_gemini_api_key
ADZUNA_APP_ID=your_adzuna_app_id
ADZUNA_API_KEY=your_adzuna_api_key
EDX_API_KEY=your_edx_api_key
DEMO_USER_ID=your_user_id
ENVIRONMENT=development
```

4. **Run locally**
```bash
uvicorn api.index:app --reload
```

Visit `http://localhost:8000/docs` for API documentation.

## 🚀 Deployment

### Vercel Deployment

1. **Push to GitHub**
```bash
git push origin main
```

2. **Import to Vercel**
- Connect your GitHub repository
- Framework: Other
- Root Directory: Leave empty
- Vercel auto-detects `api/index.py`

3. **Add Environment Variables**
In Vercel dashboard → Settings → Environment Variables:
- `SUPABASE_URL`
- `SUPABASE_KEY`
- `GEMINI_API_KEY`
- ADZUNA_APP_ID
- ADZUNA_API_KEY
- EDX_API_KEY
- `DEMO_USER_ID`
- `ENVIRONMENT=production`

4. **Deploy**
Vercel automatically deploys on push to main branch.

## 📡 API Endpoints

### Core Endpoints

**Start Learning Journey**
```http
POST /agent/start-journey
{
  "goal": "Become a Backend Developer",
  "jd_text": "Optional job description",
  "user_id": "user123"
}
```

**Get Current Action**
```http
GET /agent/current-action/{session_id}
```

**Complete Action**
```http
POST /agent/complete-action
{
  "session_id": "uuid",
  "skill": "Python",
  "module_id": 1,
  "action_index": 0,
  "completion_data": {"completed": true}
}
```

**Submit Checkpoint**
```http
POST /agent/submit-checkpoint
{
  "session_id": "uuid",
  "skill": "Python",
  "module_id": 1,
  "answers": [0, 2, 1, 3]
}
```

**Get Progress**
```http
GET /agent/progress/{session_id}/{skill}
```

## 🗃️ Database Schema

### Key Tables
- `ai_agent_sessions` - Learning sessions and paths
- `ai_module_progress` - Module completion tracking
- `ai_action_completions` - Individual action records
- `ai_checkpoint_results` - Quiz results and scores
- `user_skill_memory` - User skill confidence levels

## 🎯 Use Cases

1. **Career Transitions**: Break down new role requirements into achievable steps
2. **Skill Gap Analysis**: Identify and address specific knowledge gaps
3. **Structured Learning**: Convert informal learning into organized paths
4. **Progress Validation**: Ensure comprehension through checkpoints
5. **Resource Curation**: Access vetted learning materials

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Commit changes with clear messages
4. Submit a pull request

## 📄 License

MIT License - See LICENSE file for details

## 🙏 Acknowledgments

- Google Gemini AI for natural language processing
- Supabase for database infrastructure
- Free learning platforms (freeCodeCamp, YouTube, etc.)

## 📞 Support

For issues and questions:
- GitHub Issues: [Create an issue](https://github.com/plaroindia/Pearl/issues)
- Email: support@plaro.com

---

Built with ❤️ by the PLARO team
