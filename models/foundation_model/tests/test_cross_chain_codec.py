from hashlib import sha256

from Crypto.Hash import keccak
from google.protobuf.timestamp_pb2 import Timestamp
from unified.v1 import crosschain_pb2
from unified_foundation.cross_chain_codec import (
    CanonicalUftLocked,
    FinalityDigestInput,
    LoanCancellationAuthorizationInput,
    LoanCancellationRequestedInput,
    MessageDigestInput,
    RecoveryAuthorizationInput,
    SatelliteFundingCancelledInput,
    canonical_uft_locked_payload_hash,
    cross_chain_message_id,
    encode_canonical_uft_locked,
    encode_loan_cancellation_authorization,
    encode_loan_cancellation_requested,
    encode_satellite_funding_cancelled,
    recovery_authorization_digest,
    synthetic_finality_digest,
)

EXPECTED_PAYLOAD_HASH = "805585e890e898930c0ac7d38c1e157d0e4a5964eb8239552298bb2d3789877a"
EXPECTED_MESSAGE_ID = "f8d9ef5672d829229110e480489155be0440e916833a1290a8955a8acf9c4801"
EXPECTED_FINALITY_DIGEST = "6ebe5277d0c32b531c792319523fd367e073607937dea0c3949c5f8d43ca8820"
GOLDEN_SOURCE_PROOF_HASH = "48d3a5bd4a6edfa6da4ceb1fb19fb7d7d975e24ac53af96bc4bc39947a566caf"
EXPECTED_RECOVERY_AUTHORIZATION_DIGEST = (
    "2ca5318f1079c2d3c45a5cefb7c5cf784728956bd328df3ee36feeb9b16af0ad"
)
EXPECTED_RECOVERY_PROTOBUF_SHA256 = (
    "73012516be56b9e049e86c2ceb3aadca52ccc6badd6d32aece816deb6cc4ed1e"
)
EXPECTED_CANCELLATION_AUTHORIZATION_ABI_HASH = (
    "6559f566fae044a0b47fad5ad54de9a09b55e0cba3bd34290293e4e3e36b0bc0"
)
EXPECTED_CANCELLATION_REQUEST_ABI_HASH = (
    "d8b5a830c89f14d7eaebe14c1c819a2526194c05491fb357bf972464612fb992"
)
EXPECTED_FUNDING_CANCELLED_ABI_HASH = (
    "e272800252a7b96d69aba58e658c1151e5211a1c7137700ff341cbe2d9c23dba"
)


def _repeated(value: int, length: int) -> bytes:
    return bytes([value]) * length


def _keccak_hex(value: bytes) -> str:
    digest = keccak.new(digest_bits=256)
    digest.update(value)
    return digest.hexdigest()


