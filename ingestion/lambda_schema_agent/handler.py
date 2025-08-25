
import json, os
from langchain.chat_models import ChatOpenAI

def handler(event, context):
    """Infer schema for a CSV sample."""
    sample_rows = event.get("sample", [])
    llm = ChatOpenAI(openai_api_key=os.environ["OPENAI_API_KEY"], temperature=0)
    prompt = f"Given these CSV rows {sample_rows[:3]}, guess column types as JSON."
    resp = llm.predict(prompt)
    return {"schema": resp, "confidence": 0.8}
