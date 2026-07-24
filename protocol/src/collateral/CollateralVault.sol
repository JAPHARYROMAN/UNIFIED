// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC1155Receiver } from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { RiskTypes } from "../risk/RiskTypes.sol";

/// @notice Per-loan custody vault that rejects unsolicited NFT callbacks.
contract CollateralVault is IERC721Receiver, IERC1155Receiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error UnauthorizedVaultCaller();
    error InvalidCollateral();
    error CollateralAlreadyExists(bytes32 collateralId);
    error InvalidCollateralState(bytes32 collateralId);
    error CustodyBalanceMismatch();
    error UnsolicitedTokenCallback();

    bytes32 public immutable loanId;
    address public immutable manager;
    mapping(bytes32 collateralId => RiskTypes.CollateralItem item) private _items;
    mapping(bytes32 assetId => uint256 quantity) private _assetBalance;
    bytes32 private _expectedCallback;

    event CollateralLocked(
        bytes32 indexed collateralId,
        bytes32 indexed assetId,
        RiskTypes.CollateralKind kind,
        address indexed owner,
        address token,
        uint256 tokenId,
        uint256 quantity
    );
    event CollateralDisposed(
        bytes32 indexed collateralId,
        address indexed recipient,
        uint256 quantity,
        RiskTypes.CollateralStatus status
    );

    modifier onlyManager() {
        if (msg.sender != manager) revert UnauthorizedVaultCaller();
        _;
    }

    constructor(bytes32 loanId_, address manager_) {
        if (loanId_ == bytes32(0) || manager_ == address(0)) revert InvalidCollateral();
        loanId = loanId_;
        manager = manager_;
    }

    function depositERC20(
        bytes32 collateralId,
        bytes32 assetId,
        address token,
        address owner,
        uint256 amount
    ) external onlyManager nonReentrant {
        _requireNew(collateralId, assetId, token, owner, amount);
        uint256 beforeBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(owner, address(this), amount);
        if (IERC20(token).balanceOf(address(this)) - beforeBalance != amount) {
            revert CustodyBalanceMismatch();
        }
        _store(collateralId, assetId, RiskTypes.CollateralKind.ERC20, token, 0, owner, amount);
    }

    function depositNative(bytes32 collateralId, bytes32 assetId, address owner)
        external
        payable
        onlyManager
        nonReentrant
    {
        _requireNew(collateralId, assetId, address(this), owner, msg.value);
        _store(
            collateralId, assetId, RiskTypes.CollateralKind.NATIVE, address(0), 0, owner, msg.value
        );
    }

    function depositERC721(
        bytes32 collateralId,
        bytes32 assetId,
        address token,
        address owner,
        uint256 tokenId
    ) external onlyManager nonReentrant {
        _requireNew(collateralId, assetId, token, owner, 1);
        _expectedCallback =
            keccak256(abi.encode(RiskTypes.CollateralKind.ERC721, token, owner, tokenId, 1));
        IERC721(token).safeTransferFrom(owner, address(this), tokenId);
        if (_expectedCallback != bytes32(0) || IERC721(token).ownerOf(tokenId) != address(this)) {
            revert CustodyBalanceMismatch();
        }
        _store(collateralId, assetId, RiskTypes.CollateralKind.ERC721, token, tokenId, owner, 1);
    }

    function depositERC1155(
        bytes32 collateralId,
        bytes32 assetId,
        address token,
        address owner,
        uint256 tokenId,
        uint256 amount,
        bytes calldata data
    ) external onlyManager nonReentrant {
        _requireNew(collateralId, assetId, token, owner, amount);
        uint256 beforeBalance = IERC1155(token).balanceOf(address(this), tokenId);
        _expectedCallback =
            keccak256(abi.encode(RiskTypes.CollateralKind.ERC1155, token, owner, tokenId, amount));
        IERC1155(token).safeTransferFrom(owner, address(this), tokenId, amount, data);
        if (
            _expectedCallback != bytes32(0)
                || IERC1155(token).balanceOf(address(this), tokenId) - beforeBalance != amount
        ) {
            revert CustodyBalanceMismatch();
        }
        _store(
            collateralId, assetId, RiskTypes.CollateralKind.ERC1155, token, tokenId, owner, amount
        );
    }

    function dispose(
        bytes32 collateralId,
        address recipient,
        uint256 quantity,
        RiskTypes.CollateralStatus targetStatus
    ) external onlyManager nonReentrant {
        RiskTypes.CollateralItem storage item = _items[collateralId];
        if (
            item.status != RiskTypes.CollateralStatus.LOCKED || recipient == address(0)
                || quantity == 0 || quantity > item.quantity
                || (targetStatus != RiskTypes.CollateralStatus.RELEASED
                    && targetStatus != RiskTypes.CollateralStatus.LIQUIDATED
                    && targetStatus != RiskTypes.CollateralStatus.CLAIMED)
                || (item.kind == RiskTypes.CollateralKind.ERC721 && quantity != 1)
        ) {
            revert InvalidCollateralState(collateralId);
        }
        item.quantity -= quantity;
        _assetBalance[item.assetId] -= quantity;
        if (item.quantity == 0) item.status = targetStatus;
        _transfer(item, recipient, quantity);
        emit CollateralDisposed(collateralId, recipient, quantity, targetStatus);
    }

    function collateral(bytes32 collateralId)
        external
        view
        returns (RiskTypes.CollateralItem memory)
    {
        return _items[collateralId];
    }

    function balanceOfAsset(bytes32 assetId) external view returns (uint256) {
        return _assetBalance[assetId];
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata)
        external
        returns (bytes4)
    {
        bytes32 callback =
            keccak256(abi.encode(RiskTypes.CollateralKind.ERC721, msg.sender, from, tokenId, 1));
        if (operator != address(this) || callback != _expectedCallback) {
            revert UnsolicitedTokenCallback();
        }
        _expectedCallback = bytes32(0);
        return IERC721Receiver.onERC721Received.selector;
    }

    function onERC1155Received(
        address operator,
        address from,
        uint256 tokenId,
        uint256 value,
        bytes calldata
    ) external returns (bytes4) {
        bytes32 callback = keccak256(
            abi.encode(RiskTypes.CollateralKind.ERC1155, msg.sender, from, tokenId, value)
        );
        if (operator != address(this) || callback != _expectedCallback) {
            revert UnsolicitedTokenCallback();
        }
        _expectedCallback = bytes32(0);
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        revert UnsolicitedTokenCallback();
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IERC721Receiver).interfaceId
            || interfaceId == type(IERC1155Receiver).interfaceId;
    }

    receive() external payable {
        if (msg.sender != manager) revert UnsolicitedTokenCallback();
    }

    function _requireNew(
        bytes32 collateralId,
        bytes32 assetId,
        address token,
        address owner,
        uint256 quantity
    ) private view {
        if (
            collateralId == bytes32(0) || assetId == bytes32(0) || token.code.length == 0
                || owner == address(0) || quantity == 0
        ) {
            revert InvalidCollateral();
        }
        if (_items[collateralId].status != RiskTypes.CollateralStatus.NONE) {
            revert CollateralAlreadyExists(collateralId);
        }
    }

    function _store(
        bytes32 collateralId,
        bytes32 assetId,
        RiskTypes.CollateralKind kind,
        address token,
        uint256 tokenId,
        address owner,
        uint256 quantity
    ) private {
        _items[collateralId] = RiskTypes.CollateralItem({
            collateralId: collateralId,
            assetId: assetId,
            kind: kind,
            token: token,
            tokenId: tokenId,
            quantity: quantity,
            owner: owner,
            lockedAt: uint64(block.timestamp),
            status: RiskTypes.CollateralStatus.LOCKED
        });
        _assetBalance[assetId] += quantity;
        emit CollateralLocked(collateralId, assetId, kind, owner, token, tokenId, quantity);
    }

    function _transfer(RiskTypes.CollateralItem storage item, address recipient, uint256 quantity)
        private
    {
        if (item.kind == RiskTypes.CollateralKind.NATIVE) {
            (bool success,) = recipient.call{ value: quantity }("");
            if (!success) revert CustodyBalanceMismatch();
        } else if (item.kind == RiskTypes.CollateralKind.ERC20) {
            uint256 vaultBefore = IERC20(item.token).balanceOf(address(this));
            uint256 recipientBefore = IERC20(item.token).balanceOf(recipient);
            IERC20(item.token).safeTransfer(recipient, quantity);
            if (
                vaultBefore - IERC20(item.token).balanceOf(address(this)) != quantity
                    || IERC20(item.token).balanceOf(recipient) - recipientBefore != quantity
            ) {
                revert CustodyBalanceMismatch();
            }
        } else if (item.kind == RiskTypes.CollateralKind.ERC721) {
            IERC721(item.token).safeTransferFrom(address(this), recipient, item.tokenId);
        } else if (item.kind == RiskTypes.CollateralKind.ERC1155) {
            IERC1155(item.token)
                .safeTransferFrom(address(this), recipient, item.tokenId, quantity, "");
        } else {
            revert InvalidCollateral();
        }
    }
}