def test_python_protobuf_binding_matches_solidity_and_go_golden_vectors() -> None:
    payload = crosschain_pb2.CanonicalUftLockPayload(
        lock_id=_repeated(0x11, 32),
        loan_id=_repeated(0x22, 32),
        canonical_token=_repeated(0x11, 20),
        home_bridge_hub=_repeated(0x22, 20),
        wrapped_token=_repeated(0x33, 20),
        destination_recipient=_repeated(0x44, 20),
        amount="1000000000000000000",
    )
    codec_payload = CanonicalUftLocked(
        lock_id=payload.lock_id,
        loan_id=payload.loan_id,
        canonical_token=payload.canonical_token,
        home_bridge_hub=payload.home_bridge_hub,
        wrapped_token=payload.wrapped_token,
        destination_recipient=payload.destination_recipient,
        amount=int(payload.amount),
    )
    payload_bytes = encode_canonical_uft_locked(codec_payload)
    payload_hash = canonical_uft_locked_payload_hash(codec_payload)
    assert len(payload_bytes) == 7 * 32
    assert payload_hash.hex() == EXPECTED_PAYLOAD_HASH

    policy_hash = _repeated(0x11, 32)
    created_at = Timestamp(seconds=1_700_000_000)
    expires_at = Timestamp(seconds=1_700_003_600)
    envelope = crosschain_pb2.CrossChainMessageEnvelope(
        schema_version=1,
        protocol_id=_repeated(0x01, 32),
        source_chain_id="31337",
        source_coordinator=_repeated(0x02, 20),
        source_component=_repeated(0x03, 20),
        destination_chain_id="31338",
        destination_coordinator=_repeated(0x04, 20),
        destination_component=_repeated(0x05, 20),
        lane_id=_repeated(0x06, 32),
        source_nonce=1,
        aggregate_id=_repeated(0x07, 32),
        action_type=crosschain_pb2.CROSS_CHAIN_ACTION_TYPE_CANONICAL_UFT_LOCKED_V1,
        typed_action_payload=payload_bytes,
        payload_hash=payload_hash,
        created_at=created_at,
        expires_at=expires_at,
        route_policy_hash=policy_hash,
        adapter_set_policy_hash=policy_hash,
        source_finality_policy_hash=policy_hash,
        destination_finality_policy_hash=policy_hash,
        correlation_id=policy_hash,
        causation_message_id=bytes(32),
        superseded_message_id=bytes(32),
        canonical_uft_lock=payload,
    )
    assert envelope.WhichOneof("typed_action") == "canonical_uft_lock"
    message_id = cross_chain_message_id(
        MessageDigestInput(
            schema_version=envelope.schema_version,
            protocol_id=envelope.protocol_id,
            source_chain_id=int(envelope.source_chain_id),
            source_coordinator=envelope.source_coordinator,
            source_component=envelope.source_component,
            destination_chain_id=int(envelope.destination_chain_id),
            destination_coordinator=envelope.destination_coordinator,
            destination_component=envelope.destination_component,
            lane_id=envelope.lane_id,
            source_nonce=envelope.source_nonce,
            aggregate_id=envelope.aggregate_id,
            action_type=envelope.action_type,
            payload_hash=envelope.payload_hash,
            created_at_seconds=envelope.created_at.seconds,
            expires_at_seconds=envelope.expires_at.seconds,
            route_policy_hash=envelope.route_policy_hash,
            adapter_set_policy_hash=envelope.adapter_set_policy_hash,
            source_finality_policy_hash=envelope.source_finality_policy_hash,
            destination_finality_policy_hash=envelope.destination_finality_policy_hash,
            correlation_id=envelope.correlation_id,
            causation_message_id=envelope.causation_message_id,
            superseded_message_id=envelope.superseded_message_id,
        )
    )
    assert message_id.hex() == EXPECTED_MESSAGE_ID

    finality_digest = synthetic_finality_digest(
        FinalityDigestInput(
            destination_chain_id=31338,
            verifier=_repeated(0x55, 20),
            message_id=message_id,
            source_proof_hash=bytes.fromhex(GOLDEN_SOURCE_PROOF_HASH),
            signer_set_hash=_repeated(0x77, 32),
            signer_set_version=1,
        )
    )
    assert finality_digest.hex() == EXPECTED_FINALITY_DIGEST


