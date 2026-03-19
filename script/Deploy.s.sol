// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {EpixAirdrop} from "../src/EpixAirdrop.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        EpixAirdrop airdrop = new EpixAirdrop();

        console.log("EpixAirdrop deployed at:", address(airdrop));

        vm.stopBroadcast();
    }
}
