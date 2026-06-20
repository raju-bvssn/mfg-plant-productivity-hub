#!/usr/bin/env python3
"""
PlantIQ Edge Signal Publisher
Runs on Raspberry Pi to publish IoT signals to Anypoint MQ.

Usage:
    python simulate_edge.py --plant SHA --station "Station 4" --signal Bin-Depletion --risk High --level 8.0 --minutes 12
    python simulate_edge.py --plant SHA --station "Station 7" --signal Micro-Stoppage --risk Medium --stoppages 4
    python simulate_edge.py --plant FZ  --station "Station 3" --signal Idle-Time     --risk Low

Environment variables (set in .env or export before running):
    AMQ_CLIENT_ID      Anypoint MQ client ID
    AMQ_CLIENT_SECRET  Anypoint MQ client secret
    AMQ_ORG_ID         Anypoint organization ID
    AMQ_ENV_ID         Anypoint environment ID
    AMQ_REGION         Anypoint MQ region (default: us-east-1)
    DEVICE_ID          Device identifier (default: rpi-<hostname>)
"""

import argparse
import json
import os
import sys
import time
import uuid
from datetime import datetime, timezone

import requests

# ---------------------------------------------------------------------------
# Configuration — reads from env vars so secrets never live in this file
# ---------------------------------------------------------------------------
AMQ_TOKEN_URL  = "https://anypoint.mulesoft.com/accounts/oauth2/token"
AMQ_BROKER_URL = "https://mq-{region}.anypoint.mulesoft.com/api/v1"
QUEUE_NAME     = "plantiq-edge-signals"

SIGNAL_TYPES = ["Bin-Depletion", "Micro-Stoppage", "Idle-Time"]
RISK_LEVELS  = ["Low", "Medium", "High"]


# ---------------------------------------------------------------------------
# Token management — caches token in memory, refreshes when near expiry
# ---------------------------------------------------------------------------
class TokenCache:
    def __init__(self, client_id: str, client_secret: str):
        self.client_id     = client_id
        self.client_secret = client_secret
        self._token        = None
        self._expires_at   = 0

    def get(self) -> str:
        if time.time() < self._expires_at - 60:   # refresh 60s before expiry
            return self._token

        resp = requests.post(
            AMQ_TOKEN_URL,
            data={
                "grant_type":    "client_credentials",
                "client_id":     self.client_id,
                "client_secret": self.client_secret,
            },
            timeout=10,
        )
        resp.raise_for_status()
        data = resp.json()
        self._token      = data["access_token"]
        self._expires_at = time.time() + data.get("expires_in", 3600)
        print(f"[token] refreshed, expires in {data.get('expires_in', 3600)}s")
        return self._token


# ---------------------------------------------------------------------------
# Publisher
# ---------------------------------------------------------------------------
class EdgeSignalPublisher:
    def __init__(self, token_cache: TokenCache, org_id: str, env_id: str, region: str):
        self.token_cache = token_cache
        self.base_url = (
            f"{AMQ_BROKER_URL.format(region=region)}"
            f"/organizations/{org_id}/environments/{env_id}"
            f"/destinations/{QUEUE_NAME}/messages"
        )

    def publish(self, payload: dict) -> str:
        message_id = f"sig-{uuid.uuid4().hex[:12]}"
        body = json.dumps(payload)

        resp = requests.put(
            f"{self.base_url}/{message_id}",
            headers={
                "Authorization": f"Bearer {self.token_cache.get()}",
                "Content-Type":  "application/json",
            },
            json={
                "properties": {"contentType": "application/json"},
                "body":       body,
            },
            timeout=10,
        )

        if resp.status_code in (200, 201):
            result = resp.json()
            if result.get("status") == "successful":
                return result.get("messageId", message_id)
            raise RuntimeError(f"MQ rejected message: {result}")

        resp.raise_for_status()


# ---------------------------------------------------------------------------
# Payload builder
# ---------------------------------------------------------------------------
def build_payload(args) -> dict:
    return {
        "plant_code":         args.plant,
        "station":            args.station,
        "signal_type":        args.signal,
        "risk":               args.risk,
        "current_level":      args.level,
        "minutes_to_empty":   args.minutes,
        "stoppages_per_hour": args.stoppages,
        "image_url":          args.image_url,
        "device_id":          args.device_id,
        "captured_at":        datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def parse_args():
    parser = argparse.ArgumentParser(description="PlantIQ edge signal publisher for Raspberry Pi")

    parser.add_argument("--plant",     required=True,              help="Plant code e.g. SHA, FZ")
    parser.add_argument("--station",   required=True,              help='Station name e.g. "Station 4"')
    parser.add_argument("--signal",    required=True, choices=SIGNAL_TYPES, help="Signal type")
    parser.add_argument("--risk",      required=True, choices=RISK_LEVELS,  help="Risk level")
    parser.add_argument("--level",     type=float, default=None,   help="Current bin fill level (%%)")
    parser.add_argument("--minutes",   type=int,   default=None,   help="Minutes to empty (Bin-Depletion)")
    parser.add_argument("--stoppages", type=float, default=None,   help="Stoppages per hour (Micro-Stoppage)")
    parser.add_argument("--image-url", default=None,               help="S3 image URL (optional)")
    parser.add_argument("--device-id", default=f"rpi-{os.uname().nodename}", help="Device ID")

    return parser.parse_args()


def load_config() -> dict:
    config = {
        "client_id":     os.environ.get("AMQ_CLIENT_ID"),
        "client_secret": os.environ.get("AMQ_CLIENT_SECRET"),
        "org_id":        os.environ.get("AMQ_ORG_ID"),
        "env_id":        os.environ.get("AMQ_ENV_ID"),
        "region":        os.environ.get("AMQ_REGION", "us-east-1"),
    }
    missing = [k for k, v in config.items() if not v and k != "region"]
    if missing:
        print(f"[error] Missing environment variables: {', '.join(missing.upper() for missing in missing)}")
        print("        Set them in .env or export before running.")
        sys.exit(1)
    return config


def main():
    args   = parse_args()
    config = load_config()

    token_cache = TokenCache(config["client_id"], config["client_secret"])
    publisher   = EdgeSignalPublisher(
        token_cache,
        org_id=config["org_id"],
        env_id=config["env_id"],
        region=config["region"],
    )

    payload = build_payload(args)

    print(f"[signal] {payload['signal_type']} | {payload['plant_code']} {payload['station']} | risk={payload['risk']}")
    print(f"[payload] {json.dumps(payload, indent=2)}")

    try:
        message_id = publisher.publish(payload)
        print(f"[published] message_id={message_id} → queue={QUEUE_NAME}")
    except Exception as e:
        print(f"[error] publish failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
