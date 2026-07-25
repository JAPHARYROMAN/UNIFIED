package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"math/big"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/unified-finance/unified/services/cross-chain-coordinator/store"
)

const phase8ReleaseEvidencePath = "protocol/deployments/local/phase8-release-evidence.json"

var requiredRoutePurposes = []string{
	"MINT",
	"REPORT",
	"REPAYMENT",
	"ALTERNATE_REPAYMENT",
	"BRIDGE_EXIT",
	"DISBURSEMENT",
	"COLLATERAL_RELEASE",
}

var requiredHomeContracts = map[string]struct{}{
	"role_manager": {}, "chain_registry": {}, "emergency_controller": {},
	"route_registry": {}, "finality_verifier": {}, "coordinator": {},
	"recovery_controller": {}, "canonical_uft": {}, "loan_registry": {},
	"bridge_exposure_policy": {}, "bridge_hub": {}, "loan_account_deployer": {},
	"loan_factory": {}, "loan_policy": {}, "loan_account": {},
}

var requiredSatelliteContracts = map[string]struct{}{
	"role_manager": {}, "chain_registry": {}, "emergency_controller": {},
	"route_registry": {}, "finality_verifier": {}, "coordinator": {},
	"recovery_controller": {}, "collateral_token": {}, "wrapped_uft": {},
	"satellite_loan_component": {}, "satellite_collateral_vault": {},
	"satellite_settlement_vault": {},
}

type phase8ReleaseManifest struct {
	SchemaVersion        uint32                   `json:"schema_version"`
	ArtifactType         string                   `json:"artifact_type"`
	Environment          string                   `json:"environment"`
	ContainsRealValue    bool                     `json:"contains_real_value"`
	RunID                string                   `json:"run_id"`
	ProtocolID           string                   `json:"protocol_id"`
	ProofBoundary        string                   `json:"proof_boundary"`
	GeneratedAt          string                   `json:"generated_at"`
	SourceCommit         string                   `json:"source_commit"`
	DeploymentFlowSHA256 string                   `json:"deployment_flow_sha256"`
	Domains              phase8ManifestDomains    `json:"domains"`
	Routes               []phase8ManifestRoute    `json:"routes"`
	ExposurePolicy       phase8ManifestExposure   `json:"exposure_policy"`
	Recovery             phase8ManifestRecovery   `json:"recovery"`
	Providers            []phase8ManifestProvider `json:"providers"`
	Flow                 json.RawMessage          `json:"flow"`
	Durable              json.RawMessage          `json:"durable"`
	Reset                json.RawMessage          `json:"reset"`
	Validation           json.RawMessage          `json:"validation"`
}

type phase8ManifestExposure struct {
	PolicyVersion                         uint64 `json:"policy_version"`
	PolicyHash                            string `json:"policy_hash"`
	CirculatingSupplyReferenceUnits       string `json:"circulating_supply_reference_units"`
	CirculatingSupplyEvidenceHash         string `json:"circulating_supply_evidence_hash"`
	RouteAbsoluteCapUnits                 string `json:"route_absolute_cap_units"`
	ChainAbsoluteCapUnits                 string `json:"chain_absolute_cap_units"`
	AdapterAbsoluteCapUnits               string `json:"adapter_absolute_cap_units"`
	AggregateAbsoluteCapUnits             string `json:"aggregate_absolute_cap_units"`
	RoutePercentageCeilingBasisPoints     uint32 `json:"route_percentage_ceiling_basis_points"`
	AggregatePercentageCeilingBasisPoints uint32 `json:"aggregate_percentage_ceiling_basis_points"`
	ActivationDelay                       uint64 `json:"activation_delay"`
	ActiveFrom                            uint64 `json:"active_from"`
}

type phase8ManifestDomains struct {
	Home      phase8ManifestDomain `json:"home"`
	Satellite phase8ManifestDomain `json:"satellite"`
}

type phase8ManifestDomain struct {
	ChainID               json.Number                       `json:"chain_id"`
	ChainVersion          uint32                            `json:"chain_version"`
	RPCURL                string                            `json:"rpc_url"`
	GenesisHash           string                            `json:"genesis_hash"`
	ConfigurationHash     string                            `json:"configuration_hash"`
	ActivationBlock       json.Number                       `json:"activation_block"`
	ActivationTimestamp   json.Number                       `json:"activation_timestamp"`
	RegistryStatus        string                            `json:"registry_status"`
	ObserverFixture       string                            `json:"observer_fixture"`
	ObserverPublicKey     string                            `json:"observer_public_key_ed25519"`
	ObserverAuthorityHash string                            `json:"observer_authority_hash"`
	ConfirmationDepth     uint64                            `json:"confirmation_depth"`
	SignerSet             phase8ManifestSignerSet           `json:"signer_set"`
	Contracts             map[string]phase8ManifestContract `json:"contracts"`
	FinalityPolicies      []phase8ManifestFinalityPolicy    `json:"finality_policies"`
	RegistryBindings      phase8ManifestRegistryBindings    `json:"registry_bindings"`
}

type phase8ManifestSignerSet struct {
	Version         uint32   `json:"version"`
	Hash            string   `json:"hash"`
	Threshold       uint32   `json:"threshold"`
	ValidFrom       uint64   `json:"valid_from"`
	ValidUntil      uint64   `json:"valid_until"`
	SortedAddresses []string `json:"sorted_addresses"`
}

type phase8ManifestContract struct {
	Address               string                       `json:"address"`
	RuntimeCodeHash       string                       `json:"runtime_code_hash"`
	ABIPath               string                       `json:"abi_path"`
	ABISHA256             string                       `json:"abi_sha256"`
	DeploymentKind        string                       `json:"deployment_kind"`
	DeploymentTransaction string                       `json:"deployment_tx_hash"`
	DeploymentBlockNumber json.Number                  `json:"deployment_block_number"`
	CreationEvent         *phase8ManifestCreationEvent `json:"creation_event,omitempty"`
}

type phase8ManifestCreationEvent struct {
	Emitter                     string `json:"emitter"`
	Signature                   string `json:"signature"`
	Topic0                      string `json:"topic0"`
	IndexedID                   string `json:"indexed_id"`
	IndexedIDTopicPosition      uint32 `json:"indexed_id_topic_position"`
	IndexedAddressTopicPosition uint32 `json:"indexed_address_topic_position"`
}

type phase8ManifestRegistryBindings struct {
	RouteRegistryChainRegistry    string `json:"route_registry_chain_registry"`
	FinalityVerifierChainRegistry string `json:"finality_verifier_chain_registry"`
}

