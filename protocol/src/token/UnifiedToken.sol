// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ProtocolTypes } from "../kernel/ProtocolTypes.sol";
import { UFTAllocations } from "./UFTAllocations.sol";

/// @notice Fixed-supply Unified Coin. The only issuance occurs in this constructor.
contract UnifiedToken is ERC20, ERC20Burnable, ERC20Permit {
    error InvalidGenesisDestination();

    uint256 public constant MAX_SUPPLY = UFTAllocations.MAX_SUPPLY;

    event GenesisAllocationFunded(
        bytes32 indexed allocationId, address indexed destination, uint256 amount
    );
    event GenesisSupplyCreated(uint256 amount, uint256 resultingTotalSupply);

    constructor(ProtocolTypes.GenesisDestinations memory destinations)
        ERC20("Unified Coin", "UFT")
        ERC20Permit("Unified Coin")
    {
        _validateDestinations(destinations);
        _fund(keccak256("COMMUNITY"), destinations.community, UFTAllocations.COMMUNITY);
        _fund(keccak256("TREASURY"), destinations.treasury, UFTAllocations.TREASURY);
        _fund(
            keccak256("STAKING_REWARDS"),
            destinations.stakingRewards,
            UFTAllocations.STAKING_REWARDS
        );
        _fund(keccak256("INSURANCE"), destinations.insurance, UFTAllocations.INSURANCE);
        _fund(keccak256("CONTRIBUTORS"), destinations.contributors, UFTAllocations.CONTRIBUTORS);
        _fund(keccak256("INVESTORS"), destinations.investors, UFTAllocations.INVESTORS);
        _fund(
            keccak256("PUBLIC_DISTRIBUTION"),
            destinations.publicDistribution,
            UFTAllocations.PUBLIC_DISTRIBUTION
        );
        _fund(keccak256("LIQUIDITY"), destinations.liquidity, UFTAllocations.LIQUIDITY);
        _fund(keccak256("PARTNERS"), destinations.partners, UFTAllocations.PARTNERS);
        assert(totalSupply() == MAX_SUPPLY);
        emit GenesisSupplyCreated(MAX_SUPPLY, totalSupply());
    }

    function _fund(bytes32 allocationId, address destination, uint256 amount) private {
        if (destination == address(0)) revert InvalidGenesisDestination();
        _mint(destination, amount);
        emit GenesisAllocationFunded(allocationId, destination, amount);
    }

    function _validateDestinations(ProtocolTypes.GenesisDestinations memory destinations)
        private
        pure
    {
        address[9] memory accounts = [
            destinations.community,
            destinations.treasury,
            destinations.stakingRewards,
            destinations.insurance,
            destinations.contributors,
            destinations.investors,
            destinations.publicDistribution,
            destinations.liquidity,
            destinations.partners
        ];
        for (uint256 index = 0; index < accounts.length; ++index) {
            if (accounts[index] == address(0)) revert InvalidGenesisDestination();
            for (uint256 prior = 0; prior < index; ++prior) {
                if (accounts[index] == accounts[prior]) {
                    revert InvalidGenesisDestination();
                }
            }
        }
    }
}
