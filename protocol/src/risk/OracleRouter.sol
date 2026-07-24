// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { RiskTypes } from "./RiskTypes.sol";

interface IOracleAdapter {
    function latest(bytes32 assetId, bytes32 quoteAssetId)
        external
        view
        returns (uint256 value, uint8 decimals, uint64 observedAt, uint64 roundId);
}

/// @notice Medianized, evidence-bearing price router with explicit safe mode.
contract OracleRouter is RoleControlled {
    error InvalidOracleConfiguration();
    error InvalidOraclePair();
    error OracleUnavailable(bytes32 pairKey);

    uint8 public constant MAX_SOURCES = 8;
    uint8 public constant NORMALIZED_DECIMALS = 18;

    struct PairConfiguration {
        uint64 maximumAge;
        uint16 maximumDeviationBps;
        uint8 minimumSources;
        bool configured;
    }

    struct Source {
        bytes32 sourceId;
        address adapter;
        bool enabled;
    }

    struct Collected {
        uint256[] values;
        bytes32[] evidence;
        uint64[] observedTimes;
        uint64[] rounds;
        uint256 count;
    }

    struct Aggregate {
        uint256 median;
        uint256 acceptedCount;
        uint64 oldestAccepted;
        uint64 maximumRound;
        bytes32 evidenceHash;
    }

    mapping(bytes32 pairKey => PairConfiguration configuration) private _configuration;
    mapping(bytes32 pairKey => Source[] sources) private _sources;
    mapping(bytes32 pairKey => RiskTypes.OracleObservation observation) private _latest;
    mapping(bytes32 pairKey => bool broken) private _circuitBroken;
    mapping(bytes32 assetId => bool broken) private _assetCircuitBroken;
    mapping(bytes32 assetId => bytes32 quoteAssetId) public canonicalQuoteAsset;

    event PairConfigured(
        bytes32 indexed pairKey,
        bytes32 indexed assetId,
        bytes32 indexed quoteAssetId,
        uint64 maximumAge,
        uint16 maximumDeviationBps,
        uint8 minimumSources
    );
    event SourceConfigured(
        bytes32 indexed pairKey, bytes32 indexed sourceId, address indexed adapter, bool enabled
    );
    event PriceUpdated(
        bytes32 indexed pairKey,
        uint256 normalizedValue,
        uint64 observedAt,
        uint8 acceptedSources,
        bytes32 sourceEvidenceHash
    );
    event OracleSafeMode(bytes32 indexed pairKey, bytes32 indexed reasonCode);
    event OracleSafeModeCleared(bytes32 indexed pairKey);

    constructor(IRoleManager roleManager_) RoleControlled(roleManager_) { }

    function configurePair(
        bytes32 assetId,
        bytes32 quoteAssetId,
        uint64 maximumAge,
        uint16 maximumDeviationBps,
        uint8 minimumSources
    ) external onlyRole(ProtocolRoles.ORACLE_MANAGER_ROLE) {
        if (
            assetId == bytes32(0) || quoteAssetId == bytes32(0) || assetId == quoteAssetId
                || maximumAge == 0 || maximumDeviationBps == 0
                || maximumDeviationBps > RiskTypes.BPS || minimumSources == 0
                || minimumSources > MAX_SOURCES
        ) {
            revert InvalidOracleConfiguration();
        }
        bytes32 configuredQuote = canonicalQuoteAsset[assetId];
        if (configuredQuote != bytes32(0) && configuredQuote != quoteAssetId) {
            revert InvalidOracleConfiguration();
        }
        canonicalQuoteAsset[assetId] = quoteAssetId;
        bytes32 key = pairKey(assetId, quoteAssetId);
        _configuration[key] = PairConfiguration({
            maximumAge: maximumAge,
            maximumDeviationBps: maximumDeviationBps,
            minimumSources: minimumSources,
            configured: true
        });
        _breakCircuit(key, assetId, keccak256("PAIR_CONFIGURATION_CHANGED"));
        emit PairConfigured(
            key, assetId, quoteAssetId, maximumAge, maximumDeviationBps, minimumSources
        );
    }

    function configureSource(
        bytes32 assetId,
        bytes32 quoteAssetId,
        bytes32 sourceId,
        address adapter,
        bool enabled
    ) external onlyRole(ProtocolRoles.ORACLE_MANAGER_ROLE) {
        bytes32 key = pairKey(assetId, quoteAssetId);
        if (
            !_configuration[key].configured || sourceId == bytes32(0)
                || (enabled && adapter.code.length == 0)
        ) {
            revert InvalidOracleConfiguration();
        }
        Source[] storage records = _sources[key];
        for (uint256 index = 0; index < records.length; ++index) {
            if (records[index].sourceId == sourceId) {
                records[index].adapter = adapter;
                records[index].enabled = enabled;
                _breakCircuit(key, assetId, keccak256("SOURCE_CONFIGURATION_CHANGED"));
                emit SourceConfigured(key, sourceId, adapter, enabled);
                return;
            }
        }
        if (records.length >= MAX_SOURCES) revert InvalidOracleConfiguration();
        records.push(Source({ sourceId: sourceId, adapter: adapter, enabled: enabled }));
        _breakCircuit(key, assetId, keccak256("SOURCE_CONFIGURATION_CHANGED"));
        emit SourceConfigured(key, sourceId, adapter, enabled);
    }

    function updatePrice(bytes32 assetId, bytes32 quoteAssetId) external returns (bool accepted) {
        bytes32 key = pairKey(assetId, quoteAssetId);
        PairConfiguration memory pairConfig = _configuration[key];
        if (!pairConfig.configured) revert InvalidOraclePair();

        Collected memory collected = _collect(key, assetId, quoteAssetId, pairConfig.maximumAge);
        if (collected.count < pairConfig.minimumSources) {
            return _breakCircuit(key, assetId, keccak256("INSUFFICIENT_FRESH_SOURCES"));
        }
        _sort(collected);
        Aggregate memory aggregate = _aggregate(collected, pairConfig.maximumDeviationBps);
        if (aggregate.acceptedCount < pairConfig.minimumSources) {
            return _breakCircuit(key, assetId, keccak256("PRICE_DEVIATION"));
        }

        bool wasBroken = _circuitBroken[key];
        _circuitBroken[key] = false;
        _assetCircuitBroken[assetId] = false;
        _latest[key] = RiskTypes.OracleObservation({
            assetId: assetId,
            quoteAssetId: quoteAssetId,
            value: aggregate.median,
            decimals: NORMALIZED_DECIMALS,
            observedAt: aggregate.oldestAccepted,
            retrievedAt: uint64(block.timestamp),
            roundId: aggregate.maximumRound,
            confidenceBps: uint16(RiskTypes.BPS - pairConfig.maximumDeviationBps),
            sourceEvidenceHash: aggregate.evidenceHash
        });
        if (wasBroken) emit OracleSafeModeCleared(key);
        emit PriceUpdated(
            key,
            aggregate.median,
            aggregate.oldestAccepted,
            uint8(aggregate.acceptedCount),
            aggregate.evidenceHash
        );
        return true;
    }

    function price(bytes32 assetId, bytes32 quoteAssetId)
        external
        view
        returns (RiskTypes.OracleObservation memory observation)
    {
        bytes32 key = pairKey(assetId, quoteAssetId);
        observation = _latest[key];
        PairConfiguration memory pairConfig = _configuration[key];
        if (
            !pairConfig.configured || _circuitBroken[key] || observation.value == 0
                || block.timestamp > uint256(observation.observedAt) + pairConfig.maximumAge
        ) {
            revert OracleUnavailable(key);
        }
    }

    function validateObservation(
        RiskTypes.OracleObservation calldata observation,
        bytes32 riskContext
    ) external view returns (bool) {
        bytes32 key = pairKey(observation.assetId, observation.quoteAssetId);
        RiskTypes.OracleObservation storage canonical = _latest[key];
        PairConfiguration memory pairConfig = _configuration[key];
        return riskContext != bytes32(0) && pairConfig.configured && !_circuitBroken[key]
            && observation.assetId == canonical.assetId
            && observation.quoteAssetId == canonical.quoteAssetId
            && observation.value == canonical.value
            && observation.retrievedAt == canonical.retrievedAt
            && observation.observedAt == canonical.observedAt
            && observation.roundId == canonical.roundId
            && observation.confidenceBps == canonical.confidenceBps
            && observation.sourceEvidenceHash == canonical.sourceEvidenceHash
            && observation.decimals == NORMALIZED_DECIMALS
            && block.timestamp <= uint256(observation.observedAt) + pairConfig.maximumAge;
    }

    function adapterFor(bytes32 assetId, bytes32 quoteAssetId) external view returns (address) {
        Source[] storage records = _sources[pairKey(assetId, quoteAssetId)];
        if (records.length == 0) return address(0);
        return records[0].adapter;
    }

    function sources(bytes32 assetId, bytes32 quoteAssetId)
        external
        view
        returns (Source[] memory)
    {
        return _sources[pairKey(assetId, quoteAssetId)];
    }

    function pairConfiguration(bytes32 assetId, bytes32 quoteAssetId)
        external
        view
        returns (PairConfiguration memory)
    {
        return _configuration[pairKey(assetId, quoteAssetId)];
    }

    function isCircuitBroken(bytes32 assetId) external view returns (bool) {
        return _assetCircuitBroken[assetId];
    }

    function isPairCircuitBroken(bytes32 assetId, bytes32 quoteAssetId)
        external
        view
        returns (bool)
    {
        return _circuitBroken[pairKey(assetId, quoteAssetId)];
    }

    function pairKey(bytes32 assetId, bytes32 quoteAssetId) public pure returns (bytes32) {
        return keccak256(abi.encode(assetId, quoteAssetId));
    }

    function _collect(bytes32 key, bytes32 assetId, bytes32 quoteAssetId, uint64 maximumAge)
        private
        view
        returns (Collected memory collected)
    {
        Source[] storage records = _sources[key];
        collected.values = new uint256[](records.length);
        collected.evidence = new bytes32[](records.length);
        collected.observedTimes = new uint64[](records.length);
        collected.rounds = new uint64[](records.length);
        for (uint256 index = 0; index < records.length; ++index) {
            Source storage source = records[index];
            if (!source.enabled) continue;
            try IOracleAdapter(source.adapter).latest(assetId, quoteAssetId) returns (
                uint256 value, uint8 decimals, uint64 observedAt, uint64 roundId
            ) {
                if (
                    value == 0 || decimals > 36 || observedAt > block.timestamp
                        || block.timestamp > uint256(observedAt) + maximumAge
                ) {
                    continue;
                }
                uint256 scale = 10 ** decimals;
                uint256 normalized = Math.mulDiv(value, 1e18, scale);
                if (normalized == 0) continue;
                collected.values[collected.count] = normalized;
                collected.evidence[collected.count] = keccak256(
                    abi.encode(source.sourceId, source.adapter, roundId, value, decimals)
                );
                collected.observedTimes[collected.count] = observedAt;
                collected.rounds[collected.count] = roundId;
                ++collected.count;
            } catch { }
        }
    }

    function _breakCircuit(bytes32 key, bytes32 assetId, bytes32 reasonCode)
        private
        returns (bool)
    {
        _circuitBroken[key] = true;
        _assetCircuitBroken[assetId] = true;
        emit OracleSafeMode(key, reasonCode);
        return false;
    }

    function _difference(uint256 left, uint256 right) private pure returns (uint256) {
        return left >= right ? left - right : right - left;
    }

    function _aggregate(Collected memory collected, uint16 maximumDeviationBps)
        private
        pure
        returns (Aggregate memory aggregate)
    {
        aggregate.median = collected.values[(collected.count - 1) / 2];
        aggregate.oldestAccepted = type(uint64).max;
        for (uint256 index = 0; index < collected.count; ++index) {
            uint256 deviation = Math.mulDiv(
                _difference(collected.values[index], aggregate.median),
                RiskTypes.BPS,
                aggregate.median
            );
            if (deviation <= maximumDeviationBps) {
                ++aggregate.acceptedCount;
                if (collected.observedTimes[index] < aggregate.oldestAccepted) {
                    aggregate.oldestAccepted = collected.observedTimes[index];
                }
                if (collected.rounds[index] > aggregate.maximumRound) {
                    aggregate.maximumRound = collected.rounds[index];
                }
                aggregate.evidenceHash = keccak256(
                    abi.encode(
                        aggregate.evidenceHash,
                        collected.evidence[index],
                        collected.values[index],
                        collected.observedTimes[index]
                    )
                );
            }
        }
    }

    function _sort(Collected memory collected) private pure {
        for (uint256 index = 1; index < collected.count; ++index) {
            uint256 value = collected.values[index];
            bytes32 proof = collected.evidence[index];
            uint64 observed = collected.observedTimes[index];
            uint64 round = collected.rounds[index];
            uint256 cursor = index;
            while (cursor > 0 && collected.values[cursor - 1] > value) {
                collected.values[cursor] = collected.values[cursor - 1];
                collected.evidence[cursor] = collected.evidence[cursor - 1];
                collected.observedTimes[cursor] = collected.observedTimes[cursor - 1];
                collected.rounds[cursor] = collected.rounds[cursor - 1];
                --cursor;
            }
            collected.values[cursor] = value;
            collected.evidence[cursor] = proof;
            collected.observedTimes[cursor] = observed;
            collected.rounds[cursor] = round;
        }
    }
}
