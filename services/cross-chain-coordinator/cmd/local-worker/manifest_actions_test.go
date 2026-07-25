package main

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"testing"
)

func TestValidatePhase8MessageOrderRequiresCanonicalLowercasePurposes(t *testing.T) {
	messages := make([]phase8ImportMessage, len(phase8ExpectedActions))
	for index := range messages {
		messages[index].Envelope.ActionType = phase8ExpectedActions[index]
		messages[index].RoutePurpose = phase8ExpectedPurposes[index]
	}
	if err := validatePhase8MessageOrder(messages); err != nil {
		t.Fatalf("canonical eight-message order was rejected: %v", err)
	}
	messages[0].RoutePurpose = "MINT"
	if err := validatePhase8MessageOrder(messages); err == nil {
		t.Fatal("uppercase message purpose was accepted at the lowercase flow boundary")
	}
	messages[0].RoutePurpose = "mint"
	messages[1].Envelope.ActionType = 2
	if err := validatePhase8MessageOrder(messages); err == nil {
		t.Fatal("changed action order was accepted")
	}
}

func TestPhase8RouteForMessageMapsExactLowercasePurposeToRegistryVocabulary(
	t *testing.T,
) {
	policyHash := "0x" + strings.Repeat("11", 32)
	cases := []struct {
		messagePurpose  string
		registryPurpose string
	}{
		{"mint", "MINT"},
		{"report", "REPORT"},
		{"repayment", "REPAYMENT"},
		{"alternate_repayment", "ALTERNATE_REPAYMENT"},
		{"bridge_exit", "BRIDGE_EXIT"},
		{"disbursement", "DISBURSEMENT"},
		{"collateral_release", "COLLATERAL_RELEASE"},
	}
	for _, item := range cases {
		t.Run(item.messagePurpose, func(t *testing.T) {
			manifest := phase8ReleaseManifest{Routes: []phase8ManifestRoute{{
				Purpose:         item.registryPurpose,
				RoutePolicyHash: policyHash,
			}}}
			message := phase8ImportMessage{
				RoutePurpose: item.messagePurpose,
				Envelope: phase8ImportEnvelope{
					RoutePolicyHash: policyHash,
				},
			}
			route, err := phase8RouteForMessage(message, manifest)
			if err != nil {
				t.Fatalf("exact lowercase message purpose was rejected: %v", err)
			}
			if route.Purpose != item.registryPurpose {
				t.Fatalf("message purpose mapped to unexpected route: %#v", route)
			}
		})
	}

	manifest := phase8ReleaseManifest{Routes: []phase8ManifestRoute{{
		Purpose:         "MINT",
		RoutePolicyHash: policyHash,
	}}}
	message := phase8ImportMessage{
		Envelope: phase8ImportEnvelope{RoutePolicyHash: policyHash},
	}
	message.RoutePurpose = "MINT"
	if _, err := phase8RouteForMessage(message, manifest); err == nil {
		t.Fatal("uppercase message purpose was accepted at the lowercase boundary")
	}
	message.RoutePurpose = "unknown"
	if _, err := phase8RouteForMessage(message, manifest); err == nil {
		t.Fatal("unknown message purpose was accepted")
	}
}

func TestDecodePhase8ActionPayloadRejectsTrailingAndNoncanonicalAddress(t *testing.T) {
	payload := actionPayloadHex(
		strings.Repeat("11", 32),
		strings.Repeat("22", 32),
		strings.Repeat("00", 12)+strings.Repeat("33", 20),
		strings.Repeat("00", 12)+strings.Repeat("44", 20),
		strings.Repeat("00", 12)+strings.Repeat("55", 20),
		strings.Repeat("00", 12)+strings.Repeat("66", 20),
		uintWordHex(100),
		strings.Repeat("77", 32),
	)
	decoded, err := decodePhase8ActionPayload(5, payload)
	if err != nil || decoded.Words[6] != "100" {
		t.Fatalf("exact payload rejected: %#v %v", decoded, err)
	}
	if _, err := decodePhase8ActionPayload(5, payload+"00"); err == nil {
		t.Fatal("trailing payload byte was accepted")
	}
	raw, _ := hex.DecodeString(strings.TrimPrefix(payload, "0x"))
	raw[64] = 1
	if _, err := decodePhase8ActionPayload(
		5,
		"0x"+hex.EncodeToString(raw),
	); err == nil {
		t.Fatal("noncanonical ABI address padding was accepted")
	}
}

