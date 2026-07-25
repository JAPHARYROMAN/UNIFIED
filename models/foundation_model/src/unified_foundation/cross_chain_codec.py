"""Canonical Phase 8 ABI digest helpers used by the Python golden vectors."""

from __future__ import annotations

from dataclasses import dataclass

from Crypto.Hash import keccak

WORD_BYTES = 32
UINT256_LIMIT = 1 << 256
MESSAGE_DOMAIN = "UNIFIED_XCHAIN_MESSAGE_V1"
FINALITY_DOMAIN = "UNIFIED_SYNTHETIC_FINALITY_V1"
RECOVERY_AUTHORIZATION_DOMAIN = "UNIFIED_XCHAIN_RECOVERY_AUTHORIZATION_V2"


def _uint_word(value: int) -> bytes:
    if value < 0 or value >= UINT256_LIMIT:
        raise ValueError("value is outside uint256")
    return value.to_bytes(WORD_BYTES, byteorder="big")


def _exact_bytes(value: bytes, length: int, field: str) -> bytes:
    if len(value) != length:
        raise ValueError(f"{field} must contain {length} bytes")
    return value


def _address_word(value: bytes, field: str) -> bytes:
    return bytes(12) + _exact_bytes(value, 20, field)


def _dynamic_string_tail(value: str) -> bytes:
    encoded = value.encode("utf-8")
    padding = (-len(encoded)) % WORD_BYTES
    return _uint_word(len(encoded)) + encoded + bytes(padding)


def _abi_encode_dynamic_domain(domain: str, static_words: tuple[bytes, ...]) -> bytes:
    for index, word in enumerate(static_words):
        _exact_bytes(word, WORD_BYTES, f"word {index}")
    argument_count = len(static_words) + 1
    return (
        _uint_word(argument_count * WORD_BYTES)
        + b"".join(static_words)
        + _dynamic_string_tail(domain)
    )


def _keccak256(value: bytes) -> bytes:
    digest = keccak.new(digest_bits=256)
    digest.update(value)
    return digest.digest()


@dataclass(frozen=True)
class CanonicalUftLocked:
    lock_id: bytes
    loan_id: bytes
    canonical_token: bytes
    home_bridge_hub: bytes
    wrapped_token: bytes
    destination_recipient: bytes
    amount: int


def encode_canonical_uft_locked(payload: CanonicalUftLocked) -> bytes:
    return b"".join(
        (
            _exact_bytes(payload.lock_id, 32, "lock_id"),
            _exact_bytes(payload.loan_id, 32, "loan_id"),
            _address_word(payload.canonical_token, "canonical_token"),
            _address_word(payload.home_bridge_hub, "home_bridge_hub"),
            _address_word(payload.wrapped_token, "wrapped_token"),
            _address_word(payload.destination_recipient, "destination_recipient"),
            _uint_word(payload.amount),
        )
    )


def canonical_uft_locked_payload_hash(payload: CanonicalUftLocked) -> bytes:
    return _keccak256(encode_canonical_uft_locked(payload))


@dataclass(frozen=True)
class LoanCancellationAuthorizationInput:
    loan_router: bytes
    loan_id: bytes
    funding_lock_id: bytes
    disbursement_message_id: bytes
    disbursement_tombstone_hash: bytes
    amount: int
    policy_hash: bytes
    authorization_nonce: int
    valid_until: int
    reason_code: bytes
    authorizer_set_hash: bytes
    authorizer_set_version: int


def encode_loan_cancellation_authorization(
    authorization: LoanCancellationAuthorizationInput,
) -> bytes:
    return b"".join(
        (
            _address_word(authorization.loan_router, "loan_router"),
            _exact_bytes(authorization.loan_id, 32, "loan_id"),
            _exact_bytes(authorization.funding_lock_id, 32, "funding_lock_id"),
            _exact_bytes(
                authorization.disbursement_message_id,
                32,
                "disbursement_message_id",
            ),
            _exact_bytes(
                authorization.disbursement_tombstone_hash,
                32,
                "disbursement_tombstone_hash",
            ),
            _uint_word(authorization.amount),
            _exact_bytes(authorization.policy_hash, 32, "policy_hash"),
            _uint_word(authorization.authorization_nonce),
            _uint_word(authorization.valid_until),
            _exact_bytes(authorization.reason_code, 32, "reason_code"),
            _exact_bytes(
                authorization.authorizer_set_hash,
                32,
                "authorizer_set_hash",
            ),
            _uint_word(authorization.authorizer_set_version),
        )
    )


