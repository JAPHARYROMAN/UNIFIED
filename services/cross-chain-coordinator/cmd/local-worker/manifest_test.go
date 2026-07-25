package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

func TestPhase8ManifestValidatesSolidityAuthoritiesAndIsReadOnly(t *testing.T) {
	manifest := validPhase8Manifest(t)
	raw, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "phase8-release-evidence.json")
	if err := os.WriteFile(path, raw, 0o600); err != nil {
		t.Fatal(err)
	}
	before := sha256.Sum256(raw)
	loaded, registrations, err := loadPhase8ReleaseManifest(path)
	if err != nil {
		t.Fatal(err)
	}
	if loaded.RunID != manifest.RunID ||
		len(registrations) != len(requiredRoutePurposes) {
		t.Fatal("validated manifest did not produce all route registrations")
	}
	afterRaw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if after := sha256.Sum256(afterRaw); after != before {
		t.Fatal("manifest loader modified its authoritative input")
	}
	for _, registration := range registrations {
		if registration.Route.PolicyHash == ([32]byte{}) ||
			registration.SourceChain.Coordinator == repeated20(0x11) ||
			registration.DestinationChain.Coordinator == repeated20(0x21) {
			t.Fatal("manifest registration retained a placeholder authority")
		}
	}
}

func TestPhase8ManifestFailsClosedOnPrivateMaterialAndHashDrift(t *testing.T) {
	t.Run("private signing material", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "phase8-release-evidence.json")
		if err := os.WriteFile(
			path,
			[]byte(`{"private_key":"0x01"}`),
			0o600,
		); err != nil {
			t.Fatal(err)
		}
		if _, _, err := loadPhase8ReleaseManifest(path); err == nil {
			t.Fatal("private signing material was accepted")
		}
	})
	t.Run("route hash", func(t *testing.T) {
		manifest := validPhase8Manifest(t)
		manifest.Routes[0].RoutePolicyHash = manifestHash("wrong-route")
		if _, err := validatePhase8ReleaseManifest(manifest); err == nil {
			t.Fatal("non-Solidity route hash was accepted")
		}
	})
	t.Run("finality hash", func(t *testing.T) {
		manifest := validPhase8Manifest(t)
		manifest.Domains.Home.FinalityPolicies[0].PolicyHash =
			manifestHash("wrong-finality")
		if _, err := validatePhase8ReleaseManifest(manifest); err == nil {
			t.Fatal("non-Solidity finality hash was accepted")
		}
	})
	t.Run("circulating supply provenance", func(t *testing.T) {
		manifest := validPhase8Manifest(t)
		manifest.ExposurePolicy.CirculatingSupplyReferenceUnits = "1999"
		if _, err := validatePhase8ReleaseManifest(manifest); err == nil {
			t.Fatal("substituted circulating supply reference was accepted")
		}
	})
	t.Run("circulating supply evidence", func(t *testing.T) {
		manifest := validPhase8Manifest(t)
		manifest.ExposurePolicy.CirculatingSupplyEvidenceHash =
			manifestHash("substituted-supply-evidence")
		if _, err := validatePhase8ReleaseManifest(manifest); err == nil {
			t.Fatal("substituted circulating supply evidence was accepted")
		}
	})
	t.Run("signer order", func(t *testing.T) {
		manifest := validPhase8Manifest(t)
		addresses := manifest.Domains.Home.SignerSet.SortedAddresses
		addresses[0], addresses[1] = addresses[1], addresses[0]
		manifest.Domains.Home.SignerSet.SortedAddresses = addresses
		if _, err := validatePhase8ReleaseManifest(manifest); err == nil {
			t.Fatal("unsorted signer set was accepted")
		}
	})
	t.Run("placeholder address", func(t *testing.T) {
		manifest := validPhase8Manifest(t)
		manifest.Domains.Home.Contracts["coordinator"] =
			phase8ManifestContract{
				Address:               "0x1111111111111111111111111111111111111111",
				RuntimeCodeHash:       manifestHash("coordinator-runtime"),
				ABIPath:               "protocol/abi/phase8/coordinator.json",
				ABISHA256:             hex.EncodeToString(make([]byte, 32)),
				DeploymentTransaction: manifestHash("coordinator-deploy"),
				DeploymentBlockNumber: "1",
			}
		if _, err := validatePhase8ReleaseManifest(manifest); err == nil {
			t.Fatal("repeated-byte placeholder was accepted")
		}
	})
}

