import os
import time
import logging
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [%(name)s] %(message)s"
)
logger = logging.getLogger("product-service")

app = FastAPI(title="Product Service", version="1.0.0")

PRODUCTS = {
    "prod-1": {"id": "prod-1", "name": "Cloud Server Instance", "price": 49.99, "stock": 100},
    "prod-2": {"id": "prod-2", "name": "Managed Database Storage", "price": 19.99, "stock": 50},
    "prod-3": {"id": "prod-3", "name": "API Gateway Tier", "price": 9.99, "stock": 200},
}

# Buffer used for OOM simulation
_leak_buffer = []

@app.get("/healthz")
def healthz():
    return {"status": "ok", "service": "product-service"}

@app.get("/ready")
def ready():
    return {"status": "ready", "service": "product-service"}

@app.get("/products")
def list_products():
    logger.info("Listing all products (total: %d)", len(PRODUCTS))
    return {"products": list(PRODUCTS.values())}

@app.get("/products/{product_id}")
def get_product(product_id: str):
    logger.info("Fetching details for product_id=%s", product_id)
    if product_id not in PRODUCTS:
        logger.warning("Product not found: %s", product_id)
        raise HTTPException(status_code=404, detail="Product not found")
    return PRODUCTS[product_id]

# ─── Chaos & Failure Injection Endpoints for RCA Testing ─────────────────────

@app.post("/chaos/oom")
def chaos_oom():
    """Rapidly consumes memory until the cgroup limit is exceeded, triggering k8s OOMKilled (Exit 137)."""
    logger.critical("WARNING: Deliberate memory spike triggered via /chaos/oom! Allocating 500MB...")
    # Allocate in chunks of 50MB
    for i in range(20):
        logger.warning("Allocating memory chunk #%d (50MB)...", i + 1)
        _leak_buffer.append(bytearray(50 * 1024 * 1024))
        time.sleep(0.1)
    return {"status": "Allocated 1GB memory. Container should be terminated shortly by cgroup OOM killer."}

@app.post("/chaos/crash")
def chaos_crash():
    """Forces exit code 1 to test restart loop detection."""
    logger.critical("FATAL: product-service panic! os._exit(1) invoked.")
    os._exit(1)

@app.post("/chaos/latency")
def chaos_latency(seconds: int = 10):
    """Simulates downstream timeout or bottleneck."""
    logger.warning("Simulating high latency: sleeping for %d seconds...", seconds)
    time.sleep(seconds)
    return {"status": f"Slept for {seconds}s"}

