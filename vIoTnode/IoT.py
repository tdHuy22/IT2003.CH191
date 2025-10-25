#!/usr/bin/env python3
"""
MQTT publisher (Python) with:
- mTLS (client cert/key + CA)
- AES-256-GCM payload encryption (shared key + fixed AAD)
- Random publishing to topics: sensor/temp, sensor/rain, sensor/wind
- JSON wrapper: {"data": "<base64(iv||tag||cipher)>"} 

Usage:
  export MQTT_BROKER_HOST="your-broker-host"
  export MQTT_BROKER_PORT="8883"
  export MQTT_CLIENT_CERT="/path/to/client.crt"
  export MQTT_CLIENT_KEY="/path/to/client.key"
  export MQTT_CA_CERT="/path/to/ca.crt"
  export SHARED_KEY_B64="<base64 32-byte key>"
  export SHARED_AAD="iot-shared-aad-v1"    # optional
  python mqtt_pub_mtls_aesgcm.py
"""

import os
import time
import json
import base64
import random
import logging
from typing import Tuple
import ssl
from dotenv import load_dotenv
load_dotenv()

import paho.mqtt.client as mqtt
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

# --- Config / env ---
BROKER_HOST = os.getenv("MQTT_BROKER_HOST", "127.0.0.1")
BROKER_PORT = int(os.getenv("MQTT_BROKER_PORT", 1883))
CLIENT_CERT = os.getenv("MQTT_CLIENT_CERT")
CLIENT_KEY = os.getenv("MQTT_CLIENT_KEY")
CA_CERT = os.getenv("MQTT_CA_CERT")

if BROKER_PORT == 8883:
    if not CLIENT_CERT or not CLIENT_KEY or not CA_CERT:
        raise SystemExit("Please set MQTT_CLIENT_CERT, MQTT_CLIENT_KEY and MQTT_CA_CERT env vars")

# Shared symmetric key (base64) - must be 32 bytes when decoded
SHARED_KEY_B64 = os.getenv("SHARED_KEY_B64")
if not SHARED_KEY_B64:
    raise SystemExit("Please set SHARED_KEY_B64 env var (base64 32-byte key)")

SHARED_KEY = base64.b64decode(SHARED_KEY_B64)
if len(SHARED_KEY) != 32:
    raise SystemExit("SHARED_KEY_B64 must decode to 32 bytes (AES-256 key)")

# AAD (fixed)
SHARED_AAD = os.getenv("SHARED_AAD", "iot-lab-shared").encode("utf8")

TOPICS = ["sensor/temp", "sensor/rain", "sensor/wind"]

CLIENT_ID = os.getenv("MQTT_CLIENT_ID", f"py-pub-{random.randint(1000,9999)}")

# Logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("mqtt-pub")

# --- AES-GCM encrypt function ---
def encrypt_number_aes_gcm(key: bytes, aad: bytes, value: float) -> str:
    """
    Encrypt a numeric value (or string representation) with AES-256-GCM.
    Returns base64(iv || tag || ciphertext)
    """
    aesgcm = AESGCM(key)
    iv = os.urandom(12)  # 96-bit nonce recommended
    plaintext = str(value).encode("utf8")
    ct = aesgcm.encrypt(iv, plaintext, aad)  # returns (ciphertext || tag) in cryptography AESGCM
    # cryptography's AESGCM encrypt returns ciphertext||tag; we will store tag after iv
    # but we need tag separate: last 16 bytes of ct
    tag = ct[-16:]
    ciphertext = ct[:-16]
    out = iv + tag + ciphertext
    return base64.b64encode(out).decode("ascii")

# --- MQTT callbacks ---
def on_connect(client, userdata, flags, rc):
    if rc == 0:
        logger.info(f"Connected to broker {BROKER_HOST}:{BROKER_PORT} (client_id={CLIENT_ID})")
    else:
        logger.error(f"Failed to connect, rc={rc}")

def on_disconnect(client, userdata, rc):
    logger.info(f"Disconnected (rc={rc})")

def on_publish(client, userdata, mid):
    logger.debug(f"Published mid={mid}")

# --- Build MQTT client with mTLS ---
def create_mqtt_client() -> mqtt.Client:
    client = mqtt.Client(client_id=CLIENT_ID, protocol=mqtt.MQTTv311)
    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    client.on_publish = on_publish

    # # TLS / mTLS setup
    # # Set TLS options; verify server cert with CA, and present client cert/key
    # tls_context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile=CA_CERT)
    # tls_context.load_cert_chain(certfile=CLIENT_CERT, keyfile=CLIENT_KEY)
    # # Optionally enforce TLS versions etc:
    # tls_context.options |= ssl.OP_NO_TLSv1 | ssl.OP_NO_TLSv1_1

    # client.tls_set_context(tls_context)

    # # Enforce hostname check (default)
    # client.tls_insecure_set(False)
#=========================================================================================#
    # TLS / mTLS setup only for port 8883
    if BROKER_PORT == 8883:
        # Set TLS options; verify server cert with CA, and present client cert/key
        tls_context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile=CA_CERT)
        tls_context.load_cert_chain(certfile=CLIENT_CERT, keyfile=CLIENT_KEY)
        # Enforce TLSv1.2 or higher (match Mosquitto bridge_tls_version tlsv1.3)
        tls_context.minimum_version = ssl.TLSVersion.TLSv1_2
        client.tls_set_context(tls_context)
        # Enforce hostname check (default)
        client.tls_insecure_set(False)
        logger.info("TLS enabled for port 8883")

    return client

# --- Publisher loop ---
def publish_loop(client: mqtt.Client, interval_range: Tuple[float, float] = (1.0, 5.0)):
    try:
        while True:
            # pick a topic at random and generate a value
            topic = random.choice(TOPICS)
            if "temp" in topic:
                value = round(random.uniform(15.0, 35.0), 2)  # Celsius
            elif "rain" in topic:
                value = round(random.uniform(0.0, 50.0), 2)   # mm/h
            else:
                value = round(random.uniform(0.0, 25.0), 2)   # m/s

            # encrypt numeric value
            enc_b64 = encrypt_number_aes_gcm(SHARED_KEY, SHARED_AAD, value)
            payload = json.dumps({"data": enc_b64})

            # publish (QoS 1 as reasonable default)
            try:
                result = client.publish(topic, payload, qos=0)
                # result is MQTTMessageInfo; we can wait for success or not
                logger.info(f"Published encrypted -> topic={topic}, value={value}")
            except Exception as e:
                logger.error("Publish exception: %s", e)

            # sleep random interval
            # sleep_t = random.uniform(interval_range[0], interval_range[1])
            sleep_t = 0
            time.sleep(sleep_t)

    except KeyboardInterrupt:
        logger.info("Interrupted by user, finishing...")

# --- Main ---
def main():
    client = create_mqtt_client()
    # connect (blocking)
    logger.info(f"Connecting to {BROKER_HOST}:{BROKER_PORT}{' with mTLS' if BROKER_PORT == 8883 else ''}")
    client.connect(BROKER_HOST, BROKER_PORT, keepalive=60)
    client.loop_start()
    try:
        publish_loop(client)
    finally:
        client.loop_stop()
        client.disconnect()

if __name__ == "__main__":
    main()
