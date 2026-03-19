// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockXID
/// @notice Mock xID precompile for testing.
contract MockXID {
    mapping(bytes32 => address) private _resolutions;
    mapping(address => string) private _reverseNames;
    mapping(address => string) private _reverseTlds;

    function setResolution(string calldata name, string calldata tld, address owner) external {
        bytes32 key = keccak256(abi.encodePacked(name, tld));
        _resolutions[key] = owner;
        _reverseNames[owner] = name;
        _reverseTlds[owner] = tld;
    }

    function resolve(string calldata name, string calldata tld) external view returns (address) {
        bytes32 key = keccak256(abi.encodePacked(name, tld));
        return _resolutions[key];
    }

    function reverseResolve(address addr) external view returns (string memory, string memory) {
        return (_reverseNames[addr], _reverseTlds[addr]);
    }

    function getPrimaryName(address owner) external view returns (string memory, string memory) {
        return (_reverseNames[owner], _reverseTlds[owner]);
    }
}
