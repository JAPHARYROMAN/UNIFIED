package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"time"
)

var phase8ExpectedActions = [...]uint32{1, 5, 2, 6, 7, 8, 9, 10}

var phase8ExpectedPurposes = [...]string{
	"mint",
	"report",
	"report",
	"disbursement",
	"report",
	"repayment",
	"collateral_release",
	"report",
}

var phase8MessagePurposeToRegistryPurpose = map[string]string{
	"mint":                "MINT",
	"report":              "REPORT",
	"repayment":           "REPAYMENT",
	"alternate_repayment": "ALTERNATE_REPAYMENT",
	"bridge_exit":         "BRIDGE_EXIT",
	"disbursement":        "DISBURSEMENT",
	"collateral_release":  "COLLATERAL_RELEASE",
}

type phase8DecodedPayload struct {
	Action uint32
	Words  []string
}

type phase8FlowEconomics struct {
	LoanID                   string
	FundingLockID            string
	CollateralID             string
	BurnID                   string
	PaymentID                string
	HomeLoan                 string
	Borrower                 string
	Lender                   string
	CanonicalAsset           string
	WrappedAsset             string
	CollateralAsset          string
	MintRecipient            string
	PrincipalUnits           string
	CollateralUnits          string
	PolicyHash               string
	SatelliteComponent       string
	SatelliteCollateralVault string
	SatelliteSettlementVault string
	Messages                 [8]phase8FlowMessageEffects
}

type phase8FlowMessageEffects struct {
	MessageID                  string
	SourceTransactionHash      string
	SourceLogIndex             string
	SourceFinalizedAt          string
	SourceEventHash            string
	DestinationTransactionHash string
	DestinationLogIndex        string
	DestinationFinalizedAt     string
	DestinationResultHash      string
}

type phase8ActionEconomics struct {
	Action                       uint32
	LockID                       string
	MintID                       string
	BurnID                       string
	PaymentID                    string
	LoanID                       string
	PositionID                   string
	AuthorizationID              string
	RouteID                      string
	RouteVersion                 uint64
	PolicyVersion                uint64
	ChainID                      string
	AdapterID                    string
	CanonicalAssetID             string
	WrappedAssetID               string
	CollateralAssetID            string
	Units                        string
	BorrowerID                   string
	LenderID                     string
	Recipient                    string
	Vault                        string
	RemotePositionKey            string
	CustodyCommitment            string
	SupplyAfterUnits             string
	RecipientBalanceDeltaHash    string
	ZeroDebtCommitment           string
	ReleaseResultHash            string
	AccountingReconciliationHash string
	CancellationID               string
	DisbursementMessageID        string
	DisbursementTombstoneHash    string
	EscrowBurnResultHash         string
	HomeLoanAccount              string
	LenderAddress                string
	WrappedTokenAddress          string
	ImmutablePolicyHash          string
	ReasonCode                   string
	ActionFamilyHash             string
	SourceComponent              string
	DestinationComponent         string
	SourceBurnEvidenceHash       string
	ResultHash                   string
	FinalizedAt                  string
	BurnFinalizedAt              string
	ReleaseFinalizedAt           string
	EffectMessageID              string
	EffectTransactionHash        string
	EffectLogIndex               string
	BurnTransactionHash          string
	BurnLogIndex                 string
	ReleaseTransactionHash       string
	ReleaseLogIndex              string
}

func derivePhase8FlowEconomics(
	flow phase8ImportFlow,
	manifest phase8ReleaseManifest,
) (phase8FlowEconomics, error) {
	if err := validatePhase8MessageOrder(flow.Messages); err != nil {
		return phase8FlowEconomics{}, err
	}
	decoded := make([]phase8DecodedPayload, len(flow.Messages))
	for index, message := range flow.Messages {
		payload, err := decodePhase8ActionPayload(
			message.Envelope.ActionType,
			message.Payload,
		)
		if err != nil {
			return phase8FlowEconomics{}, fmt.Errorf("message %d payload: %w", index, err)
		}
		decoded[index] = payload
	}
	context := phase8FlowEconomics{
		LoanID:                   decoded[1].Words[0],
		CollateralID:             decoded[1].Words[1],
		HomeLoan:                 decoded[1].Words[2],
		Borrower:                 decoded[1].Words[3],
		Lender:                   decoded[1].Words[4],
		CollateralAsset:          decoded[1].Words[5],
		CollateralUnits:          decoded[1].Words[6],
		PolicyHash:               decoded[1].Words[7],
		FundingLockID:            decoded[0].Words[0],
		CanonicalAsset:           decoded[0].Words[2],
		WrappedAsset:             decoded[0].Words[4],
		MintRecipient:            decoded[0].Words[5],
		PrincipalUnits:           decoded[0].Words[6],
		BurnID:                   decoded[5].Words[0],
		PaymentID:                decoded[5].Words[2],
		SatelliteComponent:       manifest.Domains.Satellite.Contracts["satellite_loan_component"].Address,
		SatelliteCollateralVault: manifest.Domains.Satellite.Contracts["satellite_collateral_vault"].Address,
		SatelliteSettlementVault: manifest.Domains.Satellite.Contracts["satellite_settlement_vault"].Address,
	}
	for index, message := range flow.Messages {
		context.Messages[index] = phase8FlowMessageEffects{
			MessageID:             message.Envelope.MessageID,
			SourceTransactionHash: message.Source.TransactionHash,
			SourceLogIndex:        message.Source.LogIndex.String(),
			SourceFinalizedAt: unixNumberRFC3339(
				message.Source.Proof.BlockTimestamp,
			),
			SourceEventHash:            message.Source.Proof.EventHash,
			DestinationTransactionHash: message.Destination.TransactionHash,
			DestinationLogIndex:        message.Destination.LogIndex.String(),
			DestinationFinalizedAt: unixNumberRFC3339(
				message.Acknowledgement.Proof.BlockTimestamp,
			),
			DestinationResultHash: message.Destination.ResultHash,
		}
	}
	for label, pair := range map[string][2]string{
		"flow loan ID":          {flow.LoanID, context.LoanID},
		"flow funding lock ID":  {flow.FundingLockID, context.FundingLockID},
		"flow collateral ID":    {flow.CollateralID, context.CollateralID},
		"flow loan account":     {flow.LoanAccount.Address, context.HomeLoan},
		"flow canonical asset":  {flow.CanonicalAsset.Address, context.CanonicalAsset},
		"flow wrapped asset":    {flow.WrappedAsset.Address, context.WrappedAsset},
		"flow collateral asset": {flow.CollateralAsset.Address, context.CollateralAsset},
		"flow principal units":  {flow.PrincipalUnits, context.PrincipalUnits},
		"flow collateral units": {flow.CollateralUnits, context.CollateralUnits},
		"lock payload loan ID":  {decoded[0].Words[1], context.LoanID},
		"lock payload recipient": {
			context.MintRecipient,
			context.SatelliteSettlementVault,
		},
	} {
		if pair[0] != pair[1] {
			return phase8FlowEconomics{}, fmt.Errorf("%s differs from exact payload", label)
		}
	}
	for index, payload := range decoded {
		if err := payload.matches(context); err != nil {
			return phase8FlowEconomics{}, fmt.Errorf(
				"message %d economics: %w",
				index,
				err,
			)
		}
	}
	return context, nil
}