type phase8ManifestFinalityPolicy struct {
	RoutePurpose                   string      `json:"route_purpose"`
	PolicyHash                     string      `json:"policy_hash"`
	DestinationEvidence            bool        `json:"destination_evidence"`
	SourceChainID                  json.Number `json:"source_chain_id"`
	SourceCoordinator              string      `json:"source_coordinator"`
	SourceComponent                string      `json:"source_component"`
	DestinationChainID             json.Number `json:"destination_chain_id"`
	DestinationCoordinator         string      `json:"destination_coordinator"`
	DestinationComponent           string      `json:"destination_component"`
	EvidenceChainVersion           uint32      `json:"evidence_chain_version"`
	EvidenceChainConfigurationHash string      `json:"evidence_chain_configuration_hash"`
	ActionFamily                   string      `json:"action_family"`
	AllowedActionsBitmap           uint32      `json:"allowed_actions_bitmap"`
	RequiredDepth                  uint64      `json:"required_depth"`
	ObserverAuthorityHash          string      `json:"observer_authority_hash"`
	SignerSetHash                  string      `json:"signer_set_hash"`
	SignerSetVersion               uint32      `json:"signer_set_version"`
}

type phase8ManifestRoute struct {
	Purpose                          string      `json:"purpose"`
	Version                          uint64      `json:"version"`
	RoutePolicyHash                  string      `json:"route_policy_hash"`
	SourceDomain                     string      `json:"source_domain"`
	DestinationDomain                string      `json:"destination_domain"`
	SourceChainVersion               uint32      `json:"source_chain_version"`
	DestinationChainVersion          uint32      `json:"destination_chain_version"`
	SourceChainID                    json.Number `json:"source_chain_id"`
	SourceCoordinator                string      `json:"source_coordinator"`
	SourceComponent                  string      `json:"source_component"`
	SourceComponentCodeHash          string      `json:"source_component_code_hash"`
	DestinationChainID               json.Number `json:"destination_chain_id"`
	DestinationCoordinator           string      `json:"destination_coordinator"`
	DestinationComponent             string      `json:"destination_component"`
	DestinationComponentCodeHash     string      `json:"destination_component_code_hash"`
	ActionFamily                     string      `json:"action_family"`
	AllowedActionsBitmap             uint32      `json:"allowed_actions_bitmap"`
	AdapterID                        string      `json:"adapter_id"`
	AdapterCodeHash                  string      `json:"adapter_code_hash"`
	AdapterSetPolicyHash             string      `json:"adapter_set_policy_hash"`
	SourceFinalityPolicyHash         string      `json:"source_finality_policy_hash"`
	DestinationFinalityPolicyHash    string      `json:"destination_finality_policy_hash"`
	SourceSignerSetHash              string      `json:"source_signer_set_hash"`
	DestinationSignerSetHash         string      `json:"destination_signer_set_hash"`
	AbsoluteCapUnits                 string      `json:"absolute_cap_units"`
	ChainCapUnits                    string      `json:"chain_cap_units"`
	AdapterCapUnits                  string      `json:"adapter_cap_units"`
	ActivatedAt                      uint64      `json:"activated_at"`
	HomeRegistrationTransaction      string      `json:"home_registration_tx_hash"`
	HomeRegistrationBlockNumber      json.Number `json:"home_registration_block_number"`
	SatelliteRegistrationTransaction string      `json:"satellite_registration_tx_hash"`
	SatelliteRegistrationBlockNumber json.Number `json:"satellite_registration_block_number"`
	HomeRegistryHash                 string      `json:"home_registry_hash"`
	SatelliteRegistryHash            string      `json:"satellite_registry_hash"`
}

type phase8ManifestRecovery struct {
	Action                    string   `json:"action"`
	AuthorizerSetVersion      uint32   `json:"authorizer_set_version"`
	Threshold                 uint32   `json:"threshold"`
	AuthorizerSetHash         string   `json:"authorizer_set_hash"`
	SortedAuthorizerAddresses []string `json:"sorted_authorizer_addresses"`
}

type phase8ManifestProvider struct {
	ID        string `json:"id"`
	URL       string `json:"url"`
	Authority string `json:"authority"`
}

func locatePhase8ReleaseEvidence() (string, error) {
	current, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for depth := 0; depth < 10; depth++ {
		candidate := filepath.Join(current, filepath.FromSlash(phase8ReleaseEvidencePath))
		if info, statErr := os.Stat(candidate); statErr == nil && !info.IsDir() {
			return candidate, nil
		}
		parent := filepath.Dir(current)
		if parent == current {
			break
		}
		current = parent
	}
	return "", fmt.Errorf("%s was not found", phase8ReleaseEvidencePath)
}

func loadPhase8ReleaseManifest(path string) (phase8ReleaseManifest, []store.RouteRegistration, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return phase8ReleaseManifest{}, nil, fmt.Errorf("read Phase 8 release evidence: %w", err)
	}
	var generic any
	genericDecoder := json.NewDecoder(bytes.NewReader(raw))
	genericDecoder.UseNumber()
	if err := genericDecoder.Decode(&generic); err != nil {
		return phase8ReleaseManifest{}, nil, fmt.Errorf("decode Phase 8 release evidence: %w", err)
	}
	if err := rejectPrivateMaterialKeys(generic); err != nil {
		return phase8ReleaseManifest{}, nil, err
	}
	var manifest phase8ReleaseManifest
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&manifest); err != nil {
		return phase8ReleaseManifest{}, nil, fmt.Errorf("decode Phase 8 release evidence: %w", err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		return phase8ReleaseManifest{}, nil, errors.New("Phase 8 release evidence has trailing JSON")
	}
	registrations, err := validatePhase8ReleaseManifest(manifest)
	if err != nil {
		return phase8ReleaseManifest{}, nil, err
	}
	return manifest, registrations, nil
}