func TestPhase8OuterExecutionIdentityMustEqualRetainedProof(t *testing.T) {
	proof := phase8ImportProof{
		TransactionHash:  "0x" + strings.Repeat("ab", 32),
		BlockHash:        "0x" + strings.Repeat("cd", 32),
		BlockNumber:      json.Number("200"),
		TransactionIndex: json.Number("3"),
		LogIndex:         json.Number("7"),
	}
	validate := func(
		transactionHash string,
		blockHash string,
		blockNumber string,
		transactionIndex string,
		logIndex string,
	) error {
		return validatePhase8OuterProofIdentity(
			"destination",
			transactionHash,
			blockHash,
			json.Number(blockNumber),
			json.Number(transactionIndex),
			json.Number(logIndex),
			proof,
		)
	}
	if err := validate(
		proof.TransactionHash,
		proof.BlockHash,
		"200",
		"3",
		"7",
	); err != nil {
		t.Fatalf("exact receipt identity was rejected: %v", err)
	}
	for name, altered := range map[string][5]string{
		"transaction hash": {
			"0x" + strings.Repeat("aa", 32), proof.BlockHash, "200", "3", "7",
		},
		"block hash": {
			proof.TransactionHash, "0x" + strings.Repeat("cc", 32), "200", "3", "7",
		},
		"block number": {
			proof.TransactionHash, proof.BlockHash, "201", "3", "7",
		},
		"transaction index": {
			proof.TransactionHash, proof.BlockHash, "200", "4", "7",
		},
		"log index": {
			proof.TransactionHash, proof.BlockHash, "200", "3", "8",
		},
	} {
		t.Run(name, func(t *testing.T) {
			if err := validate(
				altered[0],
				altered[1],
				altered[2],
				altered[3],
				altered[4],
			); err == nil {
				t.Fatal("altered outer receipt identity was accepted")
			}
		})
	}
}

