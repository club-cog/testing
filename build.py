#!/usr/bin/env python3
"""Build the password-gated static page into dist/.

Usage: LANDING_PASSWORD=... python3 build.py
"""
import base64
import os
import shutil
import sys

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

ITERATIONS = 600_000
ROOT = os.path.dirname(os.path.abspath(__file__))


def main() -> None:
    password = os.environ.get("LANDING_PASSWORD")
    if not password:
        sys.exit("LANDING_PASSWORD env var is required")

    with open(os.path.join(ROOT, "site", "content.html")) as f:
        content = f.read()
    with open(os.path.join(ROOT, "site", "shell-template.html")) as f:
        shell = f.read()

    salt = os.urandom(16)
    iv = os.urandom(12)
    kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=salt, iterations=ITERATIONS)
    key = kdf.derive(password.encode())
    ct = AESGCM(key).encrypt(iv, content.encode(), None)

    html = (
        shell.replace("__SALT__", base64.b64encode(salt).decode())
        .replace("__IV__", base64.b64encode(iv).decode())
        .replace("__CT__", base64.b64encode(ct).decode())
        .replace("__ITERATIONS__", str(ITERATIONS))
    )

    dist = os.path.join(ROOT, "dist")
    shutil.rmtree(dist, ignore_errors=True)
    os.makedirs(os.path.join(dist, "assets"))
    with open(os.path.join(dist, "index.html"), "w") as f:
        f.write(html)
    for name in os.listdir(os.path.join(ROOT, "site", "assets")):
        shutil.copy(os.path.join(ROOT, "site", "assets", name), os.path.join(dist, "assets", name))
    print("built dist/")


if __name__ == "__main__":
    main()
