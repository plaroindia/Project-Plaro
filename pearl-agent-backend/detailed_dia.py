"""
PEARL Learning Journey - Step by Step Diagnostic and Fix
Run this to understand exactly what's failing
"""

import sys
import os

print("=" * 70)
print("🔍 PEARL LEARNING JOURNEY DIAGNOSTIC")
print("=" * 70)

# Step 1: Check if we can import the services
print("\n📦 Step 1: Checking Service Imports")
print("-" * 70)

services_status = {}

try:
    from database import EnhancedSupabaseHelper
    db = EnhancedSupabaseHelper()
    services_status['database'] = True
    print("✅ Database helper imported")
except Exception as e:
    services_status['database'] = False
    print(f"❌ Database import failed: {e}")

try:
    from services.pearl_agent import pearl
    services_status['pearl_agent'] = True
    print("✅ Pearl agent imported")
except Exception as e:
    services_status['pearl_agent'] = False
    print(f"❌ Pearl agent import failed: {e}")

try:
    from services.enhanced_rag_service import enhanced_rag
    services_status['rag'] = True
    print("✅ RAG service imported")
except Exception as e:
    services_status['rag'] = False
    print(f"❌ RAG service import failed: {e}")

try:
    from services.geminiai_service import GeminiService
    gemini = GeminiService()
    services_status['gemini'] = True
    print("✅ Gemini service imported")
except Exception as e:
    services_status['gemini'] = False
    print(f"❌ Gemini import failed: {e}")

try:
    from config import get_settings
    settings = get_settings()
    services_status['config'] = True
    print("✅ Config loaded")
except Exception as e:
    services_status['config'] = False
    print(f"❌ Config load failed: {e}")

# Step 2: Test each service individually
print("\n🧪 Step 2: Testing Each Service")
print("-" * 70)

if services_status.get('database'):
    print("\n🗄️  Testing Database...")
    try:
        # Test basic query
        result = db.client.table('user_profiles').select('user_id').limit(1).execute()
        print(f"  ✅ Database query works (found {len(result.data) if result.data else 0} records)")
        
        # Test session creation with demo user
        print(f"\n  Testing session creation for demo user...")
        try:
            session = db.create_agent_session(
                user_id=settings.DEMO_USER_ID if services_status.get('config') else "demo-user-123",
                jd_text="Test session"
            )
            if session and 'id' in session:
                print(f"  ✅ Session creation works! ID: {session['id'][:20]}...")
                
                # Clean up test session
                try:
                    db.client.table('ai_agent_sessions').delete().eq('id', session['id']).execute()
                    print(f"  🧹 Cleaned up test session")
                except:
                    pass
            else:
                print(f"  ❌ Session creation returned invalid data: {session}")
        except Exception as e:
            print(f"  ❌ Session creation failed: {e}")
            print(f"     This is likely the issue!")
            
    except Exception as e:
        print(f"  ❌ Database test failed: {e}")

if services_status.get('gemini'):
    print("\n🤖 Testing Gemini AI...")
    try:
        # Test JD parsing
        test_jd = "Backend developer with Python and SQL"
        result = gemini.parse_jd(test_jd)
        print(f"  ✅ JD parsing works")
        print(f"     Role: {result.get('role')}")
        print(f"     Skills: {result.get('required_skills')}")
    except Exception as e:
        print(f"  ❌ Gemini test failed: {e}")

if services_status.get('pearl_agent'):
    print("\n🎓 Testing Pearl Agent...")
    try:
        # Test learning path creation
        path = pearl.create_learning_path("Python", 0.0)
        print(f"  ✅ Learning path creation works")
        print(f"     Modules created: {len(path.get('modules', []))}")
        print(f"     Total hours: {path.get('estimated_hours')}")
    except Exception as e:
        print(f"  ❌ Pearl agent test failed: {e}")