def test_recovery_v2_protobuf_roundtrip_matches_solidity_and_go_golden() -> None:
    request = crosschain_pb2.CrossChainRecoveryRequestV2(
        message_id=_repeated(0xAA, 32),
        envelope_hash=_repeated(0xBB, 32),
        route_policy_hash=_repeated(0xCC, 32),
        asset_amount_commitment=_repeated(0xDD, 32),
        source_state_commitment=_repeated(0xEE, 32),
        destination_state_commitment=_repeated(0xFF, 32),
        compensation_payload_hash=_repeated(0x12, 32),
        message_expires_at=1_700_003_600,
        recovery_nonce=7,
        reason_code=_repeated(0x13, 32),
        action=crosschain_pb2.RECOVERY_ACTION_TOMBSTONE_THEN_COMPENSATE,
        authorizer_set_hash=_repeated(0x14, 32),
        authorizer_set_version=1,
    )
    authorization = crosschain_pb2.CrossChainRecoveryAuthorizationV2(
        protocol_id=_repeated(0x01, 32),
        source_chain_id="31337",
        source_coordinator=_repeated(0x02, 20),
        destination_chain_id="31338",
        destination_coordinator=_repeated(0x04, 20),
        request=request,
        authorizer_signatures=[_repeated(0x21, 65), _repeated(0x22, 65)],
        signer_bitmap=3,
    )
    wire = authorization.SerializeToString(deterministic=True)
    assert len(wire) == 549
    assert sha256(wire).hexdigest() == EXPECTED_RECOVERY_PROTOBUF_SHA256

    recovered = crosschain_pb2.CrossChainRecoveryAuthorizationV2.FromString(wire)
    assert recovered == authorization
    recovered_request = recovered.request
    digest = recovery_authorization_digest(
        RecoveryAuthorizationInput(
            protocol_id=recovered.protocol_id,
            source_chain_id=int(recovered.source_chain_id),
            source_coordinator=recovered.source_coordinator,
            destination_chain_id=int(recovered.destination_chain_id),
            destination_coordinator=recovered.destination_coordinator,
            message_id=recovered_request.message_id,
            envelope_hash=recovered_request.envelope_hash,
            route_policy_hash=recovered_request.route_policy_hash,
            asset_amount_commitment=recovered_request.asset_amount_commitment,
            source_state_commitment=recovered_request.source_state_commitment,
            destination_state_commitment=recovered_request.destination_state_commitment,
            compensation_payload_hash=recovered_request.compensation_payload_hash,
            message_expires_at=recovered_request.message_expires_at,
            recovery_nonce=recovered_request.recovery_nonce,
            reason_code=recovered_request.reason_code,
            action=recovered_request.action,
            authorizer_set_hash=recovered_request.authorizer_set_hash,
            authorizer_set_version=recovered_request.authorizer_set_version,
        )
    )
    assert digest.hex() == EXPECTED_RECOVERY_AUTHORIZATION_DIGEST