func TestDecodePhase8CancellationPayloadsRequireExactStaticABI(t *testing.T) {
	context := cancellationProjectionContext()
	for _, action := range []uint32{12, 14} {
		message := cancellationProjectionMessage(
			action,
			context,
			"0x"+strings.Repeat("00", 32),
			"0x"+strings.Repeat("00", 32),
		)
		decoded, err := decodePhase8ActionPayload(action, message.Payload)
		if err != nil || len(decoded.Words) != 11 {
			t.Fatalf("action %d exact payload rejected: %#v %v", action, decoded, err)
		}
		if _, err := decodePhase8ActionPayload(
			action,
			message.Payload+"00",
		); err == nil {
			t.Fatalf("action %d accepted trailing payload data", action)
		}
	}
}

func TestValidatePhase8CancellationOrderRequiresExactBoundPair(t *testing.T) {
	context := cancellationProjectionContext()
	request := cancellationProjectionMessage(
		12,
		context,
		"0x"+strings.Repeat("00", 32),
		"0x"+strings.Repeat("00", 32),
	)
	completion := cancellationProjectionMessage(
		14,
		context,
		"0x"+strings.Repeat("00", 32),
		"0x"+strings.Repeat("00", 32),
	)
	request.Sequence = 1
	completion.Sequence = 2
	mintMessageID := "0x" + strings.Repeat("ab", 32)
	request.Envelope.CausationMessageID = mintMessageID
	completion.Envelope.CausationMessageID = request.Envelope.MessageID
	if err := validatePhase8CancellationOrder(
		[]phase8ImportMessage{request, completion},
		mintMessageID,
	); err != nil {
		t.Fatalf("exact cancellation pair rejected: %v", err)
	}
	for name, mutate := range map[string]func(*phase8ImportMessage){
		"generic action 14": func(value *phase8ImportMessage) {
			value.Envelope.ActionType = 13
		},
		"wrong route": func(value *phase8ImportMessage) {
			value.RoutePurpose = "bridge_exit"
		},
		"wrong causation": func(value *phase8ImportMessage) {
			value.Envelope.CausationMessageID = "0x" + strings.Repeat("ff", 32)
		},
		"changed cancellation": func(value *phase8ImportMessage) {
			raw, _ := hex.DecodeString(strings.TrimPrefix(value.Payload, "0x"))
			raw[31] ^= 1
			value.Payload = "0x" + hex.EncodeToString(raw)
		},
	} {
		t.Run(name, func(t *testing.T) {
			changed := completion
			mutate(&changed)
			if err := validatePhase8CancellationOrder(
				[]phase8ImportMessage{request, changed},
				mintMessageID,
			); err == nil {
				t.Fatal("mutated cancellation pair was accepted")
			}
		})
	}
	malformed := request
	malformed.Envelope.MessageID = "not-hex"
	if err := validatePhase8CancellationOrder(
		[]phase8ImportMessage{malformed, completion},
		mintMessageID,
	); err == nil {
		t.Fatal("malformed request message ID was accepted")
	}
	wrongRequestCause := request
	wrongRequestCause.Envelope.CausationMessageID =
		"0x" + strings.Repeat("cd", 32)
	if err := validatePhase8CancellationOrder(
		[]phase8ImportMessage{wrongRequestCause, completion},
		mintMessageID,
	); err == nil {
		t.Fatal("zero cancellation accepted a causation other than the mint")
	}

	nonzeroDisbursement := "0x" + strings.Repeat("ef", 32)
	nonzeroRequest := cancellationProjectionMessage(
		12,
		context,
		nonzeroDisbursement,
		"0x"+strings.Repeat("12", 32),
	)
	nonzeroCompletion := cancellationProjectionMessage(
		14,
		context,
		nonzeroDisbursement,
		"0x"+strings.Repeat("12", 32),
	)
	nonzeroRequest.Sequence = 1
	nonzeroCompletion.Sequence = 2
	nonzeroRequest.Envelope.CausationMessageID = nonzeroDisbursement
	nonzeroCompletion.Envelope.CausationMessageID =
		nonzeroRequest.Envelope.MessageID
	if err := validatePhase8CancellationOrder(
		[]phase8ImportMessage{nonzeroRequest, nonzeroCompletion},
		"",
	); err != nil {
		t.Fatalf("nonzero exact cancellation pair rejected: %v", err)
	}
	nonzeroRequest.Envelope.CausationMessageID =
		"0x" + strings.Repeat("cd", 32)
	if err := validatePhase8CancellationOrder(
		[]phase8ImportMessage{nonzeroRequest, nonzeroCompletion},
		"",
	); err == nil {
		t.Fatal("nonzero cancellation accepted non-disbursement causation")
	}
}