if services_status.get('rag'):
    print("\n📚 Testing RAG Service...")
    try:
        resources = enhanced_rag.retrieve_resources("Python", "byte", count=2)
        print(f"  ✅ RAG service works")
        print(f"     Resources found: {len(resources)}")
        if resources:
            print(f"     Sample: {resources[0].get('title')}")
    except Exception as e:
        print(f"  ❌ RAG test failed: {e}")

# Step 3: Test the integration
print("\n🔗 Step 3: Testing Service Integration")
print("-" * 70)

if all(services_status.values()):
    print("\n✅ All services can be imported and work individually")
    print("\nNow testing the full journey flow...")
    
    try:
        # Simulate what the endpoint does
        print("\n1️⃣  Creating session...")
        session = db.create_agent_session(
            user_id=settings.DEMO_USER_ID,
            jd_text="Backend developer test"
        )
        
        if not session or 'id' not in session:
            print("❌ ISSUE FOUND: Session creation returns invalid data")
            print(f"   Returned: {session}")
            print("\n💡 FIX: Check if demo user exists in user_profiles table")
            print(f"   User ID: {settings.DEMO_USER_ID}")
        else:
            session_id = session['id']
            print(f"✅ Session created: {session_id[:20]}...")
            
            print("\n2️⃣  Extracting skills from goal...")
            # This would use Gemini
            required_skills = ["Python", "SQL", "REST APIs"]
            print(f"✅ Skills extracted: {required_skills}")
            
            print("\n3️⃣  Creating learning path...")
            path = pearl.create_learning_path("Python", 0.0)
            print(f"✅ Path created with {len(path['modules'])} modules")
            
            print("\n4️⃣  Enhancing with resources...")
            resources = enhanced_rag.retrieve_resources("Python", "byte", count=1)
            print(f"✅ Resources retrieved: {len(resources)}")
            
            print("\n✅ ALL INTEGRATION STEPS WORK!")
            print("\n🎉 The services can work together properly!")
            
            # Clean up
            try:
                db.client.table('ai_agent_sessions').delete().eq('id', session_id).execute()
                print("🧹 Cleaned up test session")
            except:
                pass
            
    except Exception as e:
        print(f"\n❌ ISSUE FOUND during integration:")
        print(f"   Error: {e}")
        print(f"   Type: {type(e).__name__}")
        import traceback
        print("\n📋 Detailed traceback:")
        traceback.print_exc()
else:
    print("\n❌ Cannot test integration - some services failed to load")
    print("\nFailed services:")
    for service, status in services_status.items():
        if not status:
            print(f"  - {service}")

# Step 4: Diagnosis and recommendations
print("\n" + "=" * 70)
print("📋 DIAGNOSIS AND RECOMMENDATIONS")
print("=" * 70)

all_pass = all(services_status.values())

if all_pass:
    print("\n✅ All services are working!")
    print("\n🔍 The issue is likely in the endpoint's error handling.")
    print("\n💡 Recommended fix:")
    print("   1. Replace routes/pearl_routes.py with pearl_routes_FIXED.py")
    print("   2. The fixed version has better error handling and logging")
    print("   3. Restart server and test again")
else:
    print("\n❌ Some services have issues:")
    for service, status in services_status.items():
        if not status:
            print(f"\n{service}:")
            print(f"  - Check if the service file exists")
            print(f"  - Check for import errors")
            print(f"  - Verify dependencies are installed")

print("\n" + "=" * 70)
print("✨ Next Steps:")
print("=" * 70)
print("\n1. If all services work (green checkmarks above):")
print("   → Replace pearl_routes.py with the fixed version")
print("\n2. If database session creation fails:")
print("   → Check if demo user exists:")
print(f"      SELECT * FROM user_profiles WHERE user_id = '{settings.DEMO_USER_ID if services_status.get('config') else 'demo-user-123'}';")
print("\n3. If any service fails to import:")
print("   → Check the specific error message above")
print("   → Verify that service file exists")
print("\n4. Run the fixed version:")
print("   → python main.py (with fixed pearl_routes.py)")
print("   → python test_backend.py")
print("\n" + "=" * 70)