func validPhase8Manifest(t *testing.T) phase8ReleaseManifest {
	t.Helper()
	observerHome := append([]byte(nil), localObserverPublicKey...)
	observerSatellite := append([]byte(nil), localDestinationObserverPublicKey...)
	homeAuthority := keccak(observerHome)
	satelliteAuthority := keccak(observerSatellite)
	signers := localSortedFinalitySigners()
	signerStrings := []string{
		hexAddress(signers[0]),
		hexAddress(signers[1]),
		hexAddress(signers[2]),
	}
	const validFrom uint64 = 1_900_000_000
	const validUntil uint64 = validFrom + 86400
	homeSignerHash := abiHash(
		"UNIFIED_SYNTHETIC_SIGNER_SET_V1",
		wordBytes32(homeAuthority),
		wordUint64(1),
		wordAddress(signers[0]),
		wordAddress(signers[1]),
		wordAddress(signers[2]),
		wordUint64(2),
		wordUint64(validFrom),
		wordUint64(validUntil),
	)
	satelliteSignerHash := abiHash(
		"UNIFIED_SYNTHETIC_SIGNER_SET_V1",
		wordBytes32(satelliteAuthority),
		wordUint64(1),
		wordAddress(signers[0]),
		wordAddress(signers[1]),
		wordAddress(signers[2]),
		wordUint64(2),
		wordUint64(validFrom),
		wordUint64(validUntil),
	)
	homeContracts := validManifestContracts("home")
	satelliteContracts := validManifestContracts("satellite")
	home := phase8ManifestDomain{
		ChainID:               "31337",
		ChainVersion:          1,
		RPCURL:                "http://127.0.0.1:18545",
		GenesisHash:           manifestHash("home-genesis"),
		ConfigurationHash:     manifestHash("home-configuration"),
		ActivationBlock:       "1",
		ActivationTimestamp:   "1900000000",
		RegistryStatus:        "ACTIVE",
		ObserverFixture:       "LOCAL_HOME_OBSERVER_ONLY",
		ObserverPublicKey:     "0x" + hex.EncodeToString(observerHome),
		ObserverAuthorityHash: hexHash(homeAuthority),
		ConfirmationDepth:     2,
		SignerSet: phase8ManifestSignerSet{
			Version:         1,
			Hash:            hexHash(homeSignerHash),
			Threshold:       2,
			ValidFrom:       validFrom,
			ValidUntil:      validUntil,
			SortedAddresses: append([]string(nil), signerStrings...),
		},
		Contracts: homeContracts,
		RegistryBindings: phase8ManifestRegistryBindings{
			RouteRegistryChainRegistry:    homeContracts["chain_registry"].Address,
			FinalityVerifierChainRegistry: homeContracts["chain_registry"].Address,
		},
	}
	satellite := phase8ManifestDomain{
		ChainID:               "31338",
		ChainVersion:          1,
		RPCURL:                "http://127.0.0.1:28545",
		GenesisHash:           manifestHash("satellite-genesis"),
		ConfigurationHash:     manifestHash("satellite-configuration"),
		ActivationBlock:       "1",
		ActivationTimestamp:   "1900000000",
		RegistryStatus:        "ACTIVE",
		ObserverFixture:       "LOCAL_SATELLITE_OBSERVER_ONLY",
		ObserverPublicKey:     "0x" + hex.EncodeToString(observerSatellite),
		ObserverAuthorityHash: hexHash(satelliteAuthority),
		ConfirmationDepth:     2,
		SignerSet: phase8ManifestSignerSet{
			Version:         1,
			Hash:            hexHash(satelliteSignerHash),
			Threshold:       2,
			ValidFrom:       validFrom,
			ValidUntil:      validUntil,
			SortedAddresses: append([]string(nil), signerStrings...),
		},
		Contracts: satelliteContracts,
		RegistryBindings: phase8ManifestRegistryBindings{
			RouteRegistryChainRegistry:    satelliteContracts["chain_registry"].Address,
			FinalityVerifierChainRegistry: satelliteContracts["chain_registry"].Address,
		},
	}
	manifest := phase8ReleaseManifest{
		SchemaVersion:     1,
		ArtifactType:      "PHASE8_RELEASE_EVIDENCE",
		Environment:       "local",
		ContainsRealValue: false,
		RunID:             "phase8-test-run",
		ProtocolID:        manifestHash("protocol"),
		ProofBoundary:     "AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT",
		GeneratedAt:       "2030-03-17T17:46:40Z",
		SourceCommit:      "0123456789abcdef0123456789abcdef01234567",
		Domains: phase8ManifestDomains{
			Home:      home,
			Satellite: satellite,
		},
		Recovery: phase8ManifestRecovery{
			Action:                    "TOMBSTONE_THEN_COMPENSATE",
			AuthorizerSetVersion:      1,
			Threshold:                 2,
			SortedAuthorizerAddresses: append([]string(nil), signerStrings...),
		},
		Providers: []phase8ManifestProvider{
			{
				ID:        localProviderAID,
				URL:       "http://127.0.0.1:58081",
				Authority: "TRANSPORT_ONLY",
			},
			{
				ID:        localProviderBID,
				URL:       "http://127.0.0.1:58082",
				Authority: "TRANSPORT_ONLY",
			},
		},
		Flow:    json.RawMessage(`{"messages":[{"sequence":1}]}`),
		Durable: json.RawMessage(`null`),
	}
	manifest.Recovery.AuthorizerSetHash = hexHash(abiHash(
		"UNIFIED_XCHAIN_RECOVERY_AUTHORIZER_SET_V1",
		wordUint64(1),
		wordUint64(2),
		wordAddress(signers[0]),
		wordAddress(signers[1]),
		wordAddress(signers[2]),
	))
	for index, purpose := range requiredRoutePurposes {
		route := validManifestRoute(
			purpose,
			uint32(1)<<uint32(index+1),
			home,
			satellite,
		)
		manifest.Routes = append(manifest.Routes, route)
		sourcePolicy := validManifestPolicy(route, home, false)
		destinationPolicy := validManifestPolicy(route, satellite, true)
		manifest.Domains.Home.FinalityPolicies = append(
			manifest.Domains.Home.FinalityPolicies,
			sourcePolicy,
			destinationPolicy,
		)
		manifest.Domains.Satellite.FinalityPolicies = append(
			manifest.Domains.Satellite.FinalityPolicies,
			sourcePolicy,
			destinationPolicy,
		)
	}
	mintRoute := manifest.Routes[0]
	manifest.ExposurePolicy = phase8ManifestExposure{
		PolicyVersion:                         mintRoute.Version,
		CirculatingSupplyReferenceUnits:       "2000",
		CirculatingSupplyEvidenceHash:         manifestHash("circulating-supply"),
		RouteAbsoluteCapUnits:                 mintRoute.AbsoluteCapUnits,
		ChainAbsoluteCapUnits:                 mintRoute.ChainCapUnits,
		AdapterAbsoluteCapUnits:               mintRoute.AdapterCapUnits,
		AggregateAbsoluteCapUnits:             mintRoute.AbsoluteCapUnits,
		RoutePercentageCeilingBasisPoints:     500,
		AggregatePercentageCeilingBasisPoints: 1500,
		ActivationDelay:                       0,
		ActiveFrom:                            mintRoute.ActivatedAt,
	}
	exposureEvidence := mustManifestHash(
		manifest.ExposurePolicy.CirculatingSupplyEvidenceHash,
	)
	manifest.ExposurePolicy.PolicyHash = hexHash(abiHash(
		"UNIFIED_BRIDGE_EXPOSURE_POLICY_V1",
		mustUintWord(json.Number(
			manifest.ExposurePolicy.CirculatingSupplyReferenceUnits,
		)),
		wordBytes32(exposureEvidence),
		mustUintWord(json.Number(manifest.ExposurePolicy.RouteAbsoluteCapUnits)),
		mustUintWord(json.Number(manifest.ExposurePolicy.ChainAbsoluteCapUnits)),
		mustUintWord(json.Number(manifest.ExposurePolicy.AdapterAbsoluteCapUnits)),
		mustUintWord(json.Number(manifest.ExposurePolicy.AggregateAbsoluteCapUnits)),
		wordUint64(uint64(
			manifest.ExposurePolicy.RoutePercentageCeilingBasisPoints,
		)),
		wordUint64(uint64(
			manifest.ExposurePolicy.AggregatePercentageCeilingBasisPoints,
		)),
		wordUint64(manifest.ExposurePolicy.ActivationDelay),
		wordUint64(manifest.ExposurePolicy.ActiveFrom),
	))
	deploymentFlowHash, err := computeDeploymentFlowSHA256(manifest)
	if err != nil {
		t.Fatal(err)
	}
	manifest.DeploymentFlowSHA256 = deploymentFlowHash
	return manifest
}