func TestProjectPhase8CancellationBindsRoutesIdentitiesAndEvidence(t *testing.T) {
	context := cancellationProjectionContext()
	sourceRequest := "0x" + strings.Repeat("41", 20)
	destinationRequest := "0x" + strings.Repeat("42", 20)
	sourceCompletion := "0x" + strings.Repeat("43", 20)
	destinationCompletion := "0x" + strings.Repeat("44", 20)
	disbursementRouteHash := "0x" + strings.Repeat("51", 32)
	reportRouteHash := "0x" + strings.Repeat("52", 32)
	disbursementFamily := "0x" + strings.Repeat("61", 32)
	reportFamily := "0x" + strings.Repeat("62", 32)
	manifest := phase8ReleaseManifest{Routes: []phase8ManifestRoute{
		{
			Purpose:              "DISBURSEMENT",
			RoutePolicyHash:      disbursementRouteHash,
			ActionFamily:         disbursementFamily,
			SourceComponent:      sourceRequest,
			DestinationComponent: destinationRequest,
		},
		{
			Purpose:              "REPORT",
			RoutePolicyHash:      reportRouteHash,
			ActionFamily:         reportFamily,
			SourceComponent:      sourceCompletion,
			DestinationComponent: destinationCompletion,
		},
	}}
	for _, nonzero := range []bool{false, true} {
		label := "zero"
		disbursementMessage := "0x" + strings.Repeat("00", 32)
		tombstone := "0x" + strings.Repeat("00", 32)
		if nonzero {
			label = "nonzero"
			disbursementMessage = "0x" + strings.Repeat("71", 32)
			tombstone = "0x" + strings.Repeat("72", 32)
		}
		t.Run(label, func(t *testing.T) {
			request := cancellationProjectionMessage(
				12,
				context,
				disbursementMessage,
				tombstone,
			)
			request.RoutePurpose = "disbursement"
			request.Envelope.RoutePolicyHash = disbursementRouteHash
			request.Envelope.SourceComponent = sourceRequest
			request.Envelope.DestinationComponent = destinationRequest
			requestFields := map[string]any{}
			projectedRequest, err := projectPhase8Action(
				request,
				manifest,
				context,
				requestFields,
			)
			if err != nil {
				t.Fatal(err)
			}
			if projectedRequest.LockID != context.FundingLockID ||
				projectedRequest.RouteID != "phase8-disbursement" ||
				projectedRequest.ActionFamilyHash != disbursementFamily ||
				requestFields["typed_action"] != "LOAN_CANCELLATION_REQUESTED" {
				t.Fatalf("request projection lost typed authority: %#v", projectedRequest)
			}

			completion := cancellationProjectionMessage(
				14,
				context,
				disbursementMessage,
				tombstone,
			)
			completion.RoutePurpose = "report"
			completion.Envelope.RoutePolicyHash = reportRouteHash
			completion.Envelope.SourceComponent = sourceCompletion
			completion.Envelope.DestinationComponent = destinationCompletion
			completionFields := map[string]any{}
			projectedCompletion, err := projectPhase8Action(
				completion,
				manifest,
				context,
				completionFields,
			)
			if err != nil {
				t.Fatal(err)
			}
			if projectedCompletion.RouteID != "phase8-report" ||
				projectedCompletion.ActionFamilyHash != reportFamily ||
				projectedCompletion.SourceBurnEvidenceHash !=
					completion.Source.RawEvidenceObjectHash ||
				projectedCompletion.BurnTransactionHash !=
					completion.Source.TransactionHash ||
				projectedCompletion.ReleaseTransactionHash !=
					completion.Destination.TransactionHash ||
				completionFields["typed_action"] != "SATELLITE_FUNDING_CANCELLED" {
				t.Fatalf(
					"completion projection lost exact evidence: %#v",
					projectedCompletion,
				)
			}

			tamperedDestination := completion
			tamperedDestination.Envelope.DestinationComponent =
				"0x" + strings.Repeat("99", 20)
			if _, err := projectPhase8Action(
				tamperedDestination,
				manifest,
				context,
				map[string]any{},
			); err == nil {
				t.Fatal("destination-component substitution was accepted")
			}
			malformedComponent := completion
			malformedComponent.Envelope.SourceComponent = "not-hex"
			if _, err := projectPhase8Action(
				malformedComponent,
				manifest,
				context,
				map[string]any{},
			); err == nil {
				t.Fatal("malformed cancellation component was accepted")
			}
			tamperedLender := completion
			tamperedLender.Payload = strings.Replace(
				completion.Payload,
				strings.TrimPrefix(context.Lender, "0x"),
				strings.Repeat("98", 20),
				1,
			)
			if _, err := projectPhase8Action(
				tamperedLender,
				manifest,
				context,
				map[string]any{},
			); err == nil {
				t.Fatal("lender-address substitution was accepted")
			}
		})
	}
}