func validatePhase8MessageOrder(messages []phase8ImportMessage) error {
	if len(messages) != len(phase8ExpectedActions) {
		return errors.New("Phase 8 flow must contain exactly eight messages")
	}
	for index, message := range messages {
		if message.Envelope.ActionType != phase8ExpectedActions[index] ||
			message.RoutePurpose != phase8ExpectedPurposes[index] {
			return fmt.Errorf(
				"message %d action/route order is not the reviewed full flow",
				index,
			)
		}
	}
	return nil
}

func validatePhase8CancellationOrder(
	messages []phase8ImportMessage,
	mintMessageID string,
) error {
	if len(messages) == 0 {
		return nil
	}
	if len(messages) != 2 {
		return errors.New(
			"Phase 8 cancellation flow must contain exact action 12 and action 14 messages",
		)
	}
	request, completion := messages[0], messages[1]
	requestMessageID, err := importHex(
		request.Envelope.MessageID,
		32,
		false,
	)
	if err != nil {
		return errors.New("cancellation request message ID is invalid")
	}
	if request.Sequence != 1 ||
		completion.Sequence != 2 ||
		request.Envelope.ActionType != 12 ||
		request.RoutePurpose != "disbursement" ||
		completion.Envelope.ActionType != 14 ||
		completion.RoutePurpose != "report" ||
		!sameHex(
			completion.Envelope.CausationMessageID,
			requestMessageID,
		) {
		return errors.New(
			"Phase 8 cancellation messages are not the reviewed request/completion path",
		)
	}
	requestPayload, err := decodePhase8ActionPayload(12, request.Payload)
	if err != nil {
		return fmt.Errorf("cancellation request payload: %w", err)
	}
	var expectedRequestCause []byte
	if requestPayload.Words[3] ==
		"0x"+strings.Repeat("00", 32) {
		expectedRequestCause, err = importHex(mintMessageID, 32, false)
		if err != nil {
			return errors.New(
				"zero-disbursement cancellation mint message ID is invalid",
			)
		}
	} else {
		expectedRequestCause, err = importHex(
			requestPayload.Words[3],
			32,
			false,
		)
		if err != nil {
			return errors.New(
				"nonzero cancellation disbursement message ID is invalid",
			)
		}
	}
	if !sameHex(request.Envelope.CausationMessageID, expectedRequestCause) {
		return errors.New(
			"cancellation request causation is not the exact mint or tombstoned disbursement",
		)
	}
	completionPayload, err := decodePhase8ActionPayload(14, completion.Payload)
	if err != nil {
		return fmt.Errorf("cancellation completion payload: %w", err)
	}
	for label, pair := range map[string][2]string{
		"cancellation": {
			requestPayload.Words[0],
			completionPayload.Words[0],
		},
		"loan": {
			requestPayload.Words[1],
			completionPayload.Words[1],
		},
		"funding lock": {
			requestPayload.Words[2],
			completionPayload.Words[2],
		},
		"disbursement message": {
			requestPayload.Words[3],
			completionPayload.Words[3],
		},
		"disbursement tombstone": {
			requestPayload.Words[4],
			completionPayload.Words[4],
		},
		"home loan": {
			requestPayload.Words[5],
			completionPayload.Words[6],
		},
		"lender": {
			requestPayload.Words[6],
			completionPayload.Words[7],
		},
		"wrapped token": {
			requestPayload.Words[7],
			completionPayload.Words[8],
		},
		"units": {
			requestPayload.Words[8],
			completionPayload.Words[9],
		},
		"policy": {
			requestPayload.Words[9],
			completionPayload.Words[10],
		},
	} {
		if pair[0] != pair[1] {
			return fmt.Errorf(
				"cancellation %s differs between request and completion",
				label,
			)
		}
	}
	return nil
}

