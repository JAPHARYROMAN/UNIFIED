"""Local-only deterministic Ed25519 fixture signer for the Phase 8 Anvil gate.

The helper derives its test-only seed from a domain-separated label on every
invocation. It never reads, writes, prints, or accepts private key material.
Only public keys and signatures are emitted.
"""

from __future__ import annotations

import hashlib
import sys
from typing import NoReturn

from Crypto.PublicKey import ECC
from Crypto.Signature import eddsa

DOMAINS = {"home", "satellite"}
SEED_DOMAIN = b"UNIFIED_PHASE8_LOCAL_OBSERVER_V1:"


def fail(message: str) -> NoReturn:
    raise SystemExit(f"ERROR: {message}")


def key_for(domain: str) -> ECC.EccKey:
    if domain not in DOMAINS:
        fail("domain must be home or satellite")
    seed = hashlib.sha512(SEED_DOMAIN + domain.encode("ascii")).digest()[:32]
    # PyCryptodome accepts a documented 32-byte Ed25519 seed; its stub is narrower.
    return ECC.construct(curve="Ed25519", seed=seed)  # type: ignore[arg-type]


def decode_hex(value: str, expected_bytes: int, label: str) -> bytes:
    if (
        not value.startswith("0x")
        or value != value.lower()
        or len(value) != 2 + expected_bytes * 2
    ):
        fail(f"{label} must be 0x-prefixed {expected_bytes}-byte hex")
    try:
        return bytes.fromhex(value[2:])
    except ValueError as error:
        fail(f"{label} is not hexadecimal: {error}")


def main() -> None:
    if len(sys.argv) < 3:
        fail("usage: sign_phase8_observer.py public|sign|verify DOMAIN [HEX ...]")
    operation, domain = sys.argv[1:3]
    key = key_for(domain)
    if operation == "public" and len(sys.argv) == 3:
        print("0x" + key.public_key().export_key(format="raw").hex())
        return
    if operation == "sign" and len(sys.argv) == 4:
        commitment = decode_hex(sys.argv[3], 32, "commitment")
        signature = eddsa.new(key, mode="rfc8032", context=b"").sign(commitment)
        print("0x" + signature.hex())
        return
    if operation == "verify" and len(sys.argv) == 5:
        commitment = decode_hex(sys.argv[3], 32, "commitment")
        signature = decode_hex(sys.argv[4], 64, "signature")
        try:
            eddsa.new(key.public_key(), mode="rfc8032", context=b"").verify(
                commitment, signature
            )
        except ValueError as error:
            fail(f"signature verification failed: {error}")
        print("valid")
        return
    fail("invalid operation or argument count")


if __name__ == "__main__":
    main()