func validatePhase8ReleaseManifest(
	manifest phase8ReleaseManifest,
) ([]store.RouteRegistration, error) {
	if manifest.SchemaVersion != 1 ||
		manifest.ArtifactType != "PHASE8_RELEASE_EVIDENCE" ||
		manifest.Environment != "local" || manifest.ContainsRealValue ||
		strings.TrimSpace(manifest.RunID) == "" {
		return nil, errors.New("release evidence is not the frozen local-only schema")
	}
	if manifest.ProofBoundary != "AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT" {
		return nil, errors.New("release evidence does not use authenticated signed-header MPT proofs")
	}
	if _, err := parseManifestHash(manifest.ProtocolID, "protocol_id"); err != nil {
		return nil, err
	}
	if _, err := time.Parse(time.RFC3339Nano, manifest.GeneratedAt); err != nil {
		return nil, errors.New("generated_at is not RFC3339")
	}
	if !isLowerHex(manifest.SourceCommit, 40) ||
		isEmptyJSONObject(manifest.Flow) {
		return nil, errors.New("release evidence source commit and flow are required")
	}
	if !bytes.Equal(bytes.TrimSpace(manifest.Durable), []byte("null")) {
		return nil, errors.New("intermediate release evidence durable must be exactly null")
	}
	if err := rejectNoncanonicalFlowNumbers(manifest.Flow); err != nil {
		return nil, err
	}
	deploymentFlowHash, err := computeDeploymentFlowSHA256(manifest)
	if err != nil || manifest.DeploymentFlowSHA256 != deploymentFlowHash {
		return nil, errors.New("deployment_flow_sha256 does not bind canonical deployment and flow")
	}
	domains := map[string]phase8ManifestDomain{
		"home":      manifest.Domains.Home,
		"satellite": manifest.Domains.Satellite,
	}
	if err := validateManifestDomain("home", manifest.Domains.Home, "31337"); err != nil {
		return nil, err
	}
	if err := validateManifestDomain(
		"satellite",
		manifest.Domains.Satellite,
		"31338",
	); err != nil {
		return nil, err
	}
	if manifest.Domains.Home.ConfigurationHash ==
		manifest.Domains.Satellite.ConfigurationHash ||
		manifest.Domains.Home.ObserverAuthorityHash ==
			manifest.Domains.Satellite.ObserverAuthorityHash ||
		manifest.Domains.Home.SignerSet.Hash ==
			manifest.Domains.Satellite.SignerSet.Hash {
		return nil, errors.New("home and satellite trust commitments must be distinct")
	}
	if err := validateManifestProviders(manifest.Providers); err != nil {
		return nil, err
	}
	if err := validateManifestExposure(manifest.ExposurePolicy); err != nil {
		return nil, err
	}
	adapterSetPolicyHash := computeManifestAdapterSetHash(manifest.Providers)
	if manifest.Recovery.Action != "TOMBSTONE_THEN_COMPENSATE" ||
		manifest.Recovery.AuthorizerSetVersion != 1 || manifest.Recovery.Threshold != 2 {
		return nil, errors.New("invalid recovery policy")
	}
	if _, err := validateSortedAddresses(
		manifest.Recovery.SortedAuthorizerAddresses,
	); err != nil {
		return nil, fmt.Errorf("recovery authorizers: %w", err)
	}
	recoveryAddresses, _ := validateSortedAddresses(
		manifest.Recovery.SortedAuthorizerAddresses,
	)
	expectedRecoveryHash := abiHash(
		"UNIFIED_XCHAIN_RECOVERY_AUTHORIZER_SET_V1",
		wordUint64(uint64(manifest.Recovery.AuthorizerSetVersion)),
		wordUint64(uint64(manifest.Recovery.Threshold)),
		wordAddress(recoveryAddresses[0]),
		wordAddress(recoveryAddresses[1]),
		wordAddress(recoveryAddresses[2]),
	)
	if !sameHex(manifest.Recovery.AuthorizerSetHash, expectedRecoveryHash[:]) {
		return nil, errors.New("recovery authorizer-set hash is not Solidity-canonical")
	}

	seen := make(map[string]struct{}, len(manifest.Routes))
	registrations := make([]store.RouteRegistration, 0, len(manifest.Routes))
	for _, route := range manifest.Routes {
		if _, exists := seen[route.Purpose]; exists {
			return nil, fmt.Errorf("duplicate route purpose %q", route.Purpose)
		}
		seen[route.Purpose] = struct{}{}
		registration, err := validateManifestRoute(route, domains, adapterSetPolicyHash)
		if err != nil {
			return nil, fmt.Errorf("route %s: %w", route.Purpose, err)
		}
		registrations = append(registrations, registration)
	}
	for _, purpose := range requiredRoutePurposes {
		if _, exists := seen[purpose]; !exists {
			return nil, fmt.Errorf("required route purpose %s is missing", purpose)
		}
	}
	if len(seen) != len(requiredRoutePurposes) {
		return nil, errors.New("release evidence contains an unknown route purpose")
	}
	for _, route := range manifest.Routes {
		if route.Purpose != "MINT" {
			continue
		}
		if route.Version != manifest.ExposurePolicy.PolicyVersion ||
			route.AbsoluteCapUnits != manifest.ExposurePolicy.RouteAbsoluteCapUnits ||
			route.ChainCapUnits != manifest.ExposurePolicy.ChainAbsoluteCapUnits ||
			route.AdapterCapUnits != manifest.ExposurePolicy.AdapterAbsoluteCapUnits ||
			route.ActivatedAt != manifest.ExposurePolicy.ActiveFrom {
			return nil, errors.New(
				"MINT route differs from the exact deployed exposure policy",
			)
		}
	}
	sort.Slice(registrations, func(left, right int) bool {
		return registrations[left].Route.RouteID < registrations[right].Route.RouteID
	})
	return registrations, nil
}

func validateManifestExposure(exposure phase8ManifestExposure) error {
	if exposure.PolicyVersion != 1 ||
		exposure.RoutePercentageCeilingBasisPoints != 500 ||
		exposure.AggregatePercentageCeilingBasisPoints != 1500 ||
		exposure.ActivationDelay != 0 ||
		exposure.ActiveFrom == 0 {
		return errors.New("release evidence exposure policy metadata is invalid")
	}
	for label, value := range map[string]string{
		"circulating supply reference": exposure.CirculatingSupplyReferenceUnits,
		"route absolute cap":           exposure.RouteAbsoluteCapUnits,
		"chain absolute cap":           exposure.ChainAbsoluteCapUnits,
		"adapter absolute cap":         exposure.AdapterAbsoluteCapUnits,
		"aggregate absolute cap":       exposure.AggregateAbsoluteCapUnits,
	} {
		number, ok := new(big.Int).SetString(value, 10)
		if !ok || number.Sign() <= 0 {
			return fmt.Errorf("%s is not a positive canonical integer", label)
		}
	}
	evidenceHash, err := parseManifestHash(
		exposure.CirculatingSupplyEvidenceHash,
		"circulating_supply_evidence_hash",
	)
	if err != nil {
		return err
	}
	expected := abiHash(
		"UNIFIED_BRIDGE_EXPOSURE_POLICY_V1",
		mustUintWord(json.Number(exposure.CirculatingSupplyReferenceUnits)),
		wordBytes32(evidenceHash),
		mustUintWord(json.Number(exposure.RouteAbsoluteCapUnits)),
		mustUintWord(json.Number(exposure.ChainAbsoluteCapUnits)),
		mustUintWord(json.Number(exposure.AdapterAbsoluteCapUnits)),
		mustUintWord(json.Number(exposure.AggregateAbsoluteCapUnits)),
		wordUint64(uint64(exposure.RoutePercentageCeilingBasisPoints)),
		wordUint64(uint64(exposure.AggregatePercentageCeilingBasisPoints)),
		wordUint64(exposure.ActivationDelay),
		wordUint64(exposure.ActiveFrom),
	)
	if !sameHex(exposure.PolicyHash, expected[:]) {
		return errors.New("exposure policy hash is not Solidity-canonical")
	}
	return nil
}

