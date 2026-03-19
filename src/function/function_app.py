import azure.functions as func
import json
import logging
import uuid
from datetime import datetime, timezone

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)


@app.route(route="process", methods=["POST"])
def process_message(req: func.HttpRequest) -> func.HttpResponse:
    """
    Accepts a POST request with a JSON body containing a 'message' field.
    Returns a JSON response with the original message, a UTC timestamp,
    and a unique request ID.
    """
    logging.info("process_message function triggered.")

    request_id = str(uuid.uuid4())

    # ── Parse JSON body ───────────────────────────────────────────────────────
    try:
        body = req.get_json()
    except ValueError:
        return func.HttpResponse(
            json.dumps({"error": "Request body must be valid JSON."}),
            status_code=400,
            mimetype="application/json",
        )

    # ── Validate required field ───────────────────────────────────────────────
    if not isinstance(body, dict) or "message" not in body:
        return func.HttpResponse(
            json.dumps({"error": "Missing required field: 'message'."}),
            status_code=400,
            mimetype="application/json",
        )

    message = body["message"]

    if not isinstance(message, str) or not message.strip():
        return func.HttpResponse(
            json.dumps({"error": "'message' must be a non-empty string."}),
            status_code=400,
            mimetype="application/json",
        )

    # ── Build response ────────────────────────────────────────────────────────
    response_body = {
        "message": message,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "request_id": request_id,
    }

    return func.HttpResponse(
        json.dumps(response_body),
        status_code=200,
        mimetype="application/json",
    )