func (payload phase8DecodedPayload) matches(context phase8FlowEconomics) error {
	var comparisons map[string][2]string
	switch payload.Action {
	case 1:
		comparisons = map[string][2]string{
			"lock":      {payload.Words[0], context.FundingLockID},
			"loan":      {payload.Words[1], context.LoanID},
			"canonical": {payload.Words[2], context.CanonicalAsset},
			"wrapped":   {payload.Words[4], context.WrappedAsset},
			"recipient": {payload.Words[5], context.MintRecipient},
			"amount":    {payload.Words[6], context.PrincipalUnits},
		}
	case 2:
		comparisons = commonLoanPayloadComparisons(payload.Words, context, true)
		comparisons["lock"] = [2]string{payload.Words[1], context.FundingLockID}
	case 5:
		comparisons = commonLoanPayloadComparisons(payload.Words, context, false)
		comparisons["collateral"] = [2]string{payload.Words[1], context.CollateralID}
	case 6, 7:
		comparisons = commonLoanPayloadComparisons(payload.Words, context, true)
		comparisons["lock"] = [2]string{payload.Words[1], context.FundingLockID}
	case 8:
		comparisons = map[string][2]string{
			"burn":      {payload.Words[0], context.BurnID},
			"loan":      {payload.Words[1], context.LoanID},
			"payment":   {payload.Words[2], context.PaymentID},
			"canonical": {payload.Words[4], context.CanonicalAsset},
			"wrapped":   {payload.Words[6], context.WrappedAsset},
			"lender":    {payload.Words[7], context.Lender},
			"amount":    {payload.Words[8], context.PrincipalUnits},
		}
	case 9, 10:
		comparisons = commonLoanPayloadComparisons(payload.Words, context, false)
		comparisons["collateral"] = [2]string{payload.Words[1], context.CollateralID}
	case 12:
		comparisons = map[string][2]string{
			"loan":         {payload.Words[1], context.LoanID},
			"funding lock": {payload.Words[2], context.FundingLockID},
			"home loan":    {payload.Words[5], context.HomeLoan},
			"lender":       {payload.Words[6], context.Lender},
			"wrapped":      {payload.Words[7], context.WrappedAsset},
			"amount":       {payload.Words[8], context.PrincipalUnits},
			"policy":       {payload.Words[9], context.PolicyHash},
		}
	case 14:
		comparisons = map[string][2]string{
			"loan":         {payload.Words[1], context.LoanID},
			"funding lock": {payload.Words[2], context.FundingLockID},
			"home loan":    {payload.Words[6], context.HomeLoan},
			"lender":       {payload.Words[7], context.Lender},
			"wrapped":      {payload.Words[8], context.WrappedAsset},
			"amount":       {payload.Words[9], context.PrincipalUnits},
			"policy":       {payload.Words[10], context.PolicyHash},
		}
	default:
		return errors.New("unsupported Phase 8 action")
	}
	for label, pair := range comparisons {
		if pair[0] != pair[1] {
			return fmt.Errorf("%s field differs across authenticated payloads", label)
		}
	}
	return nil
}

func commonLoanPayloadComparisons(
	words []string,
	context phase8FlowEconomics,
	principal bool,
) map[string][2]string {
	asset := context.CollateralAsset
	units := context.CollateralUnits
	if principal {
		asset = context.WrappedAsset
		units = context.PrincipalUnits
	}
	return map[string][2]string{
		"loan":        {words[0], context.LoanID},
		"home loan":   {words[2], context.HomeLoan},
		"borrower":    {words[3], context.Borrower},
		"lender":      {words[4], context.Lender},
		"asset":       {words[5], asset},
		"amount":      {words[6], units},
		"policy hash": {words[7], context.PolicyHash},
	}
}

func decodePhase8ActionPayload(
	action uint32,
	payloadHex string,
) (phase8DecodedPayload, error) {
	widths := map[uint32][]string{
		1:  {"bytes32", "bytes32", "address", "address", "address", "address", "uint256"},
		2:  {"bytes32", "bytes32", "address", "address", "address", "address", "uint256", "bytes32"},
		5:  {"bytes32", "bytes32", "address", "address", "address", "address", "uint256", "bytes32"},
		6:  {"bytes32", "bytes32", "address", "address", "address", "address", "uint256", "bytes32"},
		7:  {"bytes32", "bytes32", "address", "address", "address", "address", "uint256", "bytes32"},
		8:  {"bytes32", "bytes32", "bytes32", "bytes32", "address", "address", "address", "address", "uint256"},
		9:  {"bytes32", "bytes32", "address", "address", "address", "address", "uint256", "bytes32"},
		10: {"bytes32", "bytes32", "address", "address", "address", "address", "uint256", "bytes32"},
		12: {
			"bytes32", "bytes32", "bytes32", "bytes32", "bytes32",
			"address", "address", "address", "uint256", "bytes32", "bytes32",
		},
		14: {
			"bytes32", "bytes32", "bytes32", "bytes32", "bytes32", "bytes32",
			"address", "address", "address", "uint256", "bytes32",
		},
	}
	types, ok := widths[action]
	if !ok {
		return phase8DecodedPayload{}, errors.New("unsupported reviewed action payload")
	}
	payload, err := importHex(payloadHex, len(types)*32, false)
	if err != nil {
		return phase8DecodedPayload{}, errors.New("payload is not an exact static ABI tuple")
	}
	words := make([]string, len(types))
	for index, kind := range types {
		word := payload[index*32 : (index+1)*32]
		switch kind {
		case "bytes32":
			words[index] = "0x" + hex.EncodeToString(word)
		case "address":
			if !bytes.Equal(word[:12], make([]byte, 12)) {
				return phase8DecodedPayload{}, fmt.Errorf(
					"ABI address word %d is not canonically padded",
					index,
				)
			}
			words[index] = "0x" + hex.EncodeToString(word[12:])
		case "uint256":
			words[index] = new(big.Int).SetBytes(word).String()
		}
	}
	return phase8DecodedPayload{Action: action, Words: words}, nil
}