func validateManifestDomain(
	name string,
	domain phase8ManifestDomain,
	expectedChainID string,
) error {
	chainID, err := canonicalManifestNumber(domain.ChainID, false)
	if err != nil || chainID != expectedChainID {
		return fmt.Errorf("%s domain has the wrong chain ID", name)
	}
	if domain.ChainVersion != 1 {
		return fmt.Errorf("%s domain chain version must be one", name)
	}
	if err := validateLoopbackHTTP(domain.RPCURL); err != nil {
		return fmt.Errorf("%s domain RPC: %w", name, err)
	}
	for label, value := range map[string]string{
		"genesis_hash":            domain.GenesisHash,
		"configuration_hash":      domain.ConfigurationHash,
		"observer_authority_hash": domain.ObserverAuthorityHash,
	} {
		if _, err := parseManifestHash(value, name+"."+label); err != nil {
			return err
		}
	}
	publicKey, err := parseManifestFixedHex(
		domain.ObserverPublicKey,
		32,
		name+".observer_public_key_ed25519",
	)
	if err != nil {
		return err
	}
	authority, _ := parseManifestHash(
		domain.ObserverAuthorityHash,
		name+".observer_authority_hash",
	)
	if keccak(publicKey) != authority {
		return fmt.Errorf("%s observer authority does not bind its public key", name)
	}
	if domain.ObserverFixture == "" || domain.ConfirmationDepth == 0 {
		return fmt.Errorf("%s observer fixture and confirmation depth are required", name)
	}
	if _, err := canonicalManifestNumber(domain.ActivationBlock, true); err != nil {
		return fmt.Errorf("%s activation block: %w", name, err)
	}
	if _, err := canonicalManifestNumber(domain.ActivationTimestamp, false); err != nil {
		return fmt.Errorf("%s activation timestamp: %w", name, err)
	}
	if domain.RegistryStatus != "ACTIVE" {
		return fmt.Errorf("%s registry status must be ACTIVE", name)
	}
	if err := validateManifestSignerSet(name, domain); err != nil {
		return err
	}
	requiredContracts := requiredSatelliteContracts
	if name == "home" {
		requiredContracts = requiredHomeContracts
	}
	if len(domain.Contracts) != len(requiredContracts) {
		return fmt.Errorf("%s domain has a non-frozen contract set", name)
	}
	for required := range requiredContracts {
		if _, exists := domain.Contracts[required]; !exists {
			return fmt.Errorf("%s contract %s is missing", name, required)
		}
	}
	seenAddresses := make(map[[20]byte]string, len(domain.Contracts))
	for contractName, contract := range domain.Contracts {
		address, err := parseManifestAddress(
			contract.Address,
			name+".contracts."+contractName+".address",
		)
		if err != nil {
			return err
		}
		if prior, exists := seenAddresses[address]; exists {
			return fmt.Errorf("%s contracts %s and %s share an address", name, prior, contractName)
		}
		seenAddresses[address] = contractName
		if _, err := parseManifestHash(
			contract.RuntimeCodeHash,
			name+".contracts."+contractName+".runtime_code_hash",
		); err != nil {
			return err
		}
		if contract.ABIPath == "" || len(contract.ABISHA256) != 64 {
			return fmt.Errorf("%s contract %s has invalid ABI evidence", name, contractName)
		}
		if !isLowerHex(contract.ABISHA256, 64) {
			return fmt.Errorf("%s contract %s ABI hash is not lowercase SHA-256", name, contractName)
		}
		switch contract.DeploymentKind {
		case "CREATE_TRANSACTION":
			if contract.CreationEvent != nil {
				return fmt.Errorf("%s contract %s has an unexpected creation event", name, contractName)
			}
		case "INTERNAL_CREATE2":
			if name != "home" || contractName != "loan_account" ||
				contract.CreationEvent == nil {
				return fmt.Errorf("%s contract %s cannot use INTERNAL_CREATE2", name, contractName)
			}
			event := contract.CreationEvent
			if event.Signature != "CrossChainLoanCreated(bytes32,address,address,address,bytes32)" ||
				event.IndexedIDTopicPosition != 1 ||
				event.IndexedAddressTopicPosition != 2 {
				return errors.New("loan_account creation event is not canonical")
			}
			if _, err := parseManifestAddress(event.Emitter, "creation_event.emitter"); err != nil {
				return err
			}
			if _, err := parseManifestHash(event.Topic0, "creation_event.topic0"); err != nil {
				return err
			}
			if _, err := parseManifestHash(event.IndexedID, "creation_event.indexed_id"); err != nil {
				return err
			}
		default:
			return fmt.Errorf("%s contract %s has invalid deployment kind", name, contractName)
		}
		if _, err := parseManifestHash(
			contract.DeploymentTransaction,
			name+".contracts."+contractName+".deployment_tx_hash",
		); err != nil {
			return err
		}
		if block, err := canonicalManifestNumber(
			contract.DeploymentBlockNumber,
			false,
		); err != nil || block == "0" {
			return fmt.Errorf("%s contract %s has invalid deployment block", name, contractName)
		}
	}
	chainRegistry := strings.ToLower(domain.Contracts["chain_registry"].Address)
	if strings.ToLower(domain.RegistryBindings.RouteRegistryChainRegistry) != chainRegistry ||
		strings.ToLower(domain.RegistryBindings.FinalityVerifierChainRegistry) != chainRegistry {
		return fmt.Errorf("%s registry bindings do not pin its chain registry", name)
	}
	if len(domain.FinalityPolicies) != 2*len(requiredRoutePurposes) {
		return fmt.Errorf("%s domain must contain exactly fourteen finality policies", name)
	}
	seenPolicies := make(map[string]struct{}, len(domain.FinalityPolicies))
	for _, policy := range domain.FinalityPolicies {
		key := fmt.Sprintf("%s/%t", policy.RoutePurpose, policy.DestinationEvidence)
		if _, duplicate := seenPolicies[key]; duplicate {
			return fmt.Errorf("%s domain has duplicate finality policy %s", name, key)
		}
		seenPolicies[key] = struct{}{}
	}
	for _, purpose := range requiredRoutePurposes {
		for _, destination := range []bool{false, true} {
			key := fmt.Sprintf("%s/%t", purpose, destination)
			if _, exists := seenPolicies[key]; !exists {
				return fmt.Errorf("%s domain is missing finality policy %s", name, key)
			}
		}
	}
	return nil
}

