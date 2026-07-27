// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IRefinanceCoordinator } from "../src/interfaces/phase9/IRefinanceCoordinator.sol";
import { DeployPhase9RefinanceLocal } from "../script/DeployPhase9RefinanceLocal.s.sol";

contract Phase9RefinanceDeploymentAssertionHarness is DeployPhase9RefinanceLocal {
    function assertNoKnownRefinanceBusinessState(address coordinator) external view {
        _assertNoKnownRefinanceBusinessState(coordinator);
    }
}

contract Phase9ExactUnknownRefinanceViews {
    function escrowedUnits(bytes32 refinanceId) external pure returns (uint256) {
        revert IRefinanceCoordinator.UnknownRefinance(refinanceId);
    }

    function commitmentIds(bytes32 refinanceId) external pure returns (bytes32[] memory) {
        revert IRefinanceCoordinator.UnknownRefinance(refinanceId);
    }
}

contract Phase9ZeroUnknownRefinanceViews {
    function escrowedUnits(bytes32) external pure returns (uint256) {
        return 0;
    }

    function commitmentIds(bytes32) external pure returns (bytes32[] memory ids) {
        ids = new bytes32[](0);
    }
}

contract Phase9WrongUnknownRefinanceViews {
    error WrongUnknownRefinance(bytes32 refinanceId);

    function escrowedUnits(bytes32 refinanceId) external pure returns (uint256) {
        revert WrongUnknownRefinance(refinanceId);
    }

    function commitmentIds(bytes32 refinanceId) external pure returns (bytes32[] memory) {
        revert WrongUnknownRefinance(refinanceId);
    }
}

contract Phase9RefinanceLocalDeploymentAssertionsTest {
    Phase9RefinanceDeploymentAssertionHarness private harness;

    function setUp() public {
        harness = new Phase9RefinanceDeploymentAssertionHarness();
    }

    function test_ExactUnknownRefinanceTypedErrorsProveCleanBusinessState() public {
        harness.assertNoKnownRefinanceBusinessState(address(new Phase9ExactUnknownRefinanceViews()));
    }

    function test_ZeroReturningUnknownViewsFailClosed() public {
        _expectInvalidDeployment(address(new Phase9ZeroUnknownRefinanceViews()));
    }

    function test_WrongUnknownViewSelectorFailsClosed() public {
        _expectInvalidDeployment(address(new Phase9WrongUnknownRefinanceViews()));
    }

    function _expectInvalidDeployment(address coordinator) private view {
        (bool success, bytes memory returned) = address(harness)
            .staticcall(
                abi.encodeCall(
                    Phase9RefinanceDeploymentAssertionHarness.assertNoKnownRefinanceBusinessState,
                    (coordinator)
                )
            );
        require(!success, "deployment assertion accepted invalid unknown view");
        require(
            _selector(returned)
                == DeployPhase9RefinanceLocal.InvalidDeploymentConfiguration.selector,
            "deployment assertion selector"
        );
    }

    function _selector(bytes memory returned) private pure returns (bytes4 selector) {
        if (returned.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(returned, 0x20))
        }
    }
}