func TestDecodeCancellationBundleRejectsTrailingGarbage(t *testing.T) {
	if _, err := decodePhase8CancellationImportBundle(
		[]byte(`{} trailing`),
		phase8ReleaseManifest{},
	); err == nil {
		t.Fatal("cancellation bundle accepted malformed trailing JSON")
	}
}

func TestProjectPhase8RepaymentBindsTypedEconomics(t *testing.T) {
	context := phase8FlowEconomics{
		LoanID:         "0x" + strings.Repeat("11", 32),
		FundingLockID:  "0x" + strings.Repeat("22", 32),
		BurnID:         "0x" + strings.Repeat("33", 32),
		PaymentID:      "0x" + strings.Repeat("44", 32),
		CanonicalAsset: "0x" + strings.Repeat("55", 20),
		WrappedAsset:   "0x" + strings.Repeat("66", 20),
		Lender:         "0x" + strings.Repeat("77", 20),
		PrincipalUnits: "100",
	}
	message := phase8ImportMessage{
		RoutePurpose: "repayment",
		Envelope: phase8ImportEnvelope{
			ActionType: 8,
			MessageID:  "0x" + strings.Repeat("88", 32),
		},
		Payload: actionPayloadHex(
			strings.Repeat("33", 32),
			strings.Repeat("11", 32),
			strings.Repeat("44", 32),
			strings.Repeat("99", 32),
			strings.Repeat("00", 12)+strings.Repeat("55", 20),
			strings.Repeat("00", 12)+strings.Repeat("aa", 20),
			strings.Repeat("00", 12)+strings.Repeat("66", 20),
			strings.Repeat("00", 12)+strings.Repeat("77", 20),
			uintWordHex(100),
		),
		Destination: phase8ImportDestination{
			ResultHash: "0x" + strings.Repeat("ab", 32),
		},
		Acknowledgement: phase8ImportAcknowledgement{
			Commitment: "0x" + strings.Repeat("cd", 32),
			Proof: phase8ImportProof{
				BlockTimestamp: json.Number("1700000000"),
			},
		},
	}
	fields := map[string]any{}
	action, err := projectPhase8Action(
		message,
		phase8ReleaseManifest{},
		context,
		fields,
	)
	if err != nil {
		t.Fatal(err)
	}
	if action.Action != 8 ||
		fields["burn_kind"] != "LOAN_REPAYMENT" ||
		fields["result_hash"] != strings.Repeat("ab", 32) ||
		fields["registry_recipient"] != context.Lender ||
		fields["units"] != json.Number("100") {
		t.Fatalf("repayment projection lost exact economics: %#v", fields)
	}
	tampered := message
	tampered.Payload = strings.Replace(
		message.Payload,
		strings.Repeat("77", 20),
		strings.Repeat("78", 20),
		1,
	)
	if _, err := projectPhase8Action(
		tampered,
		phase8ReleaseManifest{},
		context,
		map[string]any{},
	); err == nil {
		t.Fatal("lender substitution was accepted")
	}
}