func validateManifestSignerSet(name string, domain phase8ManifestDomain) error {
	set := domain.SignerSet
	if set.Version != 1 || set.Threshold != 2 || set.ValidFrom == 0 ||
		set.ValidUntil <= set.ValidFrom {
		return fmt.Errorf("%s signer set has invalid lifecycle", name)
	}
	addresses, err := validateSortedAddresses(set.SortedAddresses)
	if err != nil {
		return fmt.Errorf("%s signer set: %w", name, err)
	}
	authority, _ := parseManifestHash(
		domain.ObserverAuthorityHash,
		name+".observer_authority_hash",
	)
	expected := abiHash(
		"UNIFIED_SYNTHETIC_SIGNER_SET_V1",
		wordBytes32(authority),
		wordUint64(uint64(set.Version)),
		wordAddress(addresses[0]),
		wordAddress(addresses[1]),
		wordAddress(addresses[2]),
		wordUint64(uint64(set.Threshold)),
		wordUint64(set.ValidFrom),
		wordUint64(set.ValidUntil),
	)
	if !sameHex(set.Hash, expected[:]) {
		return fmt.Errorf("%s signer-set hash is not Solidity-canonical", name)
	}
	return nil
}

func validateManifestProviders(providers []phase8ManifestProvider) error {
	if len(providers) != 2 {
		return errors.New("exactly two transport-only providers are required")
	}
	seen := make(map[string]struct{}, len(providers))
	for _, provider := range providers {
		if (provider.ID != localProviderAID && provider.ID != localProviderBID) ||
			provider.Authority != "TRANSPORT_ONLY" {
			return errors.New("provider identity and TRANSPORT_ONLY authority are required")
		}
		if _, duplicate := seen[provider.ID]; duplicate {
			return errors.New("provider identities must be distinct")
		}
		seen[provider.ID] = struct{}{}
		if err := validateLoopbackHTTP(provider.URL); err != nil {
			return fmt.Errorf("provider %s: %w", provider.ID, err)
		}
	}
	return nil
}