def test_cancellation_schema_matches_solidity_go_and_typescript_goldens() -> None:
    authorization = crosschain_pb2.LoanCancellationAuthorization(
        loan_router=_repeated(0x11, 20),
        loan_id=_repeated(0x22, 32),
        funding_lock_id=_repeated(0x33, 32),
        disbursement_message_id=_repeated(0x44, 32),
        disbursement_tombstone_hash=_repeated(0x55, 32),
        amount="1000000000000000000",
        policy_hash=_repeated(0x66, 32),
        authorization_nonce=7,
        valid_until=1_700_003_600,
        reason_code=_repeated(0x77, 32),
        authorizer_set_hash=_repeated(0x88, 32),
        authorizer_set_version=1,
    )
    authorization_abi = encode_loan_cancellation_authorization(
        LoanCancellationAuthorizationInput(
            loan_router=authorization.loan_router,
            loan_id=authorization.loan_id,
            funding_lock_id=authorization.funding_lock_id,
            disbursement_message_id=authorization.disbursement_message_id,
            disbursement_tombstone_hash=authorization.disbursement_tombstone_hash,
            amount=int(authorization.amount),
            policy_hash=authorization.policy_hash,
            authorization_nonce=authorization.authorization_nonce,
            valid_until=authorization.valid_until,
            reason_code=authorization.reason_code,
            authorizer_set_hash=authorization.authorizer_set_hash,
            authorizer_set_version=authorization.authorizer_set_version,
        )
    )
    assert len(authorization_abi) == 12 * 32
    assert _keccak_hex(authorization_abi) == EXPECTED_CANCELLATION_AUTHORIZATION_ABI_HASH
    authorization_wire = authorization.SerializeToString(deterministic=True)
    assert len(authorization_wire) == 291
    assert (
        sha256(authorization_wire).hexdigest()
        == "d49fc566ee4db808a2baa92b2ce06d3bf7c22f57909e8fe6325118033d11622a"
    )

    request = crosschain_pb2.LoanCancellationRequestedPayload(
        cancellation_id=_repeated(0x99, 32),
        loan_id=_repeated(0x22, 32),
        funding_lock_id=_repeated(0x33, 32),
        disbursement_message_id=_repeated(0x44, 32),
        disbursement_tombstone_hash=_repeated(0x55, 32),
        home_loan_account=_repeated(0xAA, 20),
        lender=_repeated(0xBB, 20),
        wrapped_token=_repeated(0xCC, 20),
        amount="1000000000000000000",
        policy_hash=_repeated(0x66, 32),
        reason_code=_repeated(0x77, 32),
    )
    request_abi = encode_loan_cancellation_requested(
        LoanCancellationRequestedInput(
            cancellation_id=request.cancellation_id,
            loan_id=request.loan_id,
            funding_lock_id=request.funding_lock_id,
            disbursement_message_id=request.disbursement_message_id,
            disbursement_tombstone_hash=request.disbursement_tombstone_hash,
            home_loan_account=request.home_loan_account,
            lender=request.lender,
            wrapped_token=request.wrapped_token,
            amount=int(request.amount),
            policy_hash=request.policy_hash,
            reason_code=request.reason_code,
        )
    )
    assert len(request_abi) == 11 * 32
    assert _keccak_hex(request_abi) == EXPECTED_CANCELLATION_REQUEST_ABI_HASH
    request_wire = request.SerializeToString(deterministic=True)
    assert len(request_wire) == 325
    assert (
        sha256(request_wire).hexdigest()
        == "15e698482aa0b475255ea058fca3ed816a7cae9921658c1c85dfe958b4155285"
    )

    completion = crosschain_pb2.SatelliteFundingCancelledPayload(
        cancellation_id=_repeated(0x99, 32),
        loan_id=_repeated(0x22, 32),
        funding_lock_id=_repeated(0x33, 32),
        disbursement_message_id=_repeated(0x44, 32),
        disbursement_tombstone_hash=_repeated(0x55, 32),
        escrow_burn_result_hash=_repeated(0xDD, 32),
        home_loan_account=_repeated(0xAA, 20),
        lender=_repeated(0xBB, 20),
        wrapped_token=_repeated(0xCC, 20),
        amount="1000000000000000000",
        policy_hash=_repeated(0x66, 32),
    )
    completion_abi = encode_satellite_funding_cancelled(
        SatelliteFundingCancelledInput(
            cancellation_id=completion.cancellation_id,
            loan_id=completion.loan_id,
            funding_lock_id=completion.funding_lock_id,
            disbursement_message_id=completion.disbursement_message_id,
            disbursement_tombstone_hash=completion.disbursement_tombstone_hash,
            escrow_burn_result_hash=completion.escrow_burn_result_hash,
            home_loan_account=completion.home_loan_account,
            lender=completion.lender,
            wrapped_token=completion.wrapped_token,
            amount=int(completion.amount),
            policy_hash=completion.policy_hash,
        )
    )
    assert len(completion_abi) == 11 * 32
    assert _keccak_hex(completion_abi) == EXPECTED_FUNDING_CANCELLED_ABI_HASH
    completion_wire = completion.SerializeToString(deterministic=True)
    assert len(completion_wire) == 325
    assert (
        sha256(completion_wire).hexdigest()
        == "1c7fe124da7a90146e157f9afea1b265ccda3394b1312b5044045766519a1909"
    )

    request_envelope = crosschain_pb2.CrossChainMessageEnvelope(
        action_type=crosschain_pb2.CROSS_CHAIN_ACTION_TYPE_CANCELLATION_REQUESTED_V1,
        loan_cancellation_requested=request,
    )
    completion_envelope = crosschain_pb2.CrossChainMessageEnvelope(
        action_type=crosschain_pb2.CROSS_CHAIN_ACTION_TYPE_SOURCE_COMPENSATED_V1,
        satellite_funding_cancelled=completion,
    )
    assert request_envelope.WhichOneof("typed_action") == "loan_cancellation_requested"
    assert completion_envelope.WhichOneof("typed_action") == "satellite_funding_cancelled"
    envelope_fields = crosschain_pb2.CrossChainMessageEnvelope.DESCRIPTOR.fields_by_name
    assert envelope_fields["loan_cancellation_requested"].number == 40
    assert envelope_fields["satellite_funding_cancelled"].number == 42
    assert (
        sha256(request_envelope.SerializeToString(deterministic=True)).hexdigest()
        == "f44dda8552740502b82c98dc488e20d2da4084f37cd924a557c44df79c429d52"
    )
    assert (
        sha256(completion_envelope.SerializeToString(deterministic=True)).hexdigest()
        == "4a61e679ca6b749434663f331d6da94fffd5cff01edb3104138145242a6a56d7"
    )