func TestProjectPhase8ActionUsesAuthenticatedEffectReceiptMapping(t *testing.T) {
	context := phase8FlowEconomics{
		LoanID:                   "0x" + strings.Repeat("11", 32),
		FundingLockID:            "0x" + strings.Repeat("12", 32),
		CollateralID:             "0x" + strings.Repeat("13", 32),
		BurnID:                   "0x" + strings.Repeat("14", 32),
		PaymentID:                "0x" + strings.Repeat("15", 32),
		HomeLoan:                 "0x" + strings.Repeat("21", 20),
		Borrower:                 "0x" + strings.Repeat("22", 20),
		Lender:                   "0x" + strings.Repeat("23", 20),
		CanonicalAsset:           "0x" + strings.Repeat("24", 20),
		WrappedAsset:             "0x" + strings.Repeat("25", 20),
		CollateralAsset:          "0x" + strings.Repeat("26", 20),
		MintRecipient:            "0x" + strings.Repeat("28", 20),
		PrincipalUnits:           "100",
		CollateralUnits:          "200",
		PolicyHash:               "0x" + strings.Repeat("31", 32),
		SatelliteCollateralVault: "0x" + strings.Repeat("27", 20),
		SatelliteSettlementVault: "0x" + strings.Repeat("28", 20),
	}
	for index := range context.Messages {
		context.Messages[index] = phase8FlowMessageEffects{
			MessageID:                  "0x" + strings.Repeat(string(rune('a'+index)), 64),
			SourceTransactionHash:      "0x" + strings.Repeat(string(rune('1'+index)), 64),
			SourceLogIndex:             strconv.Itoa(index + 1),
			SourceFinalizedAt:          fmt.Sprintf("2026-01-01T00:00:%02dZ", index),
			SourceEventHash:            "0x" + strings.Repeat(string(rune('a'+index)), 64),
			DestinationTransactionHash: "0x" + strings.Repeat(string(rune('9'-index)), 64),
			DestinationLogIndex:        strconv.Itoa(index + 101),
			DestinationFinalizedAt:     fmt.Sprintf("2026-01-01T00:01:%02dZ", index),
			DestinationResultHash:      "0x" + strings.Repeat(string(rune('f'-index)), 64),
		}
	}
	manifest := phase8ReleaseManifest{Routes: []phase8ManifestRoute{{
		Purpose:         "MINT",
		Version:         1,
		RoutePolicyHash: "0x" + strings.Repeat("41", 32),
		AdapterID:       "0x" + strings.Repeat("42", 32),
	}}}
	cases := []struct {
		action      uint32
		message     int
		destination bool
	}{
		{1, 0, false},
		{5, 1, false},
		{2, 0, true},
		{6, 3, false},
		{7, 3, true},
		{8, 5, false},
		{9, 6, false},
		{10, 6, true},
	}
	for _, item := range cases {
		t.Run(strconv.FormatUint(uint64(item.action), 10), func(t *testing.T) {
			message := phase8ProjectionTestMessage(item.action, context)
			if item.action == 1 {
				message.RoutePurpose = "mint"
				message.Envelope.RoutePolicyHash = manifest.Routes[0].RoutePolicyHash
			}
			fields := map[string]any{}
			projected, err := projectPhase8Action(
				message,
				manifest,
				context,
				fields,
			)
			if err != nil {
				t.Fatal(err)
			}
			expected := context.Messages[item.message]
			transaction := expected.SourceTransactionHash
			logIndex := expected.SourceLogIndex
			finalizedAt := expected.SourceFinalizedAt
			if item.destination {
				transaction = expected.DestinationTransactionHash
				logIndex = expected.DestinationLogIndex
				finalizedAt = expected.DestinationFinalizedAt
			}
			if projected.EffectMessageID != expected.MessageID ||
				projected.EffectTransactionHash != transaction ||
				projected.EffectLogIndex != logIndex ||
				projected.FinalizedAt != finalizedAt {
				t.Fatalf("wrong effect mapping: %#v", projected)
			}
			if item.action == 8 &&
				(projected.BurnTransactionHash !=
					context.Messages[5].SourceTransactionHash ||
					projected.ReleaseTransactionHash !=
						context.Messages[5].DestinationTransactionHash ||
					projected.BurnLogIndex !=
						context.Messages[5].SourceLogIndex ||
					projected.ReleaseLogIndex !=
						context.Messages[5].DestinationLogIndex ||
					projected.BurnFinalizedAt !=
						context.Messages[5].SourceFinalizedAt ||
					projected.ReleaseFinalizedAt !=
						context.Messages[5].DestinationFinalizedAt) {
				t.Fatalf("repayment dual identities were lost: %#v", projected)
			}
			switch item.action {
			case 1:
				tampered := message
				tampered.Payload = strings.Replace(
					message.Payload,
					strings.TrimPrefix(context.MintRecipient, "0x"),
					strings.TrimPrefix(context.Borrower, "0x"),
					1,
				)
				if _, err := projectPhase8Action(
					tampered,
					manifest,
					context,
					map[string]any{},
				); err == nil {
					t.Fatal("borrower substitution for settlement escrow was accepted")
				}
			case 2:
				if projected.Recipient != context.MintRecipient {
					t.Fatal("wrapped mint recipient was not settlement escrow")
				}
			case 5:
				if projected.CustodyCommitment != context.Messages[1].SourceEventHash {
					t.Fatal("collateral custody used report evidence")
				}
			case 7:
				if projected.RecipientBalanceDeltaHash !=
					context.Messages[3].DestinationResultHash {
					t.Fatal("disbursement used report result")
				}
			case 9:
				if projected.ZeroDebtCommitment != context.Messages[6].SourceEventHash {
					t.Fatal("zero-debt authorization used release report")
				}
			case 10:
				if projected.ReleaseResultHash !=
					context.Messages[6].DestinationResultHash {
					t.Fatal("collateral release used report result")
				}
			}
		})
	}
}

