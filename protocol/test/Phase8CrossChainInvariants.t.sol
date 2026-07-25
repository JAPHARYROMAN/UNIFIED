// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ICrossChainCoordinator } from "../src/interfaces/ICrossChainCoordinator.sol";
import { IUnifiedToken } from "../src/interfaces/IUnifiedToken.sol";
import { BridgeExposurePolicy } from "../src/crosschain/BridgeExposurePolicy.sol";
import { ChainRegistry } from "../src/crosschain/ChainRegistry.sol";
import { CrossChainTypes } from "../src/crosschain/CrossChainTypes.sol";
import { RouteRegistry } from "../src/crosschain/RouteRegistry.sol";
import { SatelliteCollateralVault } from "../src/crosschain/SatelliteCollateralVault.sol";
import { UFTBridgeHub } from "../src/crosschain/UFTBridgeHub.sol";
import { WrappedUFT } from "../src/crosschain/WrappedUFT.sol";
import { EmergencyController } from "../src/kernel/EmergencyController.sol";
import { ProtocolRoles } from "../src/kernel/ProtocolRoles.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";

interface Phase8InvariantVm {
    function warp(uint256 timestamp) external;
}

contract Phase8InvariantToken is ERC20 {
    uint256 public constant MAX_SUPPLY = 1_000_000 ether;

    constructor() ERC20("Phase 8 Invariant Token", "P8INV") {
        _mint(msg.sender, MAX_SUPPLY);
    }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

contract Phase8InvariantCoordinator is ICrossChainCoordinator {
    bytes32 public immutable override protocolId;
    uint256 public immutable override localChainId;
    address public immutable override recoveryController;
    mapping(bytes32 lane => uint64 nonce) public override nextOutboundNonce;
    mapping(bytes32 id => bytes32 result) public override executionResult;
    mapping(bytes32 id => bytes32 hash) public override tombstoneHash;
    mapping(bytes32 id => CrossChainTypes.MessageState state) private _states;
    mapping(bytes32 id => CrossChainTypes.MessageEnvelope envelope) private _envelopes;

    constructor(bytes32 protocolId_, uint256 localChainId_) {
        protocolId = protocolId_;
        localChainId = localChainId_;
        recoveryController = address(this);
    }

    function sendMessage(CrossChainTypes.MessageEnvelope calldata envelope, bytes calldata payload)
        external
        returns (bytes32 messageId)
    {
        require(envelope.sourceComponent == msg.sender, "source");
        require(envelope.payloadHash == keccak256(payload), "payload");
        require(envelope.sourceNonce == nextOutboundNonce[envelope.laneId] + 1, "nonce");
        messageId = CrossChainTypes.messageId(envelope);
        require(messageId == envelope.messageId, "id");
        require(_states[messageId] == CrossChainTypes.MessageState.NONE, "replay");
        nextOutboundNonce[envelope.laneId] = envelope.sourceNonce;
        _states[messageId] = CrossChainTypes.MessageState.SENT;
        _envelopes[messageId] = envelope;
    }

    function messageState(bytes32 messageId) external view returns (CrossChainTypes.MessageState) {
        return _states[messageId];
    }

    function messageEnvelope(bytes32 messageId)
        external
        view
        returns (CrossChainTypes.MessageEnvelope memory)
    {
        return _envelopes[messageId];
    }

    function deliverMint(
        WrappedUFT wrapped,
        CrossChainTypes.MessageEnvelope calldata envelope,
        bytes calldata payload
    ) external {
        _envelopes[envelope.messageId] = envelope;
        wrapped.handleCrossChainMessage(
            envelope.messageId, CrossChainTypes.ACTION_HOME_UFT_MINT_AUTHORIZED, payload
        );
        _states[envelope.messageId] = CrossChainTypes.MessageState.EXECUTED;
    }

    function deliverCollateralRelease(
        SatelliteCollateralVault vault,
        bytes32 messageId,
        bytes calldata payload
    ) external {
        vault.handleCrossChainMessage(
            messageId, CrossChainTypes.ACTION_HOME_COLLATERAL_RELEASE_AUTHORIZED, payload
        );
    }
}

    contract Phase8InvariantRecovery { }

    contract Phase8InvariantCollateralComponent {
        SatelliteCollateralVault public vault;
        uint256 public reportCount;

        function bind(SatelliteCollateralVault vault_) external {
            require(address(vault) == address(0), "bound");
            vault = vault_;
        }

        function provision(CrossChainTypes.SatelliteLoanProvisioning calldata provisioning)
            external
        {
            vault.provisionLoan(provisioning);
        }

        function reportCollateralLocked(bytes32 loanId, bytes32 operationId, uint256 amount)
            external
            returns (bytes32)
        {
            return keccak256(abi.encode("LOCK", ++reportCount, loanId, operationId, amount));
        }

        function reportCollateralReleased(bytes32 loanId, bytes32 operationId, uint256 amount)
            external
            returns (bytes32)
        {
            return keccak256(abi.encode("RELEASE", ++reportCount, loanId, operationId, amount));
        }
    }

    contract Phase8BridgeInvariantHandler {
        UFTBridgeHub public immutable hub;
        WrappedUFT public immutable wrapped;
        Phase8InvariantToken public immutable token;
        Phase8InvariantCoordinator public immutable homeCoordinator;
        Phase8InvariantCoordinator public immutable satelliteCoordinator;
        bytes32 public immutable routeOne;
        bytes32 public immutable routeTwo;
        bytes32[] private _messageIds;
        uint256 public lockCount;

        constructor(
            UFTBridgeHub hub_,
            WrappedUFT wrapped_,
            Phase8InvariantToken token_,
            Phase8InvariantCoordinator homeCoordinator_,
            Phase8InvariantCoordinator satelliteCoordinator_,
            bytes32 routeOne_,
            bytes32 routeTwo_
        ) {
            hub = hub_;
            wrapped = wrapped_;
            token = token_;
            homeCoordinator = homeCoordinator_;
            satelliteCoordinator = satelliteCoordinator_;
            routeOne = routeOne_;
            routeTwo = routeTwo_;
            token_.approve(address(hub_), type(uint256).max);
        }

        function lock(uint256, uint256 amountSeed) external {
            if (hub.totalBridgeBacking() >= 150 ether) return;
            bytes32 route = routeOne;
            uint256 routeRemaining = 100 ether - hub.routeBacking(route);
            uint256 aggregateRemaining = 150 ether - hub.totalBridgeBacking();
            uint256 maximum = routeRemaining < aggregateRemaining
                ? routeRemaining
                : aggregateRemaining;
            if (maximum == 0) return;
            uint256 amount = (amountSeed % maximum) + 1;
            bytes32 lockId = keccak256(abi.encode("INV_LOCK", ++lockCount));
            bytes32 messageId = hub.lockForBridge(
                lockId, route, address(this), amount, uint64(block.timestamp + 1 days)
            );
            CrossChainTypes.MessageEnvelope memory envelope =
                homeCoordinator.messageEnvelope(messageId);
            bytes memory payload = abi.encode(
                CrossChainTypes.CanonicalUftLockPayload({
                    lockId: lockId,
                    loanId: bytes32(0),
                    canonicalToken: address(token),
                    homeBridgeHub: address(hub),
                    wrappedToken: address(wrapped),
                    destinationRecipient: address(this),
                    amount: amount
                })
            );
            satelliteCoordinator.deliverMint(wrapped, envelope, payload);
            _messageIds.push(messageId);
        }

        function donate(uint96 amountSeed) external {
            uint256 balance = token.balanceOf(address(this));
            if (balance == 0) return;
            uint256 amount = uint256(amountSeed) % (balance + 1);
            if (amount != 0) token.transfer(address(hub), amount);
        }

        function onWrappedMint(bytes32, bytes32, uint256) external view {
            require(msg.sender == address(wrapped), "wrapped caller");
        }

        function assertMessagesAtMostOnce() external view {
            for (uint256 i; i < _messageIds.length; ++i) {
                bytes32 messageId = _messageIds[i];
                CrossChainTypes.MessageEnvelope memory envelope =
                    homeCoordinator.messageEnvelope(messageId);
                require(
                    homeCoordinator.messageState(messageId) == CrossChainTypes.MessageState.SENT,
                    "source state"
                );
                require(homeCoordinator.nextOutboundNonce(envelope.laneId) == 1, "lane replay");
                require(
                    satelliteCoordinator.messageState(messageId)
                        == CrossChainTypes.MessageState.EXECUTED,
                    "destination state"
                );
            }
        }
    }

    contract Phase8CollateralInvariantHandler {
        Phase8InvariantToken public immutable token;
        Phase8InvariantCoordinator public immutable coordinator;
        Phase8InvariantCollateralComponent public immutable component;
        SatelliteCollateralVault public immutable vault;
        bytes32[] private _loanIds;
        mapping(bytes32 loanId => uint256 count) public releaseSuccesses;
        uint256 public lockedAmount;
        uint256 public releasedAmount;
        uint256 private _nonce;

        constructor(
            Phase8InvariantToken token_,
            Phase8InvariantCoordinator coordinator_,
            Phase8InvariantCollateralComponent component_,
            SatelliteCollateralVault vault_
        ) {
            token = token_;
            coordinator = coordinator_;
            component = component_;
            vault = vault_;
            token_.approve(address(vault_), type(uint256).max);
        }

        function provisionLockAndMaybeRelease(uint256 amountSeed, bool release) external {
            uint256 balance = token.balanceOf(address(this));
            if (balance == 0) return;
            uint256 amount = (amountSeed % (balance < 10 ether ? balance : 10 ether)) + 1;
            bytes32 loanId = keccak256(abi.encode("INV_LOAN", ++_nonce));
            bytes32 collateralId = keccak256(abi.encode("INV_COLLATERAL", _nonce));
            CrossChainTypes.SatelliteLoanProvisioning memory provisioning =
                CrossChainTypes.SatelliteLoanProvisioning({
                    loanId: loanId,
                    fundingLockId: keccak256(abi.encode("FUND", _nonce)),
                    homeLoanAccount: address(0x1111),
                    homeLoanRouter: address(0x2222),
                    borrower: address(this),
                    lender: address(0x3333),
                    wrappedToken: address(0x4444),
                    collateralToken: address(token),
                    collateralId: collateralId,
                    principalAmount: amount,
                    collateralAmount: amount,
                    repaymentRoutePolicyHash: keccak256("INV_REPAYMENT_ROUTE"),
                    policyHash: keccak256("INV_POLICY")
                });
            component.provision(provisioning);
            vault.lockCollateral(loanId);
            lockedAmount += amount;
            _loanIds.push(loanId);

            CrossChainTypes.SatelliteLoanProvisioning memory duplicate = provisioning;
            duplicate.loanId = keccak256(abi.encode("DUPLICATE_LOAN", _nonce));
            (bool duplicateAccepted,) = address(component)
                .call(abi.encodeCall(Phase8InvariantCollateralComponent.provision, (duplicate)));
            require(!duplicateAccepted, "collateral reused");

            if (release) _release(provisioning);
        }

        function _release(CrossChainTypes.SatelliteLoanProvisioning memory provisioning) private {
            bytes memory payload = abi.encode(
                CrossChainTypes.HomeCollateralReleaseAuthorizedPayload({
                    loanId: provisioning.loanId,
                    collateralId: provisioning.collateralId,
                    homeLoanAccount: provisioning.homeLoanAccount,
                    borrower: provisioning.borrower,
                    lender: provisioning.lender,
                    collateralToken: provisioning.collateralToken,
                    amount: provisioning.collateralAmount,
                    policyHash: provisioning.policyHash
                })
            );
            coordinator.deliverCollateralRelease(
                vault, keccak256(abi.encode("RELEASE_MESSAGE", provisioning.loanId)), payload
            );
            ++releaseSuccesses[provisioning.loanId];
            releasedAmount += provisioning.collateralAmount;
            (bool releasedTwice,) = address(coordinator)
                .call(
                    abi.encodeCall(
                        Phase8InvariantCoordinator.deliverCollateralRelease,
                        (
                            vault,
                            keccak256(abi.encode("SECOND_RELEASE", provisioning.loanId)),
                            payload
                        )
                    )
                );
            require(!releasedTwice, "collateral released twice");
        }

        function assertCollateralState() external view {
            for (uint256 i; i < _loanIds.length; ++i) {
                bytes32 loanId = _loanIds[i];
                SatelliteCollateralVault.CollateralRecord memory record =
                    vault.collateralRecord(loanId);
                require(vault.collateralLoan(record.collateralId) == loanId, "exclusivity");
                require(releaseSuccesses[loanId] <= 1, "multiple releases");
                if (releaseSuccesses[loanId] == 1) {
                    require(
                        record.state == CrossChainTypes.SatelliteCollateralState.RELEASED,
                        "release state"
                    );
                }
            }
        }
    }

    contract Phase8CrossChainInvariantTest {
        struct FuzzSelector {
            address addr;
            bytes4[] selectors;
        }

        Phase8InvariantVm private constant vm =
            Phase8InvariantVm(address(uint160(uint256(keccak256("hevm cheat code")))));
        uint64 private constant NOW = 1_900_000_000;
        uint256 private constant HOME = 31_337;
        uint256 private constant SATELLITE = 31_338;
        bytes32 private constant PROTOCOL = keccak256("PHASE8_INVARIANT_PROTOCOL");
        bytes32 private constant ADAPTER = keccak256("PHASE8_INVARIANT_ADAPTER");

        Phase8InvariantToken private canonical;
        Phase8InvariantToken private collateral;
        Phase8InvariantCoordinator private homeCoordinator;
        Phase8InvariantCoordinator private satelliteCoordinator;
        UFTBridgeHub private hub;
        WrappedUFT private wrapped;
        Phase8BridgeInvariantHandler private bridgeHandler;
        SatelliteCollateralVault private collateralVault;
        Phase8CollateralInvariantHandler private collateralHandler;
        bytes32 private routeOne;
        bytes32 private routeTwo;
        address[] private _targets;

        function setUp() public {
            vm.warp(NOW);
            RoleManager roles = new RoleManager(address(0xA11), address(this));
            roles.grantRole(ProtocolRoles.RISK_COUNCIL_ROLE, address(this), type(uint64).max);
            canonical = new Phase8InvariantToken();
            collateral = new Phase8InvariantToken();
            homeCoordinator = new Phase8InvariantCoordinator(PROTOCOL, HOME);
            satelliteCoordinator = new Phase8InvariantCoordinator(PROTOCOL, SATELLITE);
            Phase8InvariantRecovery recovery = new Phase8InvariantRecovery();
            ChainRegistry chains = new ChainRegistry(roles, HOME);
            EmergencyController emergency = new EmergencyController(roles);
            RouteRegistry routes = new RouteRegistry(roles, chains, emergency);
            BridgeExposurePolicy exposure =
                new BridgeExposurePolicy(roles, IUnifiedToken(address(canonical)));
            hub = new UFTBridgeHub(
                roles,
                IUnifiedToken(address(canonical)),
                homeCoordinator,
                routes,
                exposure,
                address(recovery)
            );
            wrapped = new WrappedUFT(
                roles,
                HOME,
                address(canonical),
                address(hub),
                satelliteCoordinator,
                routes,
                address(recovery)
            );
            chains.registerChain(
                HOME,
                address(homeCoordinator),
                address(recovery),
                address(homeCoordinator).codehash,
                address(recovery).codehash,
                keccak256("HOME"),
                NOW
            );
            chains.registerChain(
                SATELLITE,
                address(satelliteCoordinator),
                address(recovery),
                address(satelliteCoordinator).codehash,
                address(recovery).codehash,
                keccak256("SATELLITE"),
                NOW
            );
            routeOne = routes.registerRoute(
                _route(address(hub), address(wrapped), keccak256("ONE"))
            );
            routeTwo = routes.registerRoute(
                _route(address(hub), address(wrapped), keccak256("TWO"))
            );
            bytes32 policy = exposure.registerPolicy(
                BridgeExposurePolicy.ExposureConfig({
                    circulatingSupplyReference: canonical.MAX_SUPPLY(),
                    circulatingSupplyEvidenceHash: keccak256("SUPPLY"),
                    routeAbsoluteCap: 100 ether,
                    chainAbsoluteCap: 150 ether,
                    adapterAbsoluteCap: 150 ether,
                    aggregateAbsoluteCap: 150 ether,
                    routePercentageCeilingBps: 500,
                    aggregatePercentageCeilingBps: 1_500,
                    activationDelay: 0,
                    activeFrom: NOW
                })
            );
            exposure.activateForRoute(routeOne, policy);
            exposure.activateForRoute(routeTwo, policy);
            wrapped.configureCanonicalBackingRoute(routeOne);
            bridgeHandler = new Phase8BridgeInvariantHandler(
                hub, wrapped, canonical, homeCoordinator, satelliteCoordinator, routeOne, routeTwo
            );
            canonical.transfer(address(bridgeHandler), 1_000 ether);

            Phase8InvariantCollateralComponent component = new Phase8InvariantCollateralComponent();
            collateralVault =
                new SatelliteCollateralVault(address(component), satelliteCoordinator, collateral);
            component.bind(collateralVault);
            collateralHandler = new Phase8CollateralInvariantHandler(
                collateral, satelliteCoordinator, component, collateralVault
            );
            collateral.transfer(address(collateralHandler), 1_000 ether);
            _targets.push(address(bridgeHandler));
            _targets.push(address(collateralHandler));
        }

        function invariant_BackingFloorAndAccountingSums() public view {
            uint256 total = hub.totalBridgeBacking();
            require(canonical.balanceOf(address(hub)) >= total, "backing floor");
            require(hub.routeBacking(routeOne) + hub.routeBacking(routeTwo) == total, "route sum");
            require(hub.backingForChain(SATELLITE) == total, "chain sum");
            require(hub.adapterBacking(ADAPTER) == total, "adapter sum");
        }

        function invariant_WrappedSupplyNeverExceedsChainBacking() public view {
            require(wrapped.totalSupply() <= hub.backingForChain(SATELLITE), "unbacked wrapped");
        }

        function invariant_AllCapDimensionsHold() public view {
            require(hub.routeBacking(routeOne) <= 100 ether, "route one cap");
            require(hub.routeBacking(routeTwo) <= 100 ether, "route two cap");
            require(hub.backingForChain(SATELLITE) <= 150 ether, "chain cap");
            require(hub.adapterBacking(ADAPTER) <= 150 ether, "adapter cap");
            require(hub.totalBridgeBacking() <= 150 ether, "aggregate cap");
        }

        function invariant_LanesAndMessagesProgressAtMostOnce() public view {
            bridgeHandler.assertMessagesAtMostOnce();
        }

        function invariant_CollateralExclusiveAndReleasedAtMostOnce() public view {
            collateralHandler.assertCollateralState();
            require(
                collateral.balanceOf(address(collateralVault))
                    == collateralHandler.lockedAmount() - collateralHandler.releasedAmount(),
                "collateral custody equation"
            );
        }

        function testInvariantHarnessCanLockAndMint() public {
            bridgeHandler.lock(0, 1 ether);
            require(hub.totalBridgeBacking() != 0, "handler did not lock");
            require(wrapped.totalSupply() == hub.totalBridgeBacking(), "handler did not mint");
        }

        function targetSelectors() external view returns (FuzzSelector[] memory targets) {
            targets = new FuzzSelector[](2);
            bytes4[] memory bridgeSelectors = new bytes4[](2);
            bridgeSelectors[0] = bridgeHandler.lock.selector;
            bridgeSelectors[1] = bridgeHandler.donate.selector;
            targets[0] = FuzzSelector({ addr: address(bridgeHandler), selectors: bridgeSelectors });
            bytes4[] memory collateralSelectors = new bytes4[](1);
            collateralSelectors[0] = collateralHandler.provisionLockAndMaybeRelease.selector;
            targets[1] =
                FuzzSelector({ addr: address(collateralHandler), selectors: collateralSelectors });
        }

        function targetContracts() external view returns (address[] memory) {
            return _targets;
        }

        function _route(address source, address destination, bytes32 family)
            private
            view
            returns (RouteRegistry.RouteConfig memory)
        {
            return RouteRegistry.RouteConfig({
                sourceChainVersion: 1,
                destinationChainVersion: 1,
                sourceChainId: HOME,
                sourceCoordinator: address(homeCoordinator),
                sourceComponent: source,
                sourceComponentCodeHash: source.codehash,
                destinationChainId: SATELLITE,
                destinationCoordinator: address(satelliteCoordinator),
                destinationComponent: destination,
                destinationComponentCodeHash: destination.codehash,
                actionFamily: family,
                allowedActionsBitmap: uint32(1) << 1,
                adapterId: ADAPTER,
                adapterCodeHash: keccak256("ADAPTER_CODE"),
                adapterSetPolicyHash: keccak256("ADAPTER_SET"),
                sourceFinalityPolicyHash: keccak256("SOURCE_FINALITY"),
                destinationFinalityPolicyHash: keccak256("DESTINATION_FINALITY"),
                sourceSignerSetHash: keccak256("SOURCE_SIGNERS"),
                destinationSignerSetHash: keccak256("DESTINATION_SIGNERS"),
                absoluteCap: 100 ether,
                chainCap: 150 ether,
                adapterCap: 150 ether,
                activatedAt: NOW
            });
        }
    }