func validateManifestRoute(
	route phase8ManifestRoute,
	domains map[string]phase8ManifestDomain,
	expectedAdapterSetPolicyHash [32]byte,
) (store.RouteRegistration, error) {
	if route.Version == 0 || route.ActivatedAt == 0 ||
		route.AllowedActionsBitmap == 0 {
		return store.RouteRegistration{}, errors.New("route version, action bitmap, and activation are required")
	}
	homeRegistrationBlock, err := canonicalManifestNumber(
		route.HomeRegistrationBlockNumber,
		false,
	)
	if err != nil {
		return store.RouteRegistration{}, fmt.Errorf("home registration block: %w", err)
	}
	satelliteRegistrationBlock, err := canonicalManifestNumber(
		route.SatelliteRegistrationBlockNumber,
		false,
	)
	if err != nil {
		return store.RouteRegistration{}, fmt.Errorf(
			"satellite registration block: %w",
			err,
		)
	}
	if _, err := parseManifestHash(route.HomeRegistrationTransaction, "home_registration_tx_hash"); err != nil {
		return store.RouteRegistration{}, err
	}
	if _, err := parseManifestHash(route.SatelliteRegistrationTransaction, "satellite_registration_tx_hash"); err != nil {
		return store.RouteRegistration{}, err
	}
	source, sourceOK := domains[route.SourceDomain]
	destination, destinationOK := domains[route.DestinationDomain]
	if !sourceOK || !destinationOK || route.SourceDomain == route.DestinationDomain {
		return store.RouteRegistration{}, errors.New("source and destination domains are invalid")
	}
	sourceChainID, err := canonicalManifestNumber(route.SourceChainID, false)
	if err != nil {
		return store.RouteRegistration{}, err
	}
	destinationChainID, err := canonicalManifestNumber(route.DestinationChainID, false)
	if err != nil {
		return store.RouteRegistration{}, err
	}
	expectedSourceChainID, _ := canonicalManifestNumber(source.ChainID, false)
	expectedDestinationChainID, _ := canonicalManifestNumber(destination.ChainID, false)
	if sourceChainID != expectedSourceChainID ||
		destinationChainID != expectedDestinationChainID ||
		route.SourceChainVersion != source.ChainVersion ||
		route.DestinationChainVersion != destination.ChainVersion {
		return store.RouteRegistration{}, errors.New("route chain identity is not manifest-pinned")
	}
	sourceCoordinator, err := parseManifestAddress(route.SourceCoordinator, "source_coordinator")
	if err != nil {
		return store.RouteRegistration{}, err
	}
	destinationCoordinator, err := parseManifestAddress(
		route.DestinationCoordinator,
		"destination_coordinator",
	)
	if err != nil {
		return store.RouteRegistration{}, err
	}
	if !sameHex(source.Contracts["coordinator"].Address, sourceCoordinator[:]) ||
		!sameHex(destination.Contracts["coordinator"].Address, destinationCoordinator[:]) {
		return store.RouteRegistration{}, errors.New("route coordinator is not deployed coordinator")
	}
	sourceComponent, sourceCodeHash, err := validateRouteComponent(
		source,
		route.SourceComponent,
		route.SourceComponentCodeHash,
		"source",
	)
	if err != nil {
		return store.RouteRegistration{}, err
	}
	destinationComponent, destinationCodeHash, err := validateRouteComponent(
		destination,
		route.DestinationComponent,
		route.DestinationComponentCodeHash,
		"destination",
	)
	if err != nil {
		return store.RouteRegistration{}, err
	}
	actionFamily, err := parseManifestHash(route.ActionFamily, "action_family")
	if err != nil {
		return store.RouteRegistration{}, err
	}
	adapterID, err := parseManifestHash(route.AdapterID, "adapter_id")
	if err != nil {
		return store.RouteRegistration{}, err
	}
	adapterCodeHash, err := parseManifestHash(route.AdapterCodeHash, "adapter_code_hash")
	if err != nil {
		return store.RouteRegistration{}, err
	}
	adapterSetPolicyHash, err := parseManifestHash(
		route.AdapterSetPolicyHash,
		"adapter_set_policy_hash",
	)
	if err != nil {
		return store.RouteRegistration{}, err
	}
	if adapterSetPolicyHash != expectedAdapterSetPolicyHash {
		return store.RouteRegistration{}, errors.New("adapter-set policy does not bind frozen providers")
	}
	sourceFinality, err := parseManifestHash(
		route.SourceFinalityPolicyHash,
		"source_finality_policy_hash",
	)
	if err != nil {
		return store.RouteRegistration{}, err
	}
	destinationFinality, err := parseManifestHash(
		route.DestinationFinalityPolicyHash,
		"destination_finality_policy_hash",
	)
	if err != nil {
		return store.RouteRegistration{}, err
	}
	sourceSignerSet, err := parseManifestHash(
		route.SourceSignerSetHash,
		"source_signer_set_hash",
	)
	if err != nil {
		return store.RouteRegistration{}, err
	}
	destinationSignerSet, err := parseManifestHash(
		route.DestinationSignerSetHash,
		"destination_signer_set_hash",
	)
	if err != nil {
		return store.RouteRegistration{}, err
	}
	if sourceSignerSet != mustManifestHash(source.SignerSet.Hash) ||
		destinationSignerSet != mustManifestHash(destination.SignerSet.Hash) {
		return store.RouteRegistration{}, errors.New("route signer sets do not match domains")
	}
	absoluteCap, err := wordUint256(route.AbsoluteCapUnits)
	if err != nil {
		return store.RouteRegistration{}, fmt.Errorf("absolute cap: %w", err)
	}
	chainCap, err := wordUint256(route.ChainCapUnits)
	if err != nil {
		return store.RouteRegistration{}, fmt.Errorf("chain cap: %w", err)
	}
	adapterCap, err := wordUint256(route.AdapterCapUnits)
	if err != nil {
		return store.RouteRegistration{}, fmt.Errorf("adapter cap: %w", err)
	}
	sourceChainWord, _ := wordUint256(sourceChainID)
	destinationChainWord, _ := wordUint256(destinationChainID)
	expectedRouteHash := abiHash(
		"UNIFIED_XCHAIN_ROUTE_V1",
		wordUint64(uint64(route.SourceChainVersion)),
		wordUint64(uint64(route.DestinationChainVersion)),
		sourceChainWord,
		wordAddress(sourceCoordinator),
		wordAddress(sourceComponent),
		wordBytes32(sourceCodeHash),
		destinationChainWord,
		wordAddress(destinationCoordinator),
		wordAddress(destinationComponent),
		wordBytes32(destinationCodeHash),
		wordBytes32(actionFamily),
		wordUint64(uint64(route.AllowedActionsBitmap)),
		wordBytes32(adapterID),
		wordBytes32(adapterCodeHash),
		wordBytes32(adapterSetPolicyHash),
		wordBytes32(sourceFinality),
		wordBytes32(destinationFinality),
		wordBytes32(sourceSignerSet),
		wordBytes32(destinationSignerSet),
		absoluteCap,
		chainCap,
		adapterCap,
		wordUint64(route.ActivatedAt),
	)
	for label, value := range map[string]string{
		"route_policy_hash":       route.RoutePolicyHash,
		"home_registry_hash":      route.HomeRegistryHash,
		"satellite_registry_hash": route.SatelliteRegistryHash,
	} {
		if !sameHex(value, expectedRouteHash[:]) {
			return store.RouteRegistration{}, fmt.Errorf("%s is not Solidity-canonical", label)
		}
	}
	if err := validateRouteFinalityPolicy(
		route,
		source,
		false,
		sourceFinality,
	); err != nil {
		return store.RouteRegistration{}, fmt.Errorf("source finality: %w", err)
	}
	if err := validateRouteFinalityPolicy(
		route,
		destination,
		true,
		destinationFinality,
	); err != nil {
		return store.RouteRegistration{}, fmt.Errorf("destination finality: %w", err)
	}
	sourceVerifier, _ := parseManifestAddress(
		source.Contracts["finality_verifier"].Address,
		"source finality verifier",
	)
	destinationVerifier, _ := parseManifestAddress(
		destination.Contracts["finality_verifier"].Address,
		"destination finality verifier",
	)
	sourceConfiguration := mustManifestHash(source.ConfigurationHash)
	destinationConfiguration := mustManifestHash(destination.ConfigurationHash)
	sourceObserver := mustManifestHash(source.ObserverAuthorityHash)
	destinationObserver := mustManifestHash(destination.ObserverAuthorityHash)
	if route.ActivatedAt > math.MaxInt64 {
		return store.RouteRegistration{}, errors.New("route activation exceeds Unix range")
	}
	activatedAt := time.Unix(int64(route.ActivatedAt), 0).UTC()
	routeActivationBlock := homeRegistrationBlock
	if route.SourceDomain == "satellite" {
		routeActivationBlock = satelliteRegistrationBlock
	}
	return store.RouteRegistration{
		Route: store.RouteVersion{
			RouteID:          "phase8-" + strings.ToLower(strings.ReplaceAll(route.Purpose, "_", "-")),
			Version:          route.Version,
			SourceChain:      sourceChainID,
			DestinationChain: destinationChainID,
			PolicyHash:       expectedRouteHash,
			ActivatedAt:      activatedAt,
		},
		SourceChain: store.ChainRegistration{
			ChainID:               sourceChainID,
			Version:               uint64(source.ChainVersion),
			Coordinator:           sourceCoordinator,
			FinalityVerifier:      sourceVerifier,
			ConfigurationHash:     sourceConfiguration,
			ObserverAuthorityHash: sourceObserver,
			ActivatedAtBlock:      source.ActivationBlock.String(),
		},
		DestinationChain: store.ChainRegistration{
			ChainID:               destinationChainID,
			Version:               uint64(destination.ChainVersion),
			Coordinator:           destinationCoordinator,
			FinalityVerifier:      destinationVerifier,
			ConfigurationHash:     destinationConfiguration,
			ObserverAuthorityHash: destinationObserver,
			ActivatedAtBlock:      destination.ActivationBlock.String(),
		},
		SourceComponent:               sourceComponent,
		DestinationComponent:          destinationComponent,
		ActionFamily:                  strings.ToLower(route.ActionFamily),
		AdapterSetPolicyHash:          adapterSetPolicyHash,
		SourceFinalityPolicyHash:      sourceFinality,
		DestinationFinalityPolicyHash: destinationFinality,
		SourceSignerSetHash:           sourceSignerSet,
		SourceSignerSetVersion:        uint64(source.SignerSet.Version),
		DestinationSignerSetHash:      destinationSignerSet,
		DestinationSignerSetVersion:   uint64(destination.SignerSet.Version),
		ActivatedAtBlock:              routeActivationBlock,
	}, nil
}