func phase8ProjectionTestMessage(
	action uint32,
	context phase8FlowEconomics,
) phase8ImportMessage {
	bytes32 := func(value string) string { return strings.TrimPrefix(value, "0x") }
	address := func(value string) string {
		return strings.Repeat("00", 12) + strings.TrimPrefix(value, "0x")
	}
	var words []string
	switch action {
	case 1:
		words = []string{
			bytes32(context.FundingLockID), bytes32(context.LoanID),
			address(context.CanonicalAsset), address("0x" + strings.Repeat("29", 20)),
			address(context.WrappedAsset), address(context.MintRecipient), uintWordHex(100),
		}
	case 2:
		words = commonProjectionTestWords(context, context.FundingLockID, true)
	case 5:
		words = commonProjectionTestWords(context, context.CollateralID, false)
	case 6, 7:
		words = commonProjectionTestWords(context, context.FundingLockID, true)
	case 8:
		words = []string{
			bytes32(context.BurnID), bytes32(context.LoanID),
			bytes32(context.PaymentID), strings.Repeat("30", 32),
			address(context.CanonicalAsset), address("0x" + strings.Repeat("29", 20)),
			address(context.WrappedAsset), address(context.Lender), uintWordHex(100),
		}
	case 9, 10:
		words = commonProjectionTestWords(context, context.CollateralID, false)
	}
	return phase8ImportMessage{
		Envelope: phase8ImportEnvelope{
			ActionType:         action,
			SourceChainID:      json.Number("31337"),
			DestinationChainID: json.Number("31338"),
		},
		Payload: "0x" + strings.Join(words, ""),
		Destination: phase8ImportDestination{
			ResultHash: "0x" + strings.Repeat("ab", 32),
		},
		Acknowledgement: phase8ImportAcknowledgement{
			Commitment: "0x" + strings.Repeat("cd", 32),
			Proof: phase8ImportProof{
				BlockTimestamp: json.Number("1700000000"),
			},
		},
	}
}

