// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILoanRegistry } from "../interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { AssetRegistry } from "../kernel/AssetRegistry.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { RiskTypes } from "../risk/RiskTypes.sol";
import { CollateralVault } from "./CollateralVault.sol";

interface ICollateralizedDebt {
    function outstandingPrincipal() external view returns (uint256);
}

/// @notice Creates per-loan vaults, enforces custody admission, release, and UFT limits.
contract CollateralManager is RoleControlled {
    error InvalidCollateralConfiguration();
    error InvalidCollateralOperation();
    error UFTExposureExceeded();
    error UnauthorizedLiquidationEngine();

    uint256 public constant BPS = 10_000;
    uint256 public constant UFT_SINGLE_LOAN_EXPOSURE_BPS = 25;
    uint256 public constant UFT_BORROWER_EXPOSURE_BPS = 50;

    struct AssetConfiguration {
        address token;
        RiskTypes.CollateralKind kind;
        bool enabled;
        bool isUFT;
    }

    ILoanRegistry public immutable loanRegistry;
    AssetRegistry public immutable assetRegistry;
    bytes32 public immutable uftAssetId;
    IERC20 public immutable uft;

    address public liquidationEngine;
    uint256 public uftBackedDebtCeiling;
    uint256 public totalUftBackedDebt;
    mapping(bytes32 loanId => uint256 debtValue) public uftBackedDebt;
    mapping(bytes32 assetId => AssetConfiguration configuration) private _assetConfiguration;
    mapping(bytes32 loanId => CollateralVault vault) private _vaults;
    mapping(bytes32 collateralId => bytes32 loanId) public collateralLoan;
    mapping(bytes32 loanId => bytes32[] collateralIds) private _collateralIds;
    mapping(bytes32 loanId => mapping(bytes32 assetId => uint256 quantity)) public loanExposure;
    mapping(address borrower => mapping(bytes32 assetId => uint256 quantity)) public
        borrowerExposure;

    event CollateralAssetConfigured(
        bytes32 indexed assetId,
        address indexed token,
        RiskTypes.CollateralKind kind,
        bool enabled,
        bool isUFT
    );
    event LoanCollateralVaultCreated(bytes32 indexed loanId, address indexed vault);
    event CollateralRegistered(
        bytes32 indexed loanId,
        bytes32 indexed collateralId,
        bytes32 indexed assetId,
        uint256 quantity
    );
    event CollateralReleased(
        bytes32 indexed loanId, bytes32 indexed collateralId, address indexed recipient
    );
    event CollateralLiquidated(
        bytes32 indexed loanId,
        bytes32 indexed collateralId,
        address indexed recipient,
        uint256 quantity
    );
    event LiquidationEngineConfigured(address indexed engine);
    event UFTDebtCeilingConfigured(uint256 ceiling, bytes32 indexed evidenceHash);
    event UFTBackedDebtBound(bytes32 indexed loanId, uint256 debtValue);

    constructor(
        IRoleManager roleManager_,
        ILoanRegistry loanRegistry_,
        AssetRegistry assetRegistry_,
        bytes32 uftAssetId_,
        IERC20 uft_
    ) RoleControlled(roleManager_) {
        if (
            address(loanRegistry_) == address(0) || address(assetRegistry_) == address(0)
                || uftAssetId_ == bytes32(0) || address(uft_).code.length == 0
        ) {
            revert InvalidCollateralConfiguration();
        }
        loanRegistry = loanRegistry_;
        assetRegistry = assetRegistry_;
        uftAssetId = uftAssetId_;
        uft = uft_;
    }

    function configureAsset(
        bytes32 assetId,
        address token,
        RiskTypes.CollateralKind kind,
        bool enabled,
        bool isUFT
    ) external onlyRole(ProtocolRoles.RISK_COUNCIL_ROLE) {
        if (
            assetId == bytes32(0) || kind == RiskTypes.CollateralKind.NONE
                || (kind == RiskTypes.CollateralKind.NATIVE && token != address(0))
                || (kind != RiskTypes.CollateralKind.NATIVE && token.code.length == 0)
                || isUFT != (assetId == uftAssetId && token == address(uft))
        ) {
            revert InvalidCollateralConfiguration();
        }
        if (kind != RiskTypes.CollateralKind.NATIVE) {
            AssetRegistry.AssetRecord memory registered = assetRegistry.resolve(assetId);
            if (!registered.active || registered.token != token) {
                revert InvalidCollateralConfiguration();
            }
        }
        AssetConfiguration memory existing = _assetConfiguration[assetId];
        if (
            existing.kind != RiskTypes.CollateralKind.NONE
                && (existing.token != token || existing.kind != kind || existing.isUFT != isUFT)
        ) {
            revert InvalidCollateralConfiguration();
        }
        _assetConfiguration[assetId] =
            AssetConfiguration({ token: token, kind: kind, enabled: enabled, isUFT: isUFT });
        emit CollateralAssetConfigured(assetId, token, kind, enabled, isUFT);
    }

    function configureLiquidationEngine(address engine)
        external
        onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
    {
        if (engine.code.length == 0 || liquidationEngine != address(0)) {
            revert InvalidCollateralConfiguration();
        }
        liquidationEngine = engine;
        emit LiquidationEngineConfigured(engine);
    }

    function configureUFTDebtCeiling(uint256 ceiling, bytes32 evidenceHash)
        external
        onlyRole(ProtocolRoles.RISK_COUNCIL_ROLE)
    {
        if (ceiling == 0 || ceiling < totalUftBackedDebt || evidenceHash == bytes32(0)) {
            revert InvalidCollateralConfiguration();
        }
        uftBackedDebtCeiling = ceiling;
        emit UFTDebtCeilingConfigured(ceiling, evidenceHash);
    }

    function bindUFTBackedDebt(bytes32 loanId, uint256 debtValue)
        external
        onlyRole(ProtocolRoles.RISK_COUNCIL_ROLE)
    {
        if (
            !loanRegistry.exists(loanId) || debtValue == 0 || uftBackedDebt[loanId] != 0
                || totalUftBackedDebt + debtValue > uftBackedDebtCeiling
        ) {
            revert UFTExposureExceeded();
        }
        uftBackedDebt[loanId] = debtValue;
        totalUftBackedDebt += debtValue;
        emit UFTBackedDebtBound(loanId, debtValue);
    }

    function closeUFTBackedDebt(bytes32 loanId) external {
        if (
            !loanRegistry.isTerminal(loanId)
                || ICollateralizedDebt(loanRegistry.loanAccount(loanId)).outstandingPrincipal() != 0
                || loanExposure[loanId][uftAssetId] != 0
        ) {
            revert InvalidCollateralOperation();
        }
        uint256 debt = uftBackedDebt[loanId];
        if (debt == 0) revert InvalidCollateralOperation();
        delete uftBackedDebt[loanId];
        totalUftBackedDebt -= debt;
        emit UFTBackedDebtBound(loanId, 0);
    }

    function lockERC20(bytes32 loanId, bytes32 collateralId, bytes32 assetId, uint256 amount)
        external
    {
        AssetConfiguration memory configuration =
            _validateDeposit(loanId, collateralId, assetId, RiskTypes.CollateralKind.ERC20, amount);
        CollateralVault vault = _vault(loanId);
        vault.depositERC20(collateralId, assetId, configuration.token, msg.sender, amount);
        _register(loanId, collateralId, assetId, amount);
    }

    function createVault(bytes32 loanId) external returns (address) {
        if (
            !loanRegistry.exists(loanId) || loanRegistry.isTerminal(loanId)
                || loanRegistry.borrowerOf(loanId) != msg.sender
        ) {
            revert InvalidCollateralOperation();
        }
        return address(_vault(loanId));
    }

    function lockNative(bytes32 loanId, bytes32 collateralId, bytes32 assetId) external payable {
        _validateDeposit(loanId, collateralId, assetId, RiskTypes.CollateralKind.NATIVE, msg.value);
        CollateralVault vault = _vault(loanId);
        vault.depositNative{ value: msg.value }(collateralId, assetId, msg.sender);
        _register(loanId, collateralId, assetId, msg.value);
    }

    function lockERC721(bytes32 loanId, bytes32 collateralId, bytes32 assetId, uint256 tokenId)
        external
    {
        AssetConfiguration memory configuration =
            _validateDeposit(loanId, collateralId, assetId, RiskTypes.CollateralKind.ERC721, 1);
        CollateralVault vault = _vault(loanId);
        vault.depositERC721(collateralId, assetId, configuration.token, msg.sender, tokenId);
        _register(loanId, collateralId, assetId, 1);
    }

    function lockERC1155(
        bytes32 loanId,
        bytes32 collateralId,
        bytes32 assetId,
        uint256 tokenId,
        uint256 amount,
        bytes calldata data
    ) external {
        AssetConfiguration memory configuration = _validateDeposit(
            loanId, collateralId, assetId, RiskTypes.CollateralKind.ERC1155, amount
        );
        CollateralVault vault = _vault(loanId);
        vault.depositERC1155(
            collateralId, assetId, configuration.token, msg.sender, tokenId, amount, data
        );
        _register(loanId, collateralId, assetId, amount);
    }

    function releaseCollateral(
        bytes32 loanId,
        bytes32 collateralId,
        address recipient,
        bytes32 journalRef
    ) external {
        address borrower = loanRegistry.borrowerOf(loanId);
        if (
            msg.sender != borrower || recipient != borrower || journalRef == bytes32(0)
                || !loanRegistry.isTerminal(loanId)
                || ICollateralizedDebt(loanRegistry.loanAccount(loanId)).outstandingPrincipal() != 0
                || collateralLoan[collateralId] != loanId
        ) {
            revert InvalidCollateralOperation();
        }
        RiskTypes.CollateralItem memory item = _vaults[loanId].collateral(collateralId);
        uint256 quantity = item.quantity;
        _decreaseExposure(loanId, borrower, item.assetId, quantity);
        _vaults[loanId].dispose(
            collateralId, recipient, quantity, RiskTypes.CollateralStatus.RELEASED
        );
        emit CollateralReleased(loanId, collateralId, recipient);
    }

    function liquidateCollateral(
        bytes32 loanId,
        bytes32 collateralId,
        address recipient,
        uint256 quantity
    ) external {
        if (msg.sender != liquidationEngine) {
            revert UnauthorizedLiquidationEngine();
        }
        if (collateralLoan[collateralId] != loanId) revert InvalidCollateralOperation();
        RiskTypes.CollateralItem memory item = _vaults[loanId].collateral(collateralId);
        _decreaseExposure(loanId, loanRegistry.borrowerOf(loanId), item.assetId, quantity);
        _vaults[loanId].dispose(
            collateralId, recipient, quantity, RiskTypes.CollateralStatus.LIQUIDATED
        );
        emit CollateralLiquidated(loanId, collateralId, recipient, quantity);
    }

    function collateralOf(bytes32 loanId)
        external
        view
        returns (RiskTypes.CollateralItem[] memory items)
    {
        bytes32[] storage ids = _collateralIds[loanId];
        items = new RiskTypes.CollateralItem[](ids.length);
        for (uint256 index = 0; index < ids.length; ++index) {
            items[index] = _vaults[loanId].collateral(ids[index]);
        }
    }

    function vaultOf(bytes32 loanId) external view returns (address) {
        return address(_vaults[loanId]);
    }

    function assetConfiguration(bytes32 assetId) external view returns (AssetConfiguration memory) {
        return _assetConfiguration[assetId];
    }

    function isUFTExposureCompliant(bytes32 loanId, address borrower) external view returns (bool) {
        uint256 supply = uft.totalSupply();
        return loanExposure[loanId][uftAssetId] <= supply * UFT_SINGLE_LOAN_EXPOSURE_BPS / BPS
            && borrowerExposure[borrower][uftAssetId] <= supply * UFT_BORROWER_EXPOSURE_BPS / BPS
            && totalUftBackedDebt <= uftBackedDebtCeiling;
    }

    function _validateDeposit(
        bytes32 loanId,
        bytes32 collateralId,
        bytes32 assetId,
        RiskTypes.CollateralKind expectedKind,
        uint256 quantity
    ) private view returns (AssetConfiguration memory configuration) {
        configuration = _assetConfiguration[assetId];
        if (
            !loanRegistry.exists(loanId) || loanRegistry.isTerminal(loanId)
                || loanRegistry.borrowerOf(loanId) != msg.sender || collateralId == bytes32(0)
                || collateralLoan[collateralId] != bytes32(0) || quantity == 0
                || !configuration.enabled || configuration.kind != expectedKind
        ) {
            revert InvalidCollateralOperation();
        }
        if (configuration.isUFT) {
            if (uftBackedDebt[loanId] == 0) revert UFTExposureExceeded();
            uint256 supply = uft.totalSupply();
            if (
                loanExposure[loanId][assetId] + quantity
                        > supply * UFT_SINGLE_LOAN_EXPOSURE_BPS / BPS
                    || borrowerExposure[msg.sender][assetId] + quantity
                        > supply * UFT_BORROWER_EXPOSURE_BPS / BPS
            ) {
                revert UFTExposureExceeded();
            }
        }
    }

    function _vault(bytes32 loanId) private returns (CollateralVault vault) {
        vault = _vaults[loanId];
        if (address(vault) == address(0)) {
            vault = new CollateralVault{ salt: loanId }(loanId, address(this));
            _vaults[loanId] = vault;
            emit LoanCollateralVaultCreated(loanId, address(vault));
        }
    }

    function _register(bytes32 loanId, bytes32 collateralId, bytes32 assetId, uint256 quantity)
        private
    {
        collateralLoan[collateralId] = loanId;
        _collateralIds[loanId].push(collateralId);
        loanExposure[loanId][assetId] += quantity;
        borrowerExposure[msg.sender][assetId] += quantity;
        emit CollateralRegistered(loanId, collateralId, assetId, quantity);
    }

    function _decreaseExposure(bytes32 loanId, address borrower, bytes32 assetId, uint256 quantity)
        private
    {
        if (
            quantity == 0 || loanExposure[loanId][assetId] < quantity
                || borrowerExposure[borrower][assetId] < quantity
        ) {
            revert InvalidCollateralOperation();
        }
        loanExposure[loanId][assetId] -= quantity;
        borrowerExposure[borrower][assetId] -= quantity;
    }
}
