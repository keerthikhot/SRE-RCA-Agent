import os
import hmac
import uuid
import logging
from fastapi import FastAPI, Header, HTTPException, Query
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
import agent
import report
import mailer
import tools

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("sre-agent.app")

app = FastAPI(title="AI SRE Agent & RCA Platform", version="1.0.0")
API_KEY = os.getenv("AGENT_API_KEY", "").strip()
DEFAULT_EMAIL = os.getenv("SES_SENDER", "")
SESSIONS: dict[str, list] = {}

def auth(key: str | None):
    # Only enforce if AGENT_API_KEY is configured
    if API_KEY:
        if not key or not hmac.compare_digest(key, API_KEY):
            raise HTTPException(status_code=401, detail="Invalid or missing x-api-key header")

class ChatIn(BaseModel):
    message: str
    session_id: str | None = None

class RcaIn(BaseModel):
    question: str = "Scan all pods, logs, and events; diagnose any failures and produce an RCA report."
    email_to: list[str] = []

class TestEmailIn(BaseModel):
    to: list[str]

@app.get("/healthz")
def healthz():
    return {"status": "ok", "service": "sre-agent"}

@app.get("/ready")
def ready():
    return {"status": "ready", "service": "sre-agent"}

@app.post("/chat")
def chat(body: ChatIn, x_api_key: str = Header(None)):
    auth(x_api_key)
    sid = body.session_id or str(uuid.uuid4())
    msgs = SESSIONS.setdefault(sid, [])
    answer = agent.chat(msgs, body.message)
    if len(msgs) > 40:
        SESSIONS[sid] = msgs[-20:] if msgs[-20]["role"] == "user" else msgs[-19:]
    return {"session_id": sid, "answer": answer}

@app.post("/rca")
def rca(body: RcaIn, x_api_key: str = Header(None)):
    auth(x_api_key)
    logger.info("Executing RCA for question: %s", body.question)
    data = agent.investigate_and_rca(body.question)
    filename, html_content = report.render_rca(data)
    
    email_result = None
    if body.email_to:
        subject = f"[{data['severity']}] {data['title']}"
        body_summary = report.email_body(data)
        email_result = mailer.send_rca_email(body.email_to, subject, body_summary, html_content, filename)

    return {
        "report_file": filename,
        "emailed": bool(body.email_to),
        "email_status": email_result,
        "rca": data
    }

@app.post("/rca/auto-scan")
def auto_scan(email_to: list[str] = [], x_api_key: str = Header(None)):
    """Automatically scans all namespaces for unhealthy pods, generates an RCA, and emails recipients."""
    auth(x_api_key)
    logger.info("Auto-scanning cluster for issues...")
    issues = tools.scan_cluster_for_issues()
    
    question = ("Auto-scan detected failing pods: " + str(issues)) if issues else "Scan cluster health."
    data = agent.investigate_and_rca(question)
    filename, html_content = report.render_rca(data)

    email_result = None
    if email_to:
        subject = f"[{data['severity']}] Auto-Scan RCA: {data['title']}"
        body_summary = report.email_body(data)
        email_result = mailer.send_rca_email(email_to, subject, body_summary, html_content, filename)

    return {
        "issues_detected": len(issues),
        "report_file": filename,
        "emailed": bool(email_to),
        "email_status": email_result,
        "rca": data
    }

@app.get("/rca/latest", response_class=HTMLResponse)
def get_latest_report():
    """Renders the latest RCA HTML report directly in the browser."""
    if report.LATEST_REPORT and "content" in report.LATEST_REPORT:
        return HTMLResponse(content=report.LATEST_REPORT["content"], status_code=200)
    
    # Generate on the fly if none exists
    data = agent.generate_heuristic_rca()
    _, html_content = report.render_rca(data)
    return HTMLResponse(content=html_content, status_code=200)

@app.post("/rca/test-email")
def test_email(body: TestEmailIn, x_api_key: str = Header(None)):
    auth(x_api_key)
    sample_rca = {
        "title": "Email Delivery Verification Test",
        "severity": "SEV4",
        "confidence": "high",
        "affected_services": ["order-service", "product-service"],
        "stakeholder_summary": "This is a test notification from the SRE Agent verifying AWS SES / SMTP email configuration.",
        "root_cause": "Test trigger executed via /rca/test-email.",
        "resolution": ["Verify the attached HTML report opens cleanly in your browser."],
        "prevention": ["Email alerts are functioning as expected."]
    }
    filename, html_content = report.render_rca(sample_rca)
    result = mailer.send_rca_email(
        body.to,
        "[TEST] SRE Agent Email Delivery Verification",
        report.email_body(sample_rca),
        html_content,
        filename
    )
    return {"status": "sent", "details": result, "recipients": body.to}
