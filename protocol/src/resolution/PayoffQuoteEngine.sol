// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ILoanRegistry } from "../interfaces/ILoanRegistry.sol";
import { IPayoffQuoteEngineV2 } from "../interfaces/phase9/IPayoffQuoteEngineV2.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";

/// @notice ABI/storage freeze stub for immutable version-2 payoff quotes.
contract PayoffQuoteEngine is IPayoffQuoteEngineV2 {
    struct QuoteDispositionV2 {
        IPayoffQuoteEngineV2.QuoteState state;
        bytes32 sourceEventId;
        bytes32 refinanceId;
        uint64 debtStateVersion;
        uint64 recordedAt;
    }

    ILoanRegistry private _loanRegistry;
    address private _quotePolicyRegistry;
    uint64 private _maximumQuoteValidity;
    address private _approvedPhase9Factory;
    address private _refinanceCoordinator;
    mapping(bytes32 loanId => uint64 nonce) private _nextQuoteNonce;
    mapping(bytes32 quoteId => IPayoffQuoteEngineV2.PayoffQuoteV2 quote_) private _quotes;
    mapping(bytes32 quoteId => IPayoffQuoteEngineV2.PayoffComponentV2[] components) private
        _quoteComponents;
    mapping(bytes32 quoteId => QuoteDispositionV2 disposition) private _quoteDispositions;
    mapping(bytes32 loanId => bytes32 quoteId) private _latestQuoteId;

    constructor(
        ILoanRegistry loanRegistry_,
        address quotePolicyRegistry_,
        uint64 maximumQuoteValidity_,
        address approvedPhase9Factory_,
        address refinanceCoordinator_
    ) {
        _loanRegistry = loanRegistry_;
        _quotePolicyRegistry = quotePolicyRegistry_;
        _maximumQuoteValidity = maximumQuoteValidity_;
        _approvedPhase9Factory = approvedPhase9Factory_;
        _refinanceCoordinator = refinanceCoordinator_;
    }

    function issueQuote(bytes32, uint64) external override returns (bytes32) {
        revert Phase9ImplementationNotFrozen();
    }

    function consumeQuote(bytes32, bytes32, uint64, bytes32)
        external
        override
        returns (PayoffQuoteV2 memory)
    {
        revert Phase9ImplementationNotFrozen();
    }

    function invalidateQuote(bytes32, bytes32) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function quote(bytes32 quoteId)
        external
        view
        override
        returns (PayoffQuoteV2 memory storedQuote, PayoffComponentV2[] memory components)
    {
        storedQuote = _quotes[quoteId];
        QuoteDispositionV2 memory disposition = _quoteDispositions[quoteId];
        if (disposition.state != QuoteState.NONE) storedQuote.state = disposition.state;
        components = _quoteComponents[quoteId];
    }
}