@dataclass(frozen=True)
class LoanCancellationRequestedInput:
    cancellation_id: bytes
    loan_id: bytes
    funding_lock_id: bytes
    disbursement_message_id: bytes
    disbursement_tombstone_hash: bytes
    home_loan_account: bytes
    lender: bytes
    wrapped_token: bytes
    amount: int
    policy_hash: bytes
    reason_code: bytes


def encode_loan_cancellation_requested(
    payload: LoanCancellationRequestedInput,
) -> bytes:
    return b"".join(
        (
            _exact_bytes(payload.cancellation_id, 32, "cancellation_id"),
            _exact_bytes(payload.loan_id, 32, "loan_id"),
            _exact_bytes(payload.funding_lock_id, 32, "funding_lock_id"),
            _exact_bytes(
                payload.disbursement_message_id,
                32,
                "disbursement_message_id",
            ),
            _exact_bytes(
                payload.disbursement_tombstone_hash,
                32,
                "disbursement_tombstone_hash",
            ),
            _address_word(payload.home_loan_account, "home_loan_account"),
            _address_word(payload.lender, "lender"),
            _address_word(payload.wrapped_token, "wrapped_token"),
            _uint_word(payload.amount),
            _exact_bytes(payload.policy_hash, 32, "policy_hash"),
            _exact_bytes(payload.reason_code, 32, "reason_code"),
        )
    )


@dataclass(frozen=True)
class SatelliteFundingCancelledInput:
    cancellation_id: bytes
    loan_id: bytes
    funding_lock_id: bytes
    disbursement_message_id: bytes
    disbursement_tombstone_hash: bytes
    escrow_burn_result_hash: bytes
    home_loan_account: bytes
    lender: bytes
    wrapped_token: bytes
    amount: int
    policy_hash: bytes


def encode_satellite_funding_cancelled(
    payload: SatelliteFundingCancelledInput,
) -> bytes:
    return b"".join(
        (
            _exact_bytes(payload.cancellation_id, 32, "cancellation_id"),
            _exact_bytes(payload.loan_id, 32, "loan_id"),
            _exact_bytes(payload.funding_lock_id, 32, "funding_lock_id"),
            _exact_bytes(
                payload.disbursement_message_id,
                32,
                "disbursement_message_id",
            ),
            _exact_bytes(
                payload.disbursement_tombstone_hash,
                32,
                "disbursement_tombstone_hash",
            ),
            _exact_bytes(
                payload.escrow_burn_result_hash,
                32,
                "escrow_burn_result_hash",
            ),
            _address_word(payload.home_loan_account, "home_loan_account"),
            _address_word(payload.lender, "lender"),
            _address_word(payload.wrapped_token, "wrapped_token"),
            _uint_word(payload.amount),
            _exact_bytes(payload.policy_hash, 32, "policy_hash"),
        )
    )


@dataclass(frozen=True)
class MessageDigestInput:
    schema_version: int
    protocol_id: bytes
    source_chain_id: int
    source_coordinator: bytes
    source_component: bytes
    destination_chain_id: int
    destination_coordinator: bytes
    destination_component: bytes
    lane_id: bytes
    source_nonce: int
    aggregate_id: bytes
    action_type: int
    payload_hash: bytes
    created_at_seconds: int
    expires_at_seconds: int
    route_policy_hash: bytes
    adapter_set_policy_hash: bytes
    source_finality_policy_hash: bytes
    destination_finality_policy_hash: bytes
    correlation_id: bytes
    causation_message_id: bytes
    superseded_message_id: bytes


