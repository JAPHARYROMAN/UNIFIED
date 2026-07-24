// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

library ProtocolTypes {
    struct PolicyRef {
        bytes32 policyId;
        address implementation;
        uint32 major;
        uint32 minor;
        uint32 patch;
        bytes4 interfaceId;
        bytes32 configurationSchemaHash;
    }

    struct RevenueSplit {
        uint16 insuranceBps;
        uint16 stakerBps;
        uint16 treasuryBps;
        uint16 burnBps;
        uint16 liquidityBps;
        uint16 publicGoodsBps;
    }

    struct GenesisDestinations {
        address community;
        address treasury;
        address stakingRewards;
        address insurance;
        address contributors;
        address investors;
        address publicDistribution;
        address liquidity;
        address partners;
    }
}