func cancellationProjectionContext() phase8FlowEconomics {
	return phase8FlowEconomics{
		LoanID:         "0x" + strings.Repeat("11", 32),
		FundingLockID:  "0x" + strings.Repeat("12", 32),
		HomeLoan:       "0x" + strings.Repeat("21", 20),
		Lender:         "0x" + strings.Repeat("22", 20),
		CanonicalAsset: "0x" + strings.Repeat("23", 20),
		WrappedAsset:   "0x" + strings.Repeat("24", 20),
		PrincipalUnits: "100",
		PolicyHash:     "0x" + strings.Repeat("31", 32),
	}
}

func cancellationProjectionMessage(
	action uint32,
	context phase8FlowEconomics,
	disbursementMessage string,
	tombstone string,
) phase8ImportMessage {
	address := func(value string) string {
		return strings.Repeat("00", 12) + strings.TrimPrefix(value, "0x")
	}
	words := []string{
		strings.Repeat("a1", 32),
		strings.TrimPrefix(context.LoanID, "0x"),
		strings.TrimPrefix(context.FundingLockID, "0x"),
		strings.TrimPrefix(disbursementMessage, "0x"),
		strings.TrimPrefix(tombstone, "0x"),
	}
	if action == 12 {
		words = append(
			words,
			address(context.HomeLoan),
			address(context.Lender),
			address(context.WrappedAsset),
			uintWordHex(100),
			strings.TrimPrefix(context.PolicyHash, "0x"),
			strings.Repeat("b1", 32),
		)
	} else {
		words = append(
			words,
			strings.Repeat("b2", 32),
			address(context.HomeLoan),
			address(context.Lender),
			address(context.WrappedAsset),
			uintWordHex(100),
			strings.TrimPrefix(context.PolicyHash, "0x"),
		)
	}
	routePurpose := "disbursement"
	if action == 14 {
		routePurpose = "report"
	}
	return phase8ImportMessage{
		RoutePurpose: routePurpose,
		Envelope: phase8ImportEnvelope{
			ActionType:         action,
			MessageID:          "0x" + strings.Repeat("81", 32),
			SourceChainID:      json.Number("31338"),
			DestinationChainID: json.Number("31337"),
		},
		Payload: "0x" + strings.Join(words, ""),
		Source: phase8ImportSource{
			TransactionHash:       "0x" + strings.Repeat("82", 32),
			LogIndex:              json.Number("7"),
			RawEvidenceObjectHash: "0x" + strings.Repeat("83", 32),
			Proof: phase8ImportProof{
				BlockTimestamp: json.Number("1700000000"),
			},
		},
		Destination: phase8ImportDestination{
			TransactionHash: "0x" + strings.Repeat("84", 32),
			LogIndex:        json.Number("8"),
			ResultHash:      "0x" + strings.Repeat("85", 32),
		},
		Acknowledgement: phase8ImportAcknowledgement{
			Commitment: "0x" + strings.Repeat("86", 32),
			Proof: phase8ImportProof{
				BlockTimestamp: json.Number("1700000001"),
			},
		},
	}
}

func commonProjectionTestWords(
	context phase8FlowEconomics,
	operationID string,
	principal bool,
) []string {
	asset := context.CollateralAsset
	units := byte(200)
	if principal {
		asset = context.WrappedAsset
		units = 100
	}
	return []string{
		strings.TrimPrefix(context.LoanID, "0x"),
		strings.TrimPrefix(operationID, "0x"),
		strings.Repeat("00", 12) + strings.TrimPrefix(context.HomeLoan, "0x"),
		strings.Repeat("00", 12) + strings.TrimPrefix(context.Borrower, "0x"),
		strings.Repeat("00", 12) + strings.TrimPrefix(context.Lender, "0x"),
		strings.Repeat("00", 12) + strings.TrimPrefix(asset, "0x"),
		uintWordHex(units),
		strings.TrimPrefix(context.PolicyHash, "0x"),
	}
}

func actionPayloadHex(words ...string) string {
	return "0x" + strings.Join(words, "")
}

func uintWordHex(value byte) string {
	return strings.Repeat("00", 31) + hex.EncodeToString([]byte{value})
}