func projectPhase8Action(
	message phase8ImportMessage,
	manifest phase8ReleaseManifest,
	context phase8FlowEconomics,
	fields map[string]any,
) (phase8ActionEconomics, error) {
	payload, err := decodePhase8ActionPayload(message.Envelope.ActionType, message.Payload)
	if err != nil {
		return phase8ActionEconomics{}, err
	}
	if err := payload.matches(context); err != nil {
		return phase8ActionEconomics{}, err
	}
	action := phase8ActionEconomics{
		Action:            message.Envelope.ActionType,
		LoanID:            context.LoanID,
		ResultHash:        message.Destination.ResultHash,
		BorrowerID:        context.Borrower,
		LenderID:          context.Lender,
		CanonicalAssetID:  context.CanonicalAsset,
		WrappedAssetID:    context.WrappedAsset,
		CollateralAssetID: context.CollateralAsset,
	}
	effect := func(messageIndex int, destination bool) {
		identity := context.Messages[messageIndex]
		action.EffectMessageID = identity.MessageID
		action.EffectTransactionHash = identity.SourceTransactionHash
		action.EffectLogIndex = identity.SourceLogIndex
		action.FinalizedAt = identity.SourceFinalizedAt
		if destination {
			action.EffectTransactionHash = identity.DestinationTransactionHash
			action.EffectLogIndex = identity.DestinationLogIndex
			action.FinalizedAt = identity.DestinationFinalizedAt
		}
		fields["effect_message_id"] = strings.TrimPrefix(
			action.EffectMessageID,
			"0x",
		)
		fields["effect_transaction_hash"] = strings.TrimPrefix(
			action.EffectTransactionHash,
			"0x",
		)
		fields["effect_log_index"] = json.Number(action.EffectLogIndex)
		fields["effect_finalized_at"] = action.FinalizedAt
	}
	put := func(key, value string) {
		fields[key] = value
	}
	putNumber := func(key, value string) {
		fields[key] = json.Number(value)
	}
	switch action.Action {
	case 1:
		effect(0, false)
		route, err := phase8RouteForMessage(message, manifest)
		if err != nil {
			return phase8ActionEconomics{}, err
		}
		action.LockID = context.FundingLockID
		action.RouteID = phase8RouteID(route.Purpose)
		action.RouteVersion = route.Version
		action.PolicyVersion = route.Version
		action.ChainID = message.Envelope.DestinationChainID.String()
		action.AdapterID = route.AdapterID
		action.Units = context.PrincipalUnits
		put("lock_id", action.LockID)
		put("route_id", action.RouteID)
		putNumber("route_version", fmt.Sprint(action.RouteVersion))
		putNumber("chain_id", action.ChainID)
		put("adapter_id", action.AdapterID)
		put("canonical_asset_id", action.CanonicalAssetID)
		put("wrapped_asset_id", action.WrappedAssetID)
		putNumber("units", action.Units)
		put("lender_id", action.LenderID)
		put("loan_id", action.LoanID)
	case 2:
		effect(0, true)
		action.MintID = message.Envelope.MessageID
		action.LockID = context.FundingLockID
		action.Units = context.PrincipalUnits
		action.Recipient = context.MintRecipient
		action.SupplyAfterUnits = context.PrincipalUnits
		put("mint_id", action.MintID)
		put("lock_id", action.LockID)
		put("wrapped_asset_id", action.WrappedAssetID)
		putNumber("units", action.Units)
		put("recipient", action.Recipient)
		putNumber("supply_after_units", action.SupplyAfterUnits)
	case 5:
		effect(1, false)
		action.PositionID = context.CollateralID
		action.ChainID = message.Envelope.SourceChainID.String()
		action.Vault = context.SatelliteCollateralVault
		action.RemotePositionKey = context.CollateralID
		action.Units = context.CollateralUnits
		action.CustodyCommitment = context.Messages[1].SourceEventHash
		put("position_id", action.PositionID)
		put("loan_id", action.LoanID)
		putNumber("satellite_chain_id", action.ChainID)
		put("vault", strings.TrimPrefix(action.Vault, "0x"))
		put("asset_id", action.CollateralAssetID)
		put("remote_position_key", action.RemotePositionKey)
		putNumber("units", action.Units)
		put("borrower_id", action.BorrowerID)
		put("custody_commitment", strings.TrimPrefix(action.CustodyCommitment, "0x"))
	case 6:
		effect(3, false)
		action.AuthorizationID = context.FundingLockID
		action.Units = context.PrincipalUnits
		action.Vault = context.SatelliteSettlementVault
		put("authorization_id", action.AuthorizationID)
		put("loan_id", action.LoanID)
		put("wrapped_asset_id", action.WrappedAssetID)
		putNumber("units", action.Units)
		put("borrower_id", action.BorrowerID)
		put("settlement_vault", strings.TrimPrefix(action.Vault, "0x"))
	case 7:
		effect(3, true)
		action.AuthorizationID = context.FundingLockID
		action.Units = context.PrincipalUnits
		action.RecipientBalanceDeltaHash =
			context.Messages[3].DestinationResultHash
		put("authorization_id", action.AuthorizationID)
		put("loan_id", action.LoanID)
		put("recipient_balance_delta_hash", strings.TrimPrefix(action.RecipientBalanceDeltaHash, "0x"))
		putNumber("units", action.Units)
	case 8:
		effect(5, false)
		action.BurnTransactionHash = context.Messages[5].SourceTransactionHash
		action.BurnLogIndex = context.Messages[5].SourceLogIndex
		action.BurnFinalizedAt = context.Messages[5].SourceFinalizedAt
		action.ReleaseTransactionHash = context.Messages[5].DestinationTransactionHash
		action.ReleaseLogIndex = context.Messages[5].DestinationLogIndex
		action.ReleaseFinalizedAt = context.Messages[5].DestinationFinalizedAt
		put("burn_transaction_hash", strings.TrimPrefix(action.BurnTransactionHash, "0x"))
		putNumber("burn_log_index", action.BurnLogIndex)
		put("release_transaction_hash", strings.TrimPrefix(action.ReleaseTransactionHash, "0x"))
		putNumber("release_log_index", action.ReleaseLogIndex)
		put("burn_finalized_at", action.BurnFinalizedAt)
		put("release_finalized_at", action.ReleaseFinalizedAt)
		action.BurnID = context.BurnID
		action.PaymentID = context.PaymentID
		action.LockID = context.FundingLockID
		action.Units = context.PrincipalUnits
		action.Recipient = context.Lender
		action.SupplyAfterUnits = "0"
		put("burn_id", action.BurnID)
		put("lock_id", action.LockID)
		put("payment_id", action.PaymentID)
		put("loan_id", action.LoanID)
		put("canonical_asset_id", action.CanonicalAssetID)
		put("asset_id", action.CanonicalAssetID)
		put("wrapped_asset_id", action.WrappedAssetID)
		putNumber("units", action.Units)
		put("registry_recipient", action.Recipient)
		put("lender_id", action.LenderID)
		put("burn_kind", "LOAN_REPAYMENT")
		putNumber("supply_after_units", action.SupplyAfterUnits)
		put("release_id", action.BurnID)
		put("result_hash", strings.TrimPrefix(message.Destination.ResultHash, "0x"))
	case 9:
		effect(6, false)
		action.AuthorizationID = context.CollateralID
		action.PositionID = context.CollateralID
		action.ZeroDebtCommitment = context.Messages[6].SourceEventHash
		put("authorization_id", action.AuthorizationID)
		put("loan_id", action.LoanID)
		put("position_id", action.PositionID)
		put("zero_debt_commitment", strings.TrimPrefix(action.ZeroDebtCommitment, "0x"))
		put("borrower_id", action.BorrowerID)
	case 10:
		effect(6, true)
		action.AuthorizationID = context.CollateralID
		action.PositionID = context.CollateralID
		action.ReleaseResultHash = context.Messages[6].DestinationResultHash
		action.AccountingReconciliationHash = message.Acknowledgement.Commitment
		put("authorization_id", action.AuthorizationID)
		put("loan_id", action.LoanID)
		put("position_id", action.PositionID)
		put("release_result_hash", strings.TrimPrefix(action.ReleaseResultHash, "0x"))
		put(
			"accounting_reconciliation_hash",
			strings.TrimPrefix(action.AccountingReconciliationHash, "0x"),
		)
		put("borrower_id", action.BorrowerID)
	case 12, 14:
		route, err := phase8RouteForMessage(message, manifest)
		if err != nil {
			return phase8ActionEconomics{}, err
		}
		sourceComponent, err := importHex(
			message.Envelope.SourceComponent,
			20,
			false,
		)
		if err != nil {
			return phase8ActionEconomics{}, errors.New(
				"cancellation source component is invalid",
			)
		}
		destinationComponent, err := importHex(
			message.Envelope.DestinationComponent,
			20,
			false,
		)
		if err != nil {
			return phase8ActionEconomics{}, errors.New(
				"cancellation destination component is invalid",
			)
		}
		expectedPurpose := "DISBURSEMENT"
		expectedTypedAction := "LOAN_CANCELLATION_REQUESTED"
		if action.Action == 14 {
			expectedPurpose = "REPORT"
			expectedTypedAction = "SATELLITE_FUNDING_CANCELLED"
		}
		if route.Purpose != expectedPurpose ||
			!sameHex(route.SourceComponent, sourceComponent) ||
			!sameHex(route.DestinationComponent, destinationComponent) {
			return phase8ActionEconomics{}, errors.New(
				"cancellation action does not bind the exact reviewed route components",
			)
		}
		action.RouteID = phase8RouteID(route.Purpose)
		action.ActionFamilyHash = strings.ToLower(route.ActionFamily)
		action.SourceComponent = strings.ToLower(message.Envelope.SourceComponent)
		action.DestinationComponent = strings.ToLower(
			message.Envelope.DestinationComponent,
		)
		action.CancellationID = payload.Words[0]
		action.LoanID = payload.Words[1]
		action.LockID = payload.Words[2]
		action.DisbursementMessageID = payload.Words[3]
		action.DisbursementTombstoneHash = payload.Words[4]
		action.Units = context.PrincipalUnits
		action.HomeLoanAccount = context.HomeLoan
		action.LenderAddress = context.Lender
		action.WrappedTokenAddress = context.WrappedAsset
		action.ImmutablePolicyHash = context.PolicyHash
		action.FinalizedAt = unixNumberRFC3339(
			message.Acknowledgement.Proof.BlockTimestamp,
		)
		put("typed_action", expectedTypedAction)
		put("route_id", action.RouteID)
		put("action_family_hash", action.ActionFamilyHash)
		put("source_component", strings.TrimPrefix(action.SourceComponent, "0x"))
		put(
			"destination_component",
			strings.TrimPrefix(action.DestinationComponent, "0x"),
		)
		put("cancellation_id", action.CancellationID)
		put("loan_id", action.LoanID)
		put("funding_lock_id", context.FundingLockID)
		put(
			"disbursement_message_id",
			strings.TrimPrefix(action.DisbursementMessageID, "0x"),
		)
		put(
			"disbursement_tombstone_hash",
			strings.TrimPrefix(action.DisbursementTombstoneHash, "0x"),
		)
		put("home_loan_account", strings.TrimPrefix(action.HomeLoanAccount, "0x"))
		put("lender_address", strings.TrimPrefix(action.LenderAddress, "0x"))
		put(
			"wrapped_token",
			strings.TrimPrefix(action.WrappedTokenAddress, "0x"),
		)
		putNumber("units", action.Units)
		put(
			"policy_hash",
			strings.TrimPrefix(action.ImmutablePolicyHash, "0x"),
		)
		if action.Action == 12 {
			action.ReasonCode = payload.Words[10]
			put("reason_code", strings.TrimPrefix(action.ReasonCode, "0x"))
			action.EffectMessageID = message.Envelope.MessageID
			action.EffectTransactionHash = message.Destination.TransactionHash
			action.EffectLogIndex = message.Destination.LogIndex.String()
			fields["effect_message_id"] = strings.TrimPrefix(
				action.EffectMessageID,
				"0x",
			)
			fields["effect_transaction_hash"] = strings.TrimPrefix(
				action.EffectTransactionHash,
				"0x",
			)
			fields["effect_log_index"] = json.Number(action.EffectLogIndex)
			fields["effect_finalized_at"] = action.FinalizedAt
			break
		}
		action.EscrowBurnResultHash = payload.Words[5]
		action.SourceBurnEvidenceHash = message.Source.RawEvidenceObjectHash
		action.BurnTransactionHash = message.Source.TransactionHash
		action.BurnLogIndex = message.Source.LogIndex.String()
		action.BurnFinalizedAt = unixNumberRFC3339(
			message.Source.Proof.BlockTimestamp,
		)
		action.ReleaseTransactionHash = message.Destination.TransactionHash
		action.ReleaseLogIndex = message.Destination.LogIndex.String()
		action.ReleaseFinalizedAt = action.FinalizedAt
		action.ResultHash = message.Destination.ResultHash
		action.EffectMessageID = message.Envelope.MessageID
		action.EffectTransactionHash = action.ReleaseTransactionHash
		action.EffectLogIndex = action.ReleaseLogIndex
		put(
			"escrow_burn_result_hash",
			strings.TrimPrefix(action.EscrowBurnResultHash, "0x"),
		)
		put(
			"source_burn_transaction_hash",
			strings.TrimPrefix(action.BurnTransactionHash, "0x"),
		)
		putNumber("source_burn_log_index", action.BurnLogIndex)
		put(
			"source_burn_evidence_hash",
			strings.TrimPrefix(action.SourceBurnEvidenceHash, "0x"),
		)
		put("source_burn_finalized_at", action.BurnFinalizedAt)
		put(
			"destination_refund_transaction_hash",
			strings.TrimPrefix(action.ReleaseTransactionHash, "0x"),
		)
		putNumber("destination_refund_log_index", action.ReleaseLogIndex)
		put(
			"destination_refund_result_hash",
			strings.TrimPrefix(action.ResultHash, "0x"),
		)
		put("destination_refund_finalized_at", action.ReleaseFinalizedAt)
		fields["effect_message_id"] = strings.TrimPrefix(
			action.EffectMessageID,
			"0x",
		)
		fields["effect_transaction_hash"] = strings.TrimPrefix(
			action.EffectTransactionHash,
			"0x",
		)
		fields["effect_log_index"] = json.Number(action.EffectLogIndex)
		fields["effect_finalized_at"] = action.FinalizedAt
	}
	return action, nil
}

