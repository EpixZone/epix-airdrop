# Epix Airdrop

Pool-based airdrop contract for [Epix Chain](https://epix.zone). Anyone can fund the pool, and each address may claim once. Demonstrates how to integrate the **xID precompile** into Solidity contracts - xID holders receive a 10x claim boost.

## xID Integration

Epix Chain provides an [xID precompile](https://docs.epix.zone) at `0x0000000000000000000000000000000000000900` that lets smart contracts resolve human-readable names to EVM addresses (and vice versa) without any external oracle or off-chain lookup.

### Interface

Copy `src/IXID.sol` into your project to use the xID precompile:

```solidity
address constant XID_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000900;
IXID constant XID = IXID(XID_PRECOMPILE_ADDRESS);

interface IXID {
    // "mud" + "epix" -> 0x1234...
    function resolve(string calldata name, string calldata tld) external view returns (address owner);

    // 0x1234... -> ("mud", "epix")
    function reverseResolve(address addr) external view returns (string memory name, string memory tld);

    // Same as reverseResolve but returns the user's chosen primary name
    function getPrimaryName(address owner) external view returns (string memory name, string memory tld);
}
```

### Checking if an Address Has an xID

This contract uses reverse resolution to check if a claimer has a registered xID, then gives them a 10x boost:

```solidity
function claim() external {
    bool hasXid = _hasXid(msg.sender);

    uint256 amount;
    if (hasXid) {
        amount = (pool * CLAIM_RATE_BPS * XID_MULTIPLIER) / _BPS;  // 1% of pool
        if (amount > MAX_CLAIM_XID) amount = MAX_CLAIM_XID;        // cap at 10,000 EPIX
    } else {
        amount = (pool * CLAIM_RATE_BPS) / _BPS;                   // 0.1% of pool
        if (amount > MAX_CLAIM) amount = MAX_CLAIM;                // cap at 1,000 EPIX
    }
    // ...
}

function _hasXid(address addr) private view returns (bool) {
    (string memory name,) = _tryReverseResolve(addr);
    return bytes(name).length > 0;
}
```

### Displaying xID Names in Results

The contract also resolves xID names for display in the recent claims feed:

```solidity
function _tryReverseResolve(address addr) private view returns (string memory name, string memory tld) {
    try XID.reverseResolve(addr) returns (string memory n, string memory t) {
        return (n, t);
    } catch {
        return ("", "");  // no xID registered or precompile unavailable
    }
}
```

### Best Practice: Always Wrap in try/catch

The xID precompile is a chain-level feature. If your contract might be deployed on a fork, testnet, or chain where the precompile isn't available, wrap calls in `try/catch` to prevent reverts from bricking your contract.

## How It Works

1. **Fund** - anyone sends EPIX to the contract via a plain transfer
2. **Claim** - each address calls `claim()` once to receive their share
3. **Amount** - 0.1% of pool balance (1% with xID), capped at 1,000 EPIX (10,000 with xID)
4. **Minimum** - claims below 1 EPIX are rejected ("pool exhausted")

The pool naturally decays - each claim takes a small percentage, so early claimers get more but the pool never fully empties.

| Parameter | Value |
|-----------|-------|
| Base rate | 0.1% of pool (10 bps) |
| xID boost | 10x (1% of pool) |
| Max claim (no xID) | 1,000 EPIX |
| Max claim (with xID) | 10,000 EPIX |
| Min claim | 1 EPIX |
| Claims per address | 1 |

## Usage

```solidity
// Fund the pool
(bool ok,) = address(airdrop).call{value: 100_000 ether}("");

// Check estimated claim amount
(uint256 amount, bool xidBoosted) = airdrop.estimateClaim(myAddress);

// Claim (one time only)
airdrop.claim();

// Read pool info
IEpixAirdrop.PoolInfo memory info = airdrop.getPoolInfo();

// Read claimer info (includes xID name)
IEpixAirdrop.ClaimerInfo memory ci = airdrop.getClaimerInfo(myAddress);

// Recent claims feed (last 5, most recent first)
IEpixAirdrop.RecentClaim[] memory claims = airdrop.getRecentClaims();
```

## Development

```bash
forge build       # Compile
forge test -vvv   # Run tests
forge fmt         # Format
```

## Deployment

```bash
# Set up .env with PRIVATE_KEY, RPC_URL, and EXPLORER_URL
cp .env.example .env

# Deploy
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast

# Verify on Blockscout
./verify.sh <contract_address> EpixAirdrop
```

## License

MIT