def cross_chain_message_id(envelope: MessageDigestInput) -> bytes:
    static_words = (
        _uint_word(envelope.schema_version),
        _exact_bytes(envelope.protocol_id, 32, "protocol_id"),
        _uint_word(envelope.source_chain_id),
        _address_word(envelope.source_coordinator, "source_coordinator"),
        _address_word(envelope.source_component, "source_component"),
        _uint_word(envelope.destination_chain_id),
        _address_word(envelope.destination_coordinator, "destination_coordinator"),
        _address_word(envelope.destination_component, "destination_component"),
        _exact_bytes(envelope.lane_id, 32, "lane_id"),
        _uint_word(envelope.source_nonce),
        _exact_bytes(envelope.aggregate_id, 32, "aggregate_id"),
        _uint_word(envelope.action_type),
        _exact_bytes(envelope.payload_hash, 32, "payload_hash"),
        _uint_word(envelope.created_at_seconds),
        _uint_word(envelope.expires_at_seconds),
        _exact_bytes(envelope.route_policy_hash, 32, "route_policy_hash"),
        _exact_bytes(envelope.adapter_set_policy_hash, 32, "adapter_set_policy_hash"),
        _exact_bytes(
            envelope.source_finality_policy_hash,
            32,
            "source_finality_policy_hash",
        ),
        _exact_bytes(
            envelope.destination_finality_policy_hash,
            32,
            "destination_finality_policy_hash",
        ),
        _exact_bytes(envelope.correlation_id, 32, "correlation_id"),
        _exact_bytes(envelope.causation_message_id, 32, "causation_message_id"),
        _exact_bytes(envelope.superseded_message_id, 32, "superseded_message_id"),
    )
    return _keccak256(_abi_encode_dynamic_domain(MESSAGE_DOMAIN, static_words))


@dataclass(frozen=True)
class FinalityDigestInput:
    destination_chain_id: int
    verifier: bytes
    message_id: bytes
    source_proof_hash: bytes
    signer_set_hash: bytes
    signer_set_version: int


def synthetic_finality_digest(value: FinalityDigestInput) -> bytes:
    return _keccak256(
        _abi_encode_dynamic_domain(
            FINALITY_DOMAIN,
            (
                _uint_word(value.destination_chain_id),
                _address_word(value.verifier, "verifier"),
                _exact_bytes(value.message_id, 32, "message_id"),
                _exact_bytes(value.source_proof_hash, 32, "source_proof_hash"),
                _exact_bytes(value.signer_set_hash, 32, "signer_set_hash"),
                _uint_word(value.signer_set_version),
            ),
        )
    )


@dataclass(frozen=True)
class RecoveryAuthorizationInput:
    protocol_id: bytes
    source_chain_id: int
    source_coordinator: bytes
    destination_chain_id: int
    destination_coordinator: bytes
    message_id: bytes
    envelope_hash: bytes
    route_policy_hash: bytes
    asset_amount_commitment: bytes
    source_state_commitment: bytes
    destination_state_commitment: bytes
    compensation_payload_hash: bytes
    message_expires_at: int
    recovery_nonce: int
    reason_code: bytes
    action: int
    authorizer_set_hash: bytes
    authorizer_set_version: int


def recovery_authorization_digest(value: RecoveryAuthorizationInput) -> bytes:
    return _keccak256(
        _abi_encode_dynamic_domain(
            RECOVERY_AUTHORIZATION_DOMAIN,
            (
                _exact_bytes(value.protocol_id, 32, "protocol_id"),
                _uint_word(value.source_chain_id),
                _address_word(value.source_coordinator, "source_coordinator"),
                _uint_word(value.destination_chain_id),
                _address_word(value.destination_coordinator, "destination_coordinator"),
                _exact_bytes(value.message_id, 32, "message_id"),
                _exact_bytes(value.envelope_hash, 32, "envelope_hash"),
                _exact_bytes(value.route_policy_hash, 32, "route_policy_hash"),
                _exact_bytes(
                    value.asset_amount_commitment,
                    32,
                    "asset_amount_commitment",
                ),
                _exact_bytes(
                    value.source_state_commitment,
                    32,
                    "source_state_commitment",
                ),
                _exact_bytes(
                    value.destination_state_commitment,
                    32,
                    "destination_state_commitment",
                ),
                _exact_bytes(
                    value.compensation_payload_hash,
                    32,
                    "compensation_payload_hash",
                ),
                _uint_word(value.message_expires_at),
                _uint_word(value.recovery_nonce),
                _exact_bytes(value.reason_code, 32, "reason_code"),
                _uint_word(value.action),
                _exact_bytes(value.authorizer_set_hash, 32, "authorizer_set_hash"),
                _uint_word(value.authorizer_set_version),
            ),
        )
    )