func validManifestContracts(domain string) map[string]phase8ManifestContract {
	result := make(map[string]phase8ManifestContract)
	names := make([]string, 0)
	required := requiredSatelliteContracts
	if domain == "home" {
		required = requiredHomeContracts
	}
	for name := range required {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		digest := keccak([]byte(domain + ":" + name + ":address"))
		abiDigest := keccak([]byte(domain + ":" + name + ":abi"))
		var address [20]byte
		copy(address[:], digest[12:])
		result[name] = phase8ManifestContract{
			Address:               hexAddress(address),
			RuntimeCodeHash:       manifestHash(domain + ":" + name + ":runtime"),
			ABIPath:               "protocol/abi/phase8/" + name + ".json",
			ABISHA256:             hex.EncodeToString(abiDigest[:]),
			DeploymentKind:        "CREATE_TRANSACTION",
			DeploymentTransaction: manifestHash(domain + ":" + name + ":deployment"),
			DeploymentBlockNumber: "1",
		}
	}
	if domain == "home" {
		loanAccount := result["loan_account"]
		loanAccount.DeploymentKind = "INTERNAL_CREATE2"
		topic := keccak([]byte("CrossChainLoanCreated(bytes32,address,address,address,bytes32)"))
		loanAccount.CreationEvent = &phase8ManifestCreationEvent{
			Emitter:                     result["loan_factory"].Address,
			Signature:                   "CrossChainLoanCreated(bytes32,address,address,address,bytes32)",
			Topic0:                      hexHash(topic),
			IndexedID:                   manifestHash("loan-id"),
			IndexedIDTopicPosition:      1,
			IndexedAddressTopicPosition: 2,
		}
		result["loan_account"] = loanAccount
	}
	return result
}