func phase8RouteForMessage(
	message phase8ImportMessage,
	manifest phase8ReleaseManifest,
) (phase8ManifestRoute, error) {
	registryPurpose, ok :=
		phase8MessagePurposeToRegistryPurpose[message.RoutePurpose]
	if !ok {
		return phase8ManifestRoute{}, errors.New(
			"message route purpose is not in the exact lowercase vocabulary",
		)
	}
	for _, route := range manifest.Routes {
		if route.Purpose == registryPurpose &&
			route.RoutePolicyHash == message.Envelope.RoutePolicyHash {
			return route, nil
		}
	}
	return phase8ManifestRoute{}, errors.New("message has no exact manifest route")
}

func phase8RouteID(purpose string) string {
	return "phase8-" + strings.ToLower(strings.ReplaceAll(purpose, "_", "-"))
}

const (
	bootstrapLoanRouteSQL = `
SELECT crosschain.register_loan_route(
    $1, $2, $3, $4::numeric, $5::numeric, $6, $7, $8, $9,
    $10, $11::numeric, $12, $13::numeric, $14, $15
)`
	bootstrapExposureSQL = `
SELECT crosschain.activate_bridge_exposure_policy(
    $1, $2::numeric, $3, $4::numeric, $5::numeric, $6::numeric,
    $7::numeric, $8, $9, $10
)`
)