func validateRouteComponent(
	domain phase8ManifestDomain,
	addressValue string,
	codeHashValue string,
	label string,
) ([20]byte, [32]byte, error) {
	address, err := parseManifestAddress(addressValue, label+"_component")
	if err != nil {
		return [20]byte{}, [32]byte{}, err
	}
	codeHash, err := parseManifestHash(codeHashValue, label+"_component_code_hash")
	if err != nil {
		return [20]byte{}, [32]byte{}, err
	}
	for _, contract := range domain.Contracts {
		if sameHex(contract.Address, address[:]) {
			if !sameHex(contract.RuntimeCodeHash, codeHash[:]) {
				return [20]byte{}, [32]byte{}, fmt.Errorf(
					"%s component code hash does not match deployed contract",
					label,
				)
			}
			return address, codeHash, nil
		}
	}
	return [20]byte{}, [32]byte{}, fmt.Errorf(
		"%s component is not a deployed manifest contract",
		label,
	)
}

func validateRouteFinalityPolicy(
	route phase8ManifestRoute,
	domain phase8ManifestDomain,
	destinationEvidence bool,
	expectedHash [32]byte,
) error {
	var match *phase8ManifestFinalityPolicy
	for index := range domain.FinalityPolicies {
		policy := &domain.FinalityPolicies[index]
		if policy.RoutePurpose == route.Purpose &&
			policy.DestinationEvidence == destinationEvidence {
			if match != nil {
				return errors.New("duplicate policy")
			}
			match = policy
		}
	}
	if match == nil {
		return errors.New("policy is missing")
	}
	sourceChainID, err := canonicalManifestNumber(match.SourceChainID, false)
	if err != nil {
		return err
	}
	destinationChainID, err := canonicalManifestNumber(
		match.DestinationChainID,
		false,
	)
	if err != nil {
		return err
	}
	sourceChainWord, _ := wordUint256(sourceChainID)
	destinationChainWord, _ := wordUint256(destinationChainID)
	sourceCoordinator, err := parseManifestAddress(
		match.SourceCoordinator,
		"policy source coordinator",
	)
	if err != nil {
		return err
	}
	sourceComponent, err := parseManifestAddress(
		match.SourceComponent,
		"policy source component",
	)
	if err != nil {
		return err
	}
	destinationCoordinator, err := parseManifestAddress(
		match.DestinationCoordinator,
		"policy destination coordinator",
	)
	if err != nil {
		return err
	}
	destinationComponent, err := parseManifestAddress(
		match.DestinationComponent,
		"policy destination component",
	)
	if err != nil {
		return err
	}
	configurationHash, err := parseManifestHash(
		match.EvidenceChainConfigurationHash,
		"policy evidence chain configuration hash",
	)
	if err != nil {
		return err
	}
	actionFamily, err := parseManifestHash(match.ActionFamily, "policy action family")
	if err != nil {
		return err
	}
	observerAuthority, err := parseManifestHash(
		match.ObserverAuthorityHash,
		"policy observer authority",
	)
	if err != nil {
		return err
	}
	signerSetHash, err := parseManifestHash(
		match.SignerSetHash,
		"policy signer set",
	)
	if err != nil {
		return err
	}
	destinationWord := uint64(0)
	if match.DestinationEvidence {
		destinationWord = 1
	}
	actual := abiHash(
		"UNIFIED_SYNTHETIC_FINALITY_POLICY_V1",
		wordUint64(destinationWord),
		sourceChainWord,
		wordAddress(sourceCoordinator),
		wordAddress(sourceComponent),
		destinationChainWord,
		wordAddress(destinationCoordinator),
		wordAddress(destinationComponent),
		wordUint64(uint64(match.EvidenceChainVersion)),
		wordBytes32(configurationHash),
		wordBytes32(actionFamily),
		wordUint64(uint64(match.AllowedActionsBitmap)),
		wordUint64(match.RequiredDepth),
		wordBytes32(observerAuthority),
		wordBytes32(signerSetHash),
		wordUint64(uint64(match.SignerSetVersion)),
	)
	if actual != expectedHash || !sameHex(match.PolicyHash, actual[:]) {
		return errors.New("policy hash is not Solidity-canonical")
	}
	routeSourceCoordinator := mustAddress(route.SourceCoordinator)
	routeSourceComponent := mustAddress(route.SourceComponent)
	routeDestinationCoordinator := mustAddress(route.DestinationCoordinator)
	routeDestinationComponent := mustAddress(route.DestinationComponent)
	routeActionFamily := mustManifestHash(route.ActionFamily)
	domainConfiguration := mustManifestHash(domain.ConfigurationHash)
	domainObserver := mustManifestHash(domain.ObserverAuthorityHash)
	domainSignerSet := mustManifestHash(domain.SignerSet.Hash)
	if sourceChainID != route.SourceChainID.String() ||
		destinationChainID != route.DestinationChainID.String() ||
		!sameHex(match.SourceCoordinator, routeSourceCoordinator[:]) ||
		!sameHex(match.SourceComponent, routeSourceComponent[:]) ||
		!sameHex(match.DestinationCoordinator, routeDestinationCoordinator[:]) ||
		!sameHex(match.DestinationComponent, routeDestinationComponent[:]) ||
		!sameHex(match.ActionFamily, routeActionFamily[:]) ||
		match.AllowedActionsBitmap != route.AllowedActionsBitmap {
		return errors.New("policy fields do not match route")
	}
	if match.EvidenceChainVersion != domain.ChainVersion ||
		!sameHex(
			match.EvidenceChainConfigurationHash,
			domainConfiguration[:],
		) ||
		match.RequiredDepth != domain.ConfirmationDepth ||
		!sameHex(
			match.ObserverAuthorityHash,
			domainObserver[:],
		) ||
		!sameHex(match.SignerSetHash, domainSignerSet[:]) ||
		match.SignerSetVersion != domain.SignerSet.Version {
		return errors.New("policy evidence authority does not match domain")
	}
	return nil
}

func validateSortedAddresses(values []string) ([3][20]byte, error) {
	var result [3][20]byte
	if len(values) != len(result) {
		return result, errors.New("exactly three addresses are required")
	}
	for index, value := range values {
		address, err := parseManifestAddress(value, "signer address")
		if err != nil {
			return result, err
		}
		if index > 0 && bytes.Compare(result[index-1][:], address[:]) >= 0 {
			return result, errors.New("addresses are not strictly bytewise sorted")
		}
		result[index] = address
	}
	return result, nil
}