func validManifestRoute(
	purpose string,
	bitmap uint32,
	home phase8ManifestDomain,
	satellite phase8ManifestDomain,
) phase8ManifestRoute {
	homeComponent := home.Contracts["bridge_hub"]
	satelliteComponent := satellite.Contracts["wrapped_uft"]
	route := phase8ManifestRoute{
		Purpose:                      purpose,
		Version:                      1,
		SourceDomain:                 "home",
		DestinationDomain:            "satellite",
		SourceChainVersion:           1,
		DestinationChainVersion:      1,
		SourceChainID:                "31337",
		SourceCoordinator:            home.Contracts["coordinator"].Address,
		SourceComponent:              homeComponent.Address,
		SourceComponentCodeHash:      homeComponent.RuntimeCodeHash,
		DestinationChainID:           "31338",
		DestinationCoordinator:       satellite.Contracts["coordinator"].Address,
		DestinationComponent:         satelliteComponent.Address,
		DestinationComponentCodeHash: satelliteComponent.RuntimeCodeHash,
		ActionFamily:                 manifestHash("action:" + purpose),
		AllowedActionsBitmap:         bitmap,
		AdapterID:                    manifestHash("adapter"),
		AdapterCodeHash:              manifestHash("adapter-code"),
		AdapterSetPolicyHash: hexHash(computeManifestAdapterSetHash([]phase8ManifestProvider{
			{ID: localProviderAID, Authority: "TRANSPORT_ONLY"},
			{ID: localProviderBID, Authority: "TRANSPORT_ONLY"},
		})),
		SourceSignerSetHash:              home.SignerSet.Hash,
		DestinationSignerSetHash:         satellite.SignerSet.Hash,
		AbsoluteCapUnits:                 "100",
		ChainCapUnits:                    "100",
		AdapterCapUnits:                  "100",
		ActivatedAt:                      1_900_000_000,
		HomeRegistrationTransaction:      manifestHash("home-route-registration:" + purpose),
		HomeRegistrationBlockNumber:      "11",
		SatelliteRegistrationTransaction: manifestHash("satellite-route-registration:" + purpose),
		SatelliteRegistrationBlockNumber: "12",
	}
	sourcePolicy := validManifestPolicy(route, home, false)
	destinationPolicy := validManifestPolicy(route, satellite, true)
	route.SourceFinalityPolicyHash = sourcePolicy.PolicyHash
	route.DestinationFinalityPolicyHash = destinationPolicy.PolicyHash
	sourceChain, _ := wordUint256("31337")
	destinationChain, _ := wordUint256("31338")
	sourceCoordinator := mustAddress(route.SourceCoordinator)
	sourceComponent := mustAddress(route.SourceComponent)
	sourceCodeHash := mustManifestHash(route.SourceComponentCodeHash)
	destinationCoordinator := mustAddress(route.DestinationCoordinator)
	destinationComponent := mustAddress(route.DestinationComponent)
	destinationCodeHash := mustManifestHash(route.DestinationComponentCodeHash)
	actionFamily := mustManifestHash(route.ActionFamily)
	adapterID := mustManifestHash(route.AdapterID)
	adapterCodeHash := mustManifestHash(route.AdapterCodeHash)
	adapterSet := mustManifestHash(route.AdapterSetPolicyHash)
	sourceFinality := mustManifestHash(route.SourceFinalityPolicyHash)
	destinationFinality := mustManifestHash(route.DestinationFinalityPolicyHash)
	sourceSigner := mustManifestHash(route.SourceSignerSetHash)
	destinationSigner := mustManifestHash(route.DestinationSignerSetHash)
	absoluteCap, _ := wordUint256(route.AbsoluteCapUnits)
	chainCap, _ := wordUint256(route.ChainCapUnits)
	adapterCap, _ := wordUint256(route.AdapterCapUnits)
	hash := abiHash(
		"UNIFIED_XCHAIN_ROUTE_V1",
		wordUint64(1),
		wordUint64(1),
		sourceChain,
		wordAddress(sourceCoordinator),
		wordAddress(sourceComponent),
		wordBytes32(sourceCodeHash),
		destinationChain,
		wordAddress(destinationCoordinator),
		wordAddress(destinationComponent),
		wordBytes32(destinationCodeHash),
		wordBytes32(actionFamily),
		wordUint64(uint64(bitmap)),
		wordBytes32(adapterID),
		wordBytes32(adapterCodeHash),
		wordBytes32(adapterSet),
		wordBytes32(sourceFinality),
		wordBytes32(destinationFinality),
		wordBytes32(sourceSigner),
		wordBytes32(destinationSigner),
		absoluteCap,
		chainCap,
		adapterCap,
		wordUint64(route.ActivatedAt),
	)
	route.RoutePolicyHash = hexHash(hash)
	route.HomeRegistryHash = hexHash(hash)
	route.SatelliteRegistryHash = hexHash(hash)
	return route
}

