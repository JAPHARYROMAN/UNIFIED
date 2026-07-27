// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { PreparePhase9RefinanceLocal } from "../script/PreparePhase9RefinanceLocal.s.sol";

interface Phase9RefinancePrerequisiteTestVm {
    function chainId(uint256 chainId) external;
}

contract PreparePhase9RefinanceLocalTest {
    Phase9RefinancePrerequisiteTestVm private constant vm = Phase9RefinancePrerequisiteTestVm(
        address(uint160(uint256(keccak256("hevm cheat code"))))
    );

    PreparePhase9RefinanceLocal private fixture;

    function setUp() public {
        vm.chainId(31_337);
        fixture = new PreparePhase9RefinanceLocal();
    }

    function testCandidateBroadcasterCannotBeSetupAuthority() public {
        _requireIsolationRejection(address(0x100), address(0x100), address(0x200), address(0x300));
    }

    function testCandidateBroadcasterCannotBeGovernanceAuthority() public {
        _requireIsolationRejection(address(0x100), address(0x200), address(0x200), address(0x300));
    }

    function testCandidateBroadcasterCannotReceiveSyntheticSupply() public {
        _requireIsolationRejection(address(0x100), address(0x300), address(0x200), address(0x300));
    }

    function _requireIsolationRejection(
        address setupBroadcaster,
        address candidateBroadcaster,
        address governanceExecutor,
        address fixtureAllocator
    ) private {
        try fixture.run(
            setupBroadcaster,
            candidateBroadcaster,
            governanceExecutor,
            fixtureAllocator,
            "deployments/local/phase9-refinance-smoke-configuration.json"
        ) {
            revert("candidate isolation was not enforced");
        } catch (bytes memory reason) {
            require(
                keccak256(reason)
                    == keccak256(
                        abi.encodeWithSelector(
                            PreparePhase9RefinanceLocal.InvalidFixtureConfiguration.selector
                        )
                    ),
                "wrong candidate isolation error"
            );
        }
    }
}
