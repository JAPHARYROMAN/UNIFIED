// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { AssetRegistry } from "../kernel/AssetRegistry.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";

/// @notice Atomic single-lender funding and direct same-chain disbursement.
contract FundingManager is RoleControlled, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidFunding();
    error FundingAlreadyFinalized(bytes32 loanId);
    error UnsupportedFundingAsset(bytes32 assetId);
    error FundingBalanceMismatch();

    struct FundingRecord {
        bytes32 commitmentId;
        address lender;
        address borrower;
        bytes32 assetId;
        uint256 grossPrincipal;
        uint256 originationFee;
        bytes32 journalRef;
        uint64 fundedAt;
    }

    AssetRegistry public immutable assetRegistry;
    address public immutable feeReceiver;
    mapping(bytes32 loanId => FundingRecord record) private _funding;

    event FundingCommitted(
        bytes32 indexed commitmentId, bytes32 indexed loanId, address indexed lender, uint256 amount
    );
    event PrincipalDisbursed(
        bytes32 indexed loanId,
        address indexed borrower,
        bytes32 indexed assetId,
        uint256 grossPrincipal,
        uint256 netProceeds,
        uint256 originationFee
    );
    event JournalReferenceLinked(bytes32 indexed operationId, bytes32 indexed journalRef);

    constructor(IRoleManager roleManager_, AssetRegistry assetRegistry_, address feeReceiver_)
        RoleControlled(roleManager_)
    {
        require(
            address(assetRegistry_) != address(0) && feeReceiver_ != address(0),
            "invalid funding configuration"
        );
        assetRegistry = assetRegistry_;
        feeReceiver = feeReceiver_;
    }

    function fundAndDisburse(
        bytes32 loanId,
        address lender,
        address borrower,
        bytes32 assetId,
        uint256 grossPrincipal,
        uint256 originationFee,
        bytes32 journalRef
    )
        external
        nonReentrant
        onlyRole(ProtocolRoles.LOAN_FACTORY_ROLE)
        returns (bytes32 commitmentId)
    {
        if (
            loanId == bytes32(0) || lender == address(0) || borrower == address(0)
                || lender == borrower || borrower == feeReceiver || lender == feeReceiver
                || grossPrincipal == 0 || originationFee >= grossPrincipal
                || journalRef == bytes32(0)
        ) {
            revert InvalidFunding();
        }
        if (_funding[loanId].lender != address(0)) {
            revert FundingAlreadyFinalized(loanId);
        }
        AssetRegistry.AssetRecord memory asset = assetRegistry.resolve(assetId);
        if (!asset.active) revert UnsupportedFundingAsset(assetId);

        IERC20 token = IERC20(asset.token);
        uint256 netProceeds =
            _transferExact(token, lender, borrower, grossPrincipal, originationFee);

        commitmentId = keccak256(abi.encode("UNIFIED_SINGLE_LENDER_COMMITMENT", loanId, lender));
        _funding[loanId] = FundingRecord({
            commitmentId: commitmentId,
            lender: lender,
            borrower: borrower,
            assetId: assetId,
            grossPrincipal: grossPrincipal,
            originationFee: originationFee,
            journalRef: journalRef,
            fundedAt: uint64(block.timestamp)
        });
        emit FundingCommitted(commitmentId, loanId, lender, grossPrincipal);
        emit PrincipalDisbursed(
            loanId, borrower, assetId, grossPrincipal, netProceeds, originationFee
        );
        emit JournalReferenceLinked(loanId, journalRef);
    }

    function fundingRecord(bytes32 loanId) external view returns (FundingRecord memory) {
        return _funding[loanId];
    }

    function fundedAmount(bytes32 loanId) external view returns (uint256) {
        return _funding[loanId].grossPrincipal;
    }

    function availableToDisburse(bytes32) external pure returns (uint256) {
        return 0;
    }

    function _transferExact(
        IERC20 token,
        address lender,
        address borrower,
        uint256 grossPrincipal,
        uint256 originationFee
    ) private returns (uint256 netProceeds) {
        netProceeds = grossPrincipal - originationFee;
        uint256 lenderBefore = token.balanceOf(lender);
        uint256 borrowerBefore = token.balanceOf(borrower);
        uint256 feeBefore = token.balanceOf(feeReceiver);
        if (netProceeds != 0) {
            token.safeTransferFrom(lender, borrower, netProceeds);
        }
        if (originationFee != 0) {
            token.safeTransferFrom(lender, feeReceiver, originationFee);
        }
        bool lenderExact = lenderBefore - token.balanceOf(lender) == grossPrincipal;
        bool borrowerExact = token.balanceOf(borrower) - borrowerBefore == netProceeds;
        bool feeExact = token.balanceOf(feeReceiver) - feeBefore == originationFee;
        if (!lenderExact || !borrowerExact || !feeExact) {
            revert FundingBalanceMismatch();
        }
    }
}
