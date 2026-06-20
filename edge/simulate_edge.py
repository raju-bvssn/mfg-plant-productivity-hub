#!/usr/bin/env python3
"""
PlantIQ Edge Signal Publisher
Runs on Raspberry Pi to publish IoT signals to Anypoint MQ.

Usage:
    python simulate_edge.py --key hacksst --plant SHA --station "Station 4" --signal Bin-Depletion --risk High --level 8.0 --minutes 12
    python simulate_edge.py --key hacksst --plant SHA --station "Station 7" --signal Micro-Stoppage --risk Medium --stoppages 4
    python simulate_edge.py --key hacksst --plant FZ  --station "Station 3" --signal Idle-Time     --risk Low

Requirements:
    pip install requests cryptography
"""

import argparse
import base64
import json
import sys
import time
import uuid
from datetime import datetime, timezone

import requests
from cryptography.fernet import Fernet, InvalidToken
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

# ---------------------------------------------------------------------------
# Hardcoded config — non-sensitive org/env identifiers
# ---------------------------------------------------------------------------
AMQ_ORG_ID    = "364ee0be-9e1b-4b19-aa99-356dc3e65f9d"
AMQ_ENV_ID    = "d5221ae7-8326-43fb-9915-374379fcacfb"
AMQ_REGION    = "us-east-1"
DEVICE_ID     = "rpi-sha-sta4-001"
QUEUE_NAME    = "plantiq-edge-signals"

AMQ_TOKEN_URL = "https://anypoint.mulesoft.com/accounts/oauth2/token"
AMQ_BROKER_URL = f"https://mq-{AMQ_REGION}.anypoint.mulesoft.com/api/v1"

# ---------------------------------------------------------------------------
# Encrypted credentials — decrypted at runtime using the --key argument
# ---------------------------------------------------------------------------
ENC_CLIENT_ID     = "gAAAAABqNw3G2i7w1KQSzyR_E3fo-iqUABBtSIHUlBvPOV3iJgSFJ3CI7aab4I8nf8g8YMgkkeg8dewa_w_kPm9oR19wKwLI0q7fLdzp27I_a3Nu0YmBe3SJuuMySqTTUV51zCoWuOFF"
ENC_CLIENT_SECRET = "gAAAAABqNw3GG78nafDzlRUDLJ_LAyGtqMwNtcneEcJRupeaw1fTKkSPN_PAIulXE3NWq-s-_cZdcfIjnYaE4GDSBxGpCsyp34zvoWPTQZ3nw_dl-Dd_clYYSfwzd52voXOnI8ultodS"

SIGNAL_TYPES = ["Bin-Depletion", "Micro-Stoppage", "Idle-Time"]
RISK_LEVELS  = ["Low", "Medium", "High"]


# ---------------------------------------------------------------------------
# Decryption
# ---------------------------------------------------------------------------
def derive_fernet(passphrase: str) -> Fernet:
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=b"plantiq-edge-salt",
        iterations=100000,
    )
    key = base64.urlsafe_b64encode(kdf.derive(passphrase.encode()))
    return Fernet(key)


def decrypt_credentials(passphrase: str) -> tuple[str, str]:
    try:
        f = derive_fernet(passphrase)
        client_id     = f.decrypt(ENC_CLIENT_ID.encode()).decode()
        client_secret = f.decrypt(ENC_CLIENT_SECRET.encode()).decode()
        return client_id, client_secret
    except InvalidToken:
        print("[error] Invalid decryption key. Check --key argument.")
        sys.exit(1)


# ---------------------------------------------------------------------------
# Token management — caches in memory, refreshes 60s before expiry
# ---------------------------------------------------------------------------
class TokenCache:
    def __init__(self, client_id: str, client_secret: str):
        self.client_id     = client_id
        self.client_secret = client_secret
        self._token        = None
        self._expires_at   = 0

    def get(self) -> str:
        if self._token and time.time() < self._expires_at - 60:
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
        data             = resp.json()
        self._token      = data["access_token"]
        self._expires_at = time.time() + data.get("expires_in", 3600)
        print(f"[token] refreshed, expires in {data.get('expires_in', 3600)}s")
        return self._token


# ---------------------------------------------------------------------------
# Publisher
# ---------------------------------------------------------------------------
class EdgeSignalPublisher:
    def __init__(self, token_cache: TokenCache):
        self.token_cache = token_cache
        self.base_url = (
            f"{AMQ_BROKER_URL}"
            f"/organizations/{AMQ_ORG_ID}"
            f"/environments/{AMQ_ENV_ID}"
            f"/destinations/{QUEUE_NAME}/messages"
        )

    def publish(self, payload: dict) -> str:
        message_id = f"sig-{uuid.uuid4().hex[:12]}"

        resp = requests.put(
            f"{self.base_url}/{message_id}",
            headers={
                "Authorization": f"Bearer {self.token_cache.get()}",
                "Content-Type":  "application/json",
            },
            json={
                "properties": {"contentType": "application/json"},
                "body":       json.dumps(payload),
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
        "device_id":          DEVICE_ID,
        "captured_at":        datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def parse_args():
    parser = argparse.ArgumentParser(description="PlantIQ edge signal publisher for Raspberry Pi")

    parser.add_argument("--key",       required=True,                       help="Decryption key for credentials")
    parser.add_argument("--plant",     required=True,                       help="Plant code e.g. SHA, FZ")
    parser.add_argument("--station",   required=True,                       help='Station name e.g. "Station 4"')
    parser.add_argument("--signal",    required=True, choices=SIGNAL_TYPES, help="Signal type")
    parser.add_argument("--risk",      required=True, choices=RISK_LEVELS,  help="Risk level")
    parser.add_argument("--level",     type=float,    default=None,         help="Current bin fill level (%%)")
    parser.add_argument("--minutes",   type=int,      default=None,         help="Minutes to empty (Bin-Depletion)")
    parser.add_argument("--stoppages", type=float,    default=None,         help="Stoppages per hour (Micro-Stoppage)")
    parser.add_argument("--image-url", default=None,                        help="S3 image URL (optional)")

    return parser.parse_args()


def main():
    args = parse_args()

    client_id, client_secret = decrypt_credentials(args.key)

    token_cache = TokenCache(client_id, client_secret)
    publisher   = EdgeSignalPublisher(token_cache)
    payload     = build_payload(args)

    print(f"[signal]  {payload['signal_type']} | {payload['plant_code']} {payload['station']} | risk={payload['risk']}")
    print(f"[payload] {json.dumps(payload, indent=2)}")

    try:
        message_id = publisher.publish(payload)
        print(f"[published] message_id={message_id} → queue={QUEUE_NAME}")
    except Exception as e:
        print(f"[error] publish failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
