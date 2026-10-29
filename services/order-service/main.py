import os
import sys
import logging
import requests
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [%(name)s] %(message)s"
)
logger = logging.getLogger("order-service")

app = FastAPI(title="Order Service", version="1.0.0")

PRODUCT_SERVICE_URL = os.getenv("PRODUCT_SERVICE_URL", "http://product-service.apps.svc.cluster.local:8000")

# In-memory orders store
ORDERS = [
    {"id": "ord-101", "product_id": "prod-1", "quantity": 2, "status": "CONFIRMED", "customer": "alice@example.com"},
    {"id": "ord-102", "product_id": "prod-2", "quantity": 1, "status": "PENDING", "customer": "bob@example.com"},
]

class CreateOrderRequest(BaseModel):
    product_id: str
    quantity: int
    customer: str

@app.get("/healthz")
def healthz():
    return {"status": "ok", "service": "order-service"}

@app.get("/ready")
def ready():
    return {"status": "ready", "service": "order-service"}

@app.get("/orders")
def get_orders():
    logger.info("Fetching all orders (total: %d)", len(ORDERS))
    return {"orders": ORDERS, "count": len(ORDERS)}

@app.post("/orders", status_code=status.HTTP_201_CREATED)
def create_order(order: CreateOrderRequest):
    logger.info("Received order request for product_id=%s qty=%d", order.product_id, order.quantity)
    
    # Verify stock with product-service
    try:
        url = f"{PRODUCT_SERVICE_URL}/products/{order.product_id}"
        resp = requests.get(url, timeout=3.0)
        if resp.status_code == 404:
            raise HTTPException(status_code=400, detail=f"Product {order.product_id} does not exist")
        product_data = resp.json()
        if product_data.get("stock", 0) < order.quantity:
            raise HTTPException(status_code=400, detail=f"Insufficient inventory for {order.product_id}")
    except requests.exceptions.RequestException as e:
        logger.error("Failed to connect to product-service at %s: %s", PRODUCT_SERVICE_URL, str(e))
        raise HTTPException(status_code=503, detail="product-service unavailable")

    new_order = {
        "id": f"ord-{len(ORDERS) + 101}",
        "product_id": order.product_id,
        "quantity": order.quantity,
        "status": "CONFIRMED",
        "customer": order.customer,
    }
    ORDERS.append(new_order)
    logger.info("Order created successfully: %s", new_order["id"])
    return new_order

# ─── Chaos & Failure Injection Endpoints for RCA Testing ─────────────────────

@app.post("/chaos/crash")
def chaos_crash():
    """Simulates sudden container failure to trigger CrashLoopBackOff."""
    logger.critical("FATAL: Unhandled panic / segmentation fault simulated! Exiting process with code 1.")
    # Exit process abruptly to simulate pod crash
    os._exit(1)

@app.post("/chaos/db-error")
def chaos_db_error():
    """Simulates database connection pool exhaustion and stack trace."""
    logger.error("DBConnectionPoolExhausted: Unable to acquire connection from pool [max_size=20, active=20, timeout=5000ms]")
    logger.error("Traceback (most recent call last):\n"
                 "  File '/app/db.py', line 142, in get_connection\n"
                 "    conn = pool.get_connection(timeout=5)\n"
                 "psycopg2.OperationalError: FATAL: remaining connection slots are reserved for non-replication superuser connections")
    raise HTTPException(
        status_code=500,
        detail="Internal Server Error: Database connection pool exhausted. Active connections: 20/20."
    )

@app.post("/chaos/500")
def chaos_500():
    """Simulates an internal 500 error."""
    logger.error("Unexpected runtime error in OrderService: NullReferencePointer / KeyError('payment_gateway_token')")
    raise HTTPException(status_code=500, detail="NullReferenceException: payment token not found in session context")