func bootstrapManifestEconomics(
	ctx context.Context,
	databaseURL string,
	manifest phase8ReleaseManifest,
	flow phase8ImportFlow,
) error {
	if ctx == nil || databaseURL == "" {
		return errors.New("economics bootstrap requires owner database")
	}
	database, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return err
	}
	defer func() { _ = database.Close() }()
	if err := database.PingContext(ctx); err != nil {
		return err
	}
	var role string
	if err := database.QueryRowContext(ctx, "SELECT current_user").Scan(&role); err != nil {
		return err
	}
	if role != "unified_local" && role != "unified_crosschain_owner" {
		return errors.New("economics bootstrap requires local owner role")
	}
	var mintRoute *phase8ManifestRoute
	for index := range manifest.Routes {
		if manifest.Routes[index].Purpose == "MINT" {
			mintRoute = &manifest.Routes[index]
			break
		}
	}
	if mintRoute == nil {
		return errors.New("MINT route is required for loan bootstrap")
	}
	createdAt := mustUnixNumberTime(flow.Messages[0].Envelope.CreatedAt)
	economics := flow.Economics
	if _, err := database.ExecContext(
		ctx,
		bootstrapLoanRouteSQL,
		economics.LoanID,
		phase8RouteID(mintRoute.Purpose),
		int64(mintRoute.Version),
		manifest.Domains.Home.ChainID.String(),
		manifest.Domains.Satellite.ChainID.String(),
		mustImportHex(economics.HomeLoan, 20, false),
		mustImportHex(economics.SatelliteComponent, 20, false),
		economics.Borrower,
		economics.Lender,
		economics.CanonicalAsset,
		economics.PrincipalUnits,
		economics.CollateralAsset,
		economics.CollateralUnits,
		mustImportHex(economics.PolicyHash, 32, false),
		createdAt,
	); err != nil {
		return fmt.Errorf("register manifest loan route: %w", err)
	}
	exposure := manifest.ExposurePolicy
	evidenceHash := mustImportHex(
		exposure.CirculatingSupplyEvidenceHash,
		32,
		false,
	)
	effectiveAt := time.Unix(int64(exposure.ActiveFrom), 0).UTC()
	if _, err := database.ExecContext(
		ctx,
		bootstrapExposureSQL,
		int64(exposure.PolicyVersion),
		exposure.CirculatingSupplyReferenceUnits,
		evidenceHash,
		exposure.RouteAbsoluteCapUnits,
		exposure.ChainAbsoluteCapUnits,
		exposure.AdapterAbsoluteCapUnits,
		exposure.AggregateAbsoluteCapUnits,
		int64(exposure.RoutePercentageCeilingBasisPoints),
		int64(exposure.AggregatePercentageCeilingBasisPoints),
		effectiveAt,
	); err != nil {
		return fmt.Errorf("activate manifest bridge exposure: %w", err)
	}
	return nil
}

