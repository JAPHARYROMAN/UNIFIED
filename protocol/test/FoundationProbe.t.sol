// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import {FoundationProbe} from "../src/FoundationProbe.sol";
import {FoundationTypes} from "../src/generated/FoundationTypes.sol";

contract FoundationProbeTest {
    function testMoneyHashIsDeterministic() public {
        FoundationProbe probe = new FoundationProbe();
        FoundationTypes.Money memory amount = FoundationTypes.Money({
            assetId: FoundationTypes.AssetId({value: "asset:local:usd"}),
            units: "1000"
        });
        bytes32 first = probe.moneyHash(amount);
        bytes32 second = probe.moneyHash(amount);
        require(first == second, "money hash changed");
        require(first != bytes32(0), "money hash is empty");
    }
}