func parseManifestAddress(value, label string) ([20]byte, error) {
	raw, err := parseManifestFixedHex(value, 20, label)
	if err != nil {
		return [20]byte{}, err
	}
	var result [20]byte
	copy(result[:], raw)
	if result == ([20]byte{}) {
		return [20]byte{}, fmt.Errorf("%s must not be zero", label)
	}
	repeated := true
	for _, item := range result[1:] {
		if item != result[0] {
			repeated = false
			break
		}
	}
	if repeated {
		return [20]byte{}, fmt.Errorf("%s is a repeated-byte placeholder", label)
	}
	return result, nil
}

func parseManifestHash(value, label string) ([32]byte, error) {
	raw, err := parseManifestFixedHex(value, 32, label)
	if err != nil {
		return [32]byte{}, err
	}
	var result [32]byte
	copy(result[:], raw)
	if result == ([32]byte{}) {
		return [32]byte{}, fmt.Errorf("%s must not be zero", label)
	}
	return result, nil
}

func parseManifestFixedHex(value string, length int, label string) ([]byte, error) {
	if value != strings.ToLower(value) || !strings.HasPrefix(value, "0x") {
		return nil, fmt.Errorf("%s must be lowercase 0x-prefixed hex", label)
	}
	raw, err := hex.DecodeString(strings.TrimPrefix(value, "0x"))
	if err != nil || len(raw) != length {
		return nil, fmt.Errorf("%s must be exactly %d bytes", label, length)
	}
	return raw, nil
}

func canonicalManifestNumber(value json.Number, allowZero bool) (string, error) {
	text := value.String()
	if text == "" || strings.HasPrefix(text, "-") ||
		(len(text) > 1 && strings.HasPrefix(text, "0")) {
		return "", errors.New("number is not canonical unsigned decimal")
	}
	if _, ok := newBigInt(text); !ok || (!allowZero && text == "0") {
		return "", errors.New("number is outside uint256")
	}
	return text, nil
}

func newBigInt(value string) (string, bool) {
	word, err := wordNonnegativeUint256(value)
	if err != nil {
		return "", false
	}
	return hex.EncodeToString(word), true
}

func mustManifestHash(value string) [32]byte {
	result, err := parseManifestHash(value, "manifest hash")
	if err != nil {
		panic(err)
	}
	return result
}

func mustAddress(value string) [20]byte {
	result, err := parseManifestAddress(value, "manifest address")
	if err != nil {
		panic(err)
	}
	return result
}

func isEmptyJSONObject(raw json.RawMessage) bool {
	trimmed := bytes.TrimSpace(raw)
	return len(trimmed) == 0 || bytes.Equal(trimmed, []byte("null")) ||
		bytes.Equal(trimmed, []byte("{}"))
}

func rejectPrivateMaterialKeys(value any) error {
	switch typed := value.(type) {
	case map[string]any:
		for key, child := range typed {
			normalized := strings.ToLower(key)
			for _, marker := range []string{"private_key", "mnemonic", "seed", "secret"} {
				if strings.Contains(normalized, marker) {
					return errors.New("Phase 8 release evidence must not contain private signing material")
				}
			}
			if err := rejectPrivateMaterialKeys(child); err != nil {
				return err
			}
		}
	case []any:
		for _, child := range typed {
			if err := rejectPrivateMaterialKeys(child); err != nil {
				return err
			}
		}
	}
	return nil
}

func rejectNoncanonicalFlowNumbers(raw json.RawMessage) error {
	var value any
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	if err := decoder.Decode(&value); err != nil {
		return fmt.Errorf("decode canonical flow: %w", err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		return errors.New("flow has trailing JSON")
	}
	var walk func(any) error
	walk = func(node any) error {
		switch typed := node.(type) {
		case json.Number:
			if _, err := canonicalManifestNumber(typed, true); err != nil {
				return errors.New("flow contains a float or noncanonical number")
			}
		case map[string]any:
			for _, child := range typed {
				if err := walk(child); err != nil {
					return err
				}
			}
		case []any:
			for _, child := range typed {
				if err := walk(child); err != nil {
					return err
				}
			}
		}
		return nil
	}
	return walk(value)
}

func isLowerHex(value string, length int) bool {
	if len(value) != length || value != strings.ToLower(value) {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil
}

func computeManifestAdapterSetHash(providers []phase8ManifestProvider) [32]byte {
	canonical := append([]phase8ManifestProvider(nil), providers...)
	sort.Slice(canonical, func(left, right int) bool {
		if canonical[left].ID == canonical[right].ID {
			return canonical[left].Authority < canonical[right].Authority
		}
		return canonical[left].ID < canonical[right].ID
	})
	words := make([][]byte, 0, 1+2*len(canonical))
	words = append(words, wordUint64(uint64(len(canonical))))
	for _, provider := range canonical {
		providerID := keccak([]byte(provider.ID))
		authority := keccak([]byte(provider.Authority))
		words = append(words, wordBytes32(providerID), wordBytes32(authority))
	}
	return abiHash("UNIFIED_LOCAL_ADAPTER_SET_POLICY_V1", words...)
}

func manifestProviderURLs(manifest phase8ReleaseManifest) (string, string, error) {
	var first, second string
	for _, provider := range manifest.Providers {
		parsed, err := url.Parse(provider.URL)
		if err != nil {
			return "", "", err
		}
		normalized := parsed.String()
		switch provider.ID {
		case localProviderAID:
			first = normalized
		case localProviderBID:
			second = normalized
		}
	}
	if first == "" || second == "" {
		return "", "", errors.New("manifest provider identities do not match worker transports")
	}
	return first, second, nil
}

func computeDeploymentFlowSHA256(manifest phase8ReleaseManifest) (string, error) {
	preimage := map[string]any{
		"protocol_id":     manifest.ProtocolID,
		"proof_boundary":  manifest.ProofBoundary,
		"domains":         manifest.Domains,
		"routes":          manifest.Routes,
		"exposure_policy": manifest.ExposurePolicy,
		"recovery":        manifest.Recovery,
		"providers":       manifest.Providers,
	}
	var flow any
	decoder := json.NewDecoder(bytes.NewReader(manifest.Flow))
	decoder.UseNumber()
	if err := decoder.Decode(&flow); err != nil {
		return "", err
	}
	preimage["flow"] = flow
	intermediate, err := json.Marshal(preimage)
	if err != nil {
		return "", err
	}
	var canonical any
	decoder = json.NewDecoder(bytes.NewReader(intermediate))
	decoder.UseNumber()
	if err := decoder.Decode(&canonical); err != nil {
		return "", err
	}
	encoded, err := json.Marshal(canonical)
	if err != nil {
		return "", err
	}
	hash := sha256.Sum256(encoded)
	return hex.EncodeToString(hash[:]), nil
}