func commitPhase8Action(
	ctx context.Context,
	runtime *sql.DB,
	messageID []byte,
	input phase8SQLImport,
) error {
	if ctx == nil || runtime == nil || len(messageID) != 32 {
		return errors.New("typed action commit requires runtime database and message")
	}
	var projectionHash []byte
	if err := runtime.QueryRowContext(
		ctx,
		`SELECT projection_hash
		   FROM crosschain.action_projections
		  WHERE message_id = $1`,
		messageID,
	).Scan(&projectionHash); err != nil {
		return fmt.Errorf("load exact action projection: %w", err)
	}
	action := input.ActionEconomics
	transactionHash := mustImportHex(action.EffectTransactionHash, 32, false)
	logIndex := action.EffectLogIndex
	finalizedAt := mustImportTime(action.FinalizedAt)
	exec := func(query string, arguments ...any) error {
		if _, err := runtime.ExecContext(ctx, query, arguments...); err != nil {
			return err
		}
		return nil
	}
	switch action.Action {
	case 1:
		return exec(
			`SELECT crosschain.commit_bridge_lock(
			    $1, $2, $3, $4, $5::numeric, $6, $7, $8, $9,
			    $10::numeric, $11, $12, $13, $14::numeric, $15, $16
			)`,
			action.LockID,
			action.RouteID,
			int64(action.RouteVersion),
			int64(action.PolicyVersion),
			action.ChainID,
			action.AdapterID,
			messageID,
			action.CanonicalAssetID,
			action.WrappedAssetID,
			action.Units,
			action.LenderID,
			action.LoanID,
			transactionHash,
			logIndex,
			projectionHash,
			finalizedAt,
		)
	case 2:
		return exec(
			`SELECT crosschain.commit_wrapped_mint(
			    $1, $2, $3, $4, $5::numeric, $6, $7, $8::numeric,
			    $9::numeric, $10, $11
			)`,
			action.MintID,
			action.LockID,
			messageID,
			action.WrappedAssetID,
			action.Units,
			action.Recipient,
			transactionHash,
			logIndex,
			action.SupplyAfterUnits,
			projectionHash,
			finalizedAt,
		)
	case 5:
		return exec(
			`SELECT crosschain.commit_satellite_collateral_lock(
			    $1, $2, $3::numeric, $4, $5, $6, $7::numeric,
			    $8, $9, $10, $11
			)`,
			action.PositionID,
			action.LoanID,
			action.ChainID,
			mustImportHex(action.Vault, 20, false),
			action.CollateralAssetID,
			action.RemotePositionKey,
			action.Units,
			action.BorrowerID,
			messageID,
			mustImportHex(action.CustodyCommitment, 32, false),
			finalizedAt,
		)
	case 6:
		return exec(
			`SELECT crosschain.commit_disbursement_authorization(
			    $1, $2, $3, $4, $5::numeric, $6, $7, $8
			)`,
			action.AuthorizationID,
			action.LoanID,
			messageID,
			action.WrappedAssetID,
			action.Units,
			action.BorrowerID,
			mustImportHex(action.Vault, 20, false),
			finalizedAt,
		)
	case 7:
		return exec(
			`SELECT crosschain.commit_disbursement_result(
			    $1, $2, $3, $4, $5::numeric, $6, $7::numeric, $8
			)`,
			action.AuthorizationID,
			action.LoanID,
			messageID,
			transactionHash,
			logIndex,
			mustImportHex(action.RecipientBalanceDeltaHash, 32, false),
			action.Units,
			finalizedAt,
		)
	case 8:
		burnTransactionHash := mustImportHex(
			action.BurnTransactionHash,
			32,
			false,
		)
		burnFinalizedAt := mustImportTime(action.BurnFinalizedAt)
		releaseTransactionHash := mustImportHex(
			action.ReleaseTransactionHash,
			32,
			false,
		)
		releaseFinalizedAt := mustImportTime(action.ReleaseFinalizedAt)
		if err := exec(
			`SELECT crosschain.commit_wrapped_burn(
			    $1, $2, $3, $4, $5, $6::numeric, $7, 'LOAN_REPAYMENT',
			    $8, $9::numeric, $10::numeric, $11, $12
			)`,
			action.BurnID,
			action.LockID,
			messageID,
			action.PaymentID,
			action.WrappedAssetID,
			action.Units,
			action.LenderID,
			burnTransactionHash,
			action.BurnLogIndex,
			action.SupplyAfterUnits,
			projectionHash,
			burnFinalizedAt,
		); err != nil {
			return fmt.Errorf("wrapped repayment burn: %w", err)
		}
		if err := exec(
			`SELECT crosschain.commit_canonical_release(
			    $1, $2, $3, $4, $5::numeric, $6, $7, $8::numeric, $9, $10
			)`,
			action.BurnID,
			action.BurnID,
			messageID,
			action.CanonicalAssetID,
			action.Units,
			action.LenderID,
			releaseTransactionHash,
			action.ReleaseLogIndex,
			mustImportHex(action.ResultHash, 32, false),
			releaseFinalizedAt,
		); err != nil {
			return fmt.Errorf("canonical repayment release: %w", err)
		}
		return exec(
			`SELECT crosschain.commit_remote_repayment(
			    $1, $2, $3, $4, $5, $6, $7::numeric, $8::numeric,
			    0::numeric, $9, $10, $11::numeric, $12, $13
			)`,
			action.PaymentID,
			action.LoanID,
			action.BurnID,
			messageID,
			mustImportHex(action.ResultHash, 32, false),
			action.CanonicalAssetID,
			action.Units,
			action.Units,
			action.LenderID,
			releaseTransactionHash,
			action.ReleaseLogIndex,
			projectionHash,
			releaseFinalizedAt,
		)
	case 9:
		return exec(
			`SELECT crosschain.commit_collateral_release_authorization(
			    $1, $2, $3, $4, $5, $6, $7
			)`,
			action.AuthorizationID,
			action.LoanID,
			action.PositionID,
			messageID,
			mustImportHex(action.ZeroDebtCommitment, 32, false),
			action.BorrowerID,
			finalizedAt,
		)
	case 10:
		return exec(
			`SELECT crosschain.commit_collateral_release(
			    $1, $2, $3, $4, $5, $6::numeric, $7, $8, $9, $10
			)`,
			action.AuthorizationID,
			action.LoanID,
			action.PositionID,
			messageID,
			transactionHash,
			logIndex,
			mustImportHex(action.ReleaseResultHash, 32, false),
			mustImportHex(action.AccountingReconciliationHash, 32, false),
			action.BorrowerID,
			finalizedAt,
		)
	case 12:
		return exec(
			`SELECT crosschain.record_loan_cancellation_request(
			    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
			    $12, $13::numeric, $14, $15, $16
			)`,
			action.CancellationID,
			action.LoanID,
			action.LockID,
			messageID,
			action.RouteID,
			mustImportHex(action.SourceComponent, 20, false),
			mustImportHex(action.DestinationComponent, 20, false),
			mustImportHex(action.DisbursementMessageID, 32, false),
			mustImportHex(action.DisbursementTombstoneHash, 32, false),
			mustImportHex(action.HomeLoanAccount, 20, false),
			mustImportHex(action.LenderAddress, 20, false),
			mustImportHex(action.WrappedTokenAddress, 20, false),
			action.Units,
			mustImportHex(action.ImmutablePolicyHash, 32, false),
			mustImportHex(action.ReasonCode, 32, false),
			finalizedAt,
		)
	case 14:
		return exec(
			`SELECT crosschain.commit_loan_cancellation_completion(
			    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
			    $12, $13, $14::numeric, $15, $16, $17::numeric, $18,
			    $19, $20, $21::numeric, $22, $23
			)`,
			action.CancellationID,
			action.LoanID,
			action.LockID,
			messageID,
			action.RouteID,
			mustImportHex(action.SourceComponent, 20, false),
			mustImportHex(action.DestinationComponent, 20, false),
			mustImportHex(action.DisbursementMessageID, 32, false),
			mustImportHex(action.DisbursementTombstoneHash, 32, false),
			mustImportHex(action.EscrowBurnResultHash, 32, false),
			mustImportHex(action.HomeLoanAccount, 20, false),
			mustImportHex(action.LenderAddress, 20, false),
			mustImportHex(action.WrappedTokenAddress, 20, false),
			action.Units,
			mustImportHex(action.ImmutablePolicyHash, 32, false),
			mustImportHex(action.BurnTransactionHash, 32, false),
			action.BurnLogIndex,
			mustImportHex(action.SourceBurnEvidenceHash, 32, false),
			mustImportTime(action.BurnFinalizedAt),
			mustImportHex(action.ReleaseTransactionHash, 32, false),
			action.ReleaseLogIndex,
			mustImportHex(action.ResultHash, 32, false),
			mustImportTime(action.ReleaseFinalizedAt),
		)
	default:
		return errors.New("unsupported typed Phase 8 action")
	}
}
