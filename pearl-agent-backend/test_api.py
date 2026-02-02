import google.generativeai as genai

# Configure with your API key
genai.configure(api_key="AIzaSyD0bFYOkkJC9r73HEr2B5Jq-V6MIQUtN1U")

try:
    # print("📋 Listing all available Gemini models:\n")
    
    # for model in genai.list_models():
    #     if 'generateContent' in model.supported_generation_methods:
    #         print(f"✅ Model: {model.name}")
    #         print(f"   Display Name: {model.display_name}")
    #         print(f"   Description: {model.description}")
    #         print(f"   Supported methods: {model.supported_generation_methods}")
    #         print("-" * 80)
    
    print("\n🧪 Testing with gemini-2.5-flash:")
    model = genai.GenerativeModel('gemini-2.5-flash')
    response = model.generate_content("Say hello")
    print("✅ Gemini API Key works!")
    print(f"Response: {response.text}")
    
except Exception as e:
    print(f"❌ Error: {e}")