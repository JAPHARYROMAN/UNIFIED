// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ICollateralCustodyV2 } from "../src/interfaces/phase9/ICollateralCustodyV2.sol";
import { ILienRegistry } from "../src/interfaces/phase9/ILienRegistry.sol";
import { Phase9Types } from "../src/resolution/Phase9Types.sol";
import {
    Phase9BootstrapAssetSource,
    Phase9BootstrapPolicyResolver,
    Phase9RefinanceBootstrapHarness
} from "./Phase9RefinanceBootstrapHarness.sol";

contract Phase9CustodyUnauthorizedCaller {
    function recordCustody(
        ICollateralCustodyV2 custody,
        Phase9Types.CustodyRecord calldata record,
        bytes32 operationId
    ) external {
        custody.recordCustody(record, operationId);
    }

    function registerLien(ILienRegistry registry, Phase9Types.Lien calldata lien_) external {
        registry.registerLien(lien_);
    }
}

/// @dev D1 evidence for P9R-SRC-003, P9R-SRC-005, and bootstrap security replay.
contract Phase9RefinanceCustodyLienBootstrapTest is Phase9RefinanceBootstrapHarness {
    bytes32 private constant SEED = keccak256("PHASE9_D1_CUSTODY_LIEN");
    address private constant LENDER = address(0x1E0D3);

    BootstrapSpec private _spec;

    function setUp() public {
        _deployBootstrapHarness();
        _spec = _defaultBootstrapSpec(SEED, address(this), LENDER);
        _createBootstrap(_spec);
    }

    function test_P9R_SRC003_SRC005_FirstCustodyIsBackedAndExactReplayIsInert() public {
        uint256 borrowerBefore = settlementToken.balanceOf(address(this));
        uint256 custodyBefore = settlementToken.balanceOf(address(collateralCustody));
        settlementToken.approve(address(collateralCustody), _spec.collateralQuantity);
        _recordBootstrapSecurity(_spec.loanId);
        uint256 borrowerAfter = settlementToken.balanceOf(address(this));
        uint256 custodyAfter = settlementToken.balanceOf(address(collateralCustody));
        require(borrowerBefore - borrowerAfter == _spec.collateralQuantity, "borrower delta");
        require(custodyAfter - custodyBefore == _spec.collateralQuantity, "custody delta");
        require(
            collateralCustody.totalCustody(_spec.collateralAssetId) == _spec.collateralQuantity,
            "attributed custody"
        );

        _recordBootstrapSecurity(_spec.loanId);
        require(settlementToken.balanceOf(address(this)) == borrowerAfter, "replay borrower");
        require(
            settlementToken.balanceOf(address(collateralCustody)) == custodyAfter, "replay custody"
        );
        require(
            lienRegistry.lien(_spec.collateralId).status == Phase9Types.LienStatus.ACTIVE,
            "active lien"
        );
    }

    function test_P9R_SRC005_ChangedAndAlternateOperationReuseConflict() public {
        settlementToken.approve(address(collateralCustody), _spec.collateralQuantity);
        _recordBootstrapSecurity(_spec.loanId);
        Phase9BootstrapPolicyResolver.BootstrapRecord memory record =
            policyResolver.bootstrap(canonicalBootstrapIds[_spec.loanId]);
        bytes32 operationId = _deriveCustodyOperationId(
            canonicalBootstrapIds[_spec.loanId], _spec.loanId, _spec.collateralId
        );

        Phase9Types.CustodyRecord memory changed = record.custodyRecords[0];
        changed.quantity += 1;
        _expectCustodyError(
            abi.encodeCall(ICollateralCustodyV2.recordCustody, (changed, operationId)),
            ICollateralCustodyV2.CustodyOperationReplay.selector
        );
        _expectCustodyError(
            abi.encodeCall(
                ICollateralCustodyV2.recordCustody,
                (record.custodyRecords[0], keccak256("ALTERNATE_OPERATION"))
            ),
            ICollateralCustodyV2.CustodyOperationReplay.selector
        );

        Phase9Types.Lien memory changedLien = record.liens[0];
        changedLien.quantity += 1;
        (bool success, bytes memory returned) =
            address(lienRegistry).call(abi.encodeCall(ILienRegistry.registerLien, (changedLien)));
        require(!success, "changed lien replay");
        require(_selector(returned) == ILienRegistry.InvalidLien.selector, "lien selector");
    }

    function test_P9R_SRC003_ResolverDriftBreaksCustodyReplay() public {
        settlementToken.approve(address(collateralCustody), _spec.collateralQuantity);
        _recordBootstrapSecurity(_spec.loanId);
        Phase9BootstrapPolicyResolver.BootstrapRecord memory record =
            policyResolver.bootstrap(canonicalBootstrapIds[_spec.loanId]);
        custodyAssetSource.setAsset(
            _spec.collateralAssetId,
            Phase9BootstrapAssetSource.AssetRecord({
                token: address(settlementToken),
                decimals: 6,
                runtimeCodeHash: address(settlementToken).codehash,
                exactBalanceDelta: true,
                active: false
            })
        );
        bytes32 operationId = _deriveCustodyOperationId(
            canonicalBootstrapIds[_spec.loanId], _spec.loanId, _spec.collateralId
        );
        _expectCustodyError(
            abi.encodeCall(
                ICollateralCustodyV2.recordCustody, (record.custodyRecords[0], operationId)
            ),
            ICollateralCustodyV2.InvalidCustodyOperation.selector
        );
    }

    function test_P9R_AUTH008_CustodyAndLienRejectSubstitutedCaller() public {
        Phase9BootstrapPolicyResolver.BootstrapRecord memory record =
            policyResolver.bootstrap(canonicalBootstrapIds[_spec.loanId]);
        bytes32 operationId = _deriveCustodyOperationId(
            canonicalBootstrapIds[_spec.loanId], _spec.loanId, _spec.collateralId
        );
        Phase9CustodyUnauthorizedCaller attacker = new Phase9CustodyUnauthorizedCaller();
        (bool success, bytes memory returned) = address(attacker)
            .call(
                abi.encodeCall(
                    Phase9CustodyUnauthorizedCaller.recordCustody,
                    (collateralCustody, record.custodyRecords[0], operationId)
                )
            );
        require(!success, "unauthorized custody");
        require(
            _selector(returned) == ICollateralCustodyV2.InvalidCustodyOperation.selector,
            "custody auth selector"
        );
        (success, returned) = address(attacker)
            .call(
                abi.encodeCall(
                    Phase9CustodyUnauthorizedCaller.registerLien, (lienRegistry, record.liens[0])
                )
            );
        require(!success, "unauthorized lien");
        require(_selector(returned) == ILienRegistry.InvalidLien.selector, "lien auth selector");
    }

    function test_P9R_VIEW001_UnknownLienUsesTypedError() public view {
        bytes32 unknown = keccak256("UNKNOWN_COLLATERAL");
        (bool success, bytes memory returned) =
            address(lienRegistry).staticcall(abi.encodeCall(ILienRegistry.lien, (unknown)));
        require(!success, "unknown lien returned");
        require(_selector(returned) == ILienRegistry.UnknownLien.selector, "unknown selector");
    }

    function _expectCustodyError(bytes memory callData, bytes4 expected) private {
        (bool success, bytes memory returned) = address(collateralCustody).call(callData);
        require(!success, "expected custody revert");
        require(_selector(returned) == expected, "custody selector");
    }

    function _selector(bytes memory returned) private pure returns (bytes4 selector) {
        if (returned.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(returned, 0x20))
        }
    }
}