func validManifestPolicy(
	route phase8ManifestRoute,
	evidenceDomain phase8ManifestDomain,
	destinationEvidence bool,
) phase8ManifestFinalityPolicy {
	policy := phase8ManifestFinalityPolicy{
		RoutePurpose:                   route.Purpose,
		DestinationEvidence:            destinationEvidence,
		SourceChainID:                  route.SourceChainID,
		SourceCoordinator:              route.SourceCoordinator,
		SourceComponent:                route.SourceComponent,
		DestinationChainID:             route.DestinationChainID,
		DestinationCoordinator:         route.DestinationCoordinator,
		DestinationComponent:           route.DestinationComponent,
		EvidenceChainVersion:           evidenceDomain.ChainVersion,
		EvidenceChainConfigurationHash: evidenceDomain.ConfigurationHash,
		ActionFamily:                   route.ActionFamily,
		AllowedActionsBitmap:           route.AllowedActionsBitmap,
		RequiredDepth:                  evidenceDomain.ConfirmationDepth,
		ObserverAuthorityHash:          evidenceDomain.ObserverAuthorityHash,
		SignerSetHash:                  evidenceDomain.SignerSet.Hash,
		SignerSetVersion:               evidenceDomain.SignerSet.Version,
	}
	sourceChain, _ := wordUint256(policy.SourceChainID.String())
	destinationChain, _ := wordUint256(policy.DestinationChainID.String())
	sourceCoordinator := mustAddress(policy.SourceCoordinator)
	sourceComponent := mustAddress(policy.SourceComponent)
	destinationCoordinator := mustAddress(policy.DestinationCoordinator)
	destinationComponent := mustAddress(policy.DestinationComponent)
	configuration := mustManifestHash(policy.EvidenceChainConfigurationHash)
	actionFamily := mustManifestHash(policy.ActionFamily)
	observer := mustManifestHash(policy.ObserverAuthorityHash)
	signerSet := mustManifestHash(policy.SignerSetHash)
	destinationWord := uint64(0)
	if destinationEvidence {
		destinationWord = 1
	}
	hash := abiHash(
		"UNIFIED_SYNTHETIC_FINALITY_POLICY_V1",
		wordUint64(destinationWord),
		sourceChain,
		wordAddress(sourceCoordinator),
		wordAddress(sourceComponent),
		destinationChain,
		wordAddress(destinationCoordinator),
		wordAddress(destinationComponent),
		wordUint64(uint64(policy.EvidenceChainVersion)),
		wordBytes32(configuration),
		wordBytes32(actionFamily),
		wordUint64(uint64(policy.AllowedActionsBitmap)),
		wordUint64(policy.RequiredDepth),
		wordBytes32(observer),
		wordBytes32(signerSet),
		wordUint64(uint64(policy.SignerSetVersion)),
	)
	policy.PolicyHash = hexHash(hash)
	return policy
}

func manifestHash(label string) string {
	return hexHash(keccak([]byte(label)))
}

func hexAddress(value [20]byte) string {
	return "0x" + hex.EncodeToString(value[:])
}
