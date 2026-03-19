// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEpixAirdrop} from "./IEpixAirdrop.sol";
import {XID} from "./IXID.sol";

/// @title EpixAirdrop
/// @notice Pool-based airdrop for EPIX. Anyone can fund the pool. Each address
///         may claim only once. Claim amount is proportional to the current pool
///         balance (0.1% base rate). xID holders get a 10x boost.
///         Caps at 1,000 EPIX (10,000 with xID).
///         Claims are rejected when the computed amount falls below 1 EPIX.
contract EpixAirdrop is IEpixAirdrop {
    // -----------------------------------------------------------------------
    //  Constants
    // -----------------------------------------------------------------------

    /// @dev Base claim rate: 10 bps = 0.1% of pool balance.
    uint256 public constant CLAIM_RATE_BPS = 10;

    /// @dev Max claim without xID: 1,000 EPIX.
    uint256 public constant MAX_CLAIM = 1_000 ether;

    /// @dev Max claim with xID: 10,000 EPIX.
    uint256 public constant MAX_CLAIM_XID = 10_000 ether;

    /// @dev Minimum claimable amount: 1 EPIX. Below this the pool is "empty".
    uint256 public constant MIN_CLAIM = 1 ether;

    /// @dev xID holders get 10x the base rate.
    uint256 public constant XID_MULTIPLIER = 10;

    /// @dev BPS denominator.
    uint256 private constant _BPS = 10_000;

    /// @dev Circular buffer size for recent claims.
    uint8 private constant _RECENT_SIZE = 5;

    // -----------------------------------------------------------------------
    //  State
    // -----------------------------------------------------------------------

    /// @dev Reentrancy lock.
    bool private _locked;

    /// @dev Total EPIX claimed across all claims.
    uint256 private _totalClaimed;

    /// @dev Total number of claimers.
    uint32 private _totalClaimers;

    /// @dev Per-address claim tracking.
    struct ClaimerData {
        uint256 amountClaimed;
        uint64 claimTime;
    }

    mapping(address => ClaimerData) private _claimers;

    /// @dev Circular buffer for last 5 claims.
    struct RecentClaimData {
        address claimer;
        uint128 amount;
        uint64 timestamp;
        bool xidBoosted;
    }

    RecentClaimData[5] private _recentClaims;
    uint8 private _recentIndex;
    uint8 private _recentCount;

    // -----------------------------------------------------------------------
    //  Modifiers
    // -----------------------------------------------------------------------

    modifier nonReentrant() {
        require(!_locked, "Reentrant call");
        _locked = true;
        _;
        _locked = false;
    }

    // -----------------------------------------------------------------------
    //  Receive
    // -----------------------------------------------------------------------

    /// @notice Fund the airdrop pool by sending EPIX directly.
    receive() external payable {
        require(msg.value > 0, "Zero funding");
        emit Funded(msg.sender, msg.value);
    }

    // -----------------------------------------------------------------------
    //  Write
    // -----------------------------------------------------------------------

    /// @inheritdoc IEpixAirdrop
    function claim() external nonReentrant {
        ClaimerData storage cd = _claimers[msg.sender];
        require(cd.claimTime == 0, "Already claimed");

        uint256 pool = address(this).balance;
        bool hasXid = _hasXid(msg.sender);

        // Compute claim amount
        uint256 amount;
        if (hasXid) {
            amount = (pool * CLAIM_RATE_BPS * XID_MULTIPLIER) / _BPS;
            if (amount > MAX_CLAIM_XID) amount = MAX_CLAIM_XID;
        } else {
            amount = (pool * CLAIM_RATE_BPS) / _BPS;
            if (amount > MAX_CLAIM) amount = MAX_CLAIM;
        }

        require(amount >= MIN_CLAIM, "Pool exhausted");
        require(amount <= type(uint128).max, "Amount overflow");

        // Update state before transfer
        _totalClaimed += amount;
        _totalClaimers++;
        cd.amountClaimed = amount;
        cd.claimTime = uint64(block.timestamp);

        // Record in recent claims circular buffer
        _recentClaims[_recentIndex] = RecentClaimData({
            claimer: msg.sender, amount: uint128(amount), timestamp: uint64(block.timestamp), xidBoosted: hasXid
        });
        _recentIndex = uint8((_recentIndex + 1) % _RECENT_SIZE);
        if (_recentCount < _RECENT_SIZE) _recentCount++;

        // Transfer
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");

        emit Claimed(msg.sender, amount, hasXid);
    }

    // -----------------------------------------------------------------------
    //  Read
    // -----------------------------------------------------------------------

    /// @inheritdoc IEpixAirdrop
    function getPoolInfo() external view returns (PoolInfo memory info) {
        info = PoolInfo({
            balance: address(this).balance,
            totalClaimed: _totalClaimed,
            totalClaimers: _totalClaimers,
            claimRateBps: CLAIM_RATE_BPS,
            maxClaim: MAX_CLAIM,
            maxClaimXid: MAX_CLAIM_XID,
            minClaim: MIN_CLAIM,
            xidMultiplier: XID_MULTIPLIER
        });
    }

    /// @inheritdoc IEpixAirdrop
    function estimateClaim(address claimer) external view returns (uint256 amount, bool xidBoosted) {
        // Already claimed - return 0
        if (_claimers[claimer].claimTime != 0) return (0, false);

        uint256 pool = address(this).balance;
        xidBoosted = _hasXid(claimer);

        if (xidBoosted) {
            amount = (pool * CLAIM_RATE_BPS * XID_MULTIPLIER) / _BPS;
            if (amount > MAX_CLAIM_XID) amount = MAX_CLAIM_XID;
        } else {
            amount = (pool * CLAIM_RATE_BPS) / _BPS;
            if (amount > MAX_CLAIM) amount = MAX_CLAIM;
        }

        if (amount < MIN_CLAIM) amount = 0;
    }

    /// @inheritdoc IEpixAirdrop
    function getClaimerInfo(address claimer) external view returns (ClaimerInfo memory info) {
        ClaimerData storage cd = _claimers[claimer];

        // Single call to reverseResolve (G-01 fix)
        (string memory name, string memory tld) = _tryReverseResolve(claimer);
        bool hasXid = bytes(name).length > 0;
        string memory xidName = hasXid ? string(abi.encodePacked(name, ".", tld)) : "";

        info = ClaimerInfo({
            amountClaimed: cd.amountClaimed,
            claimTime: cd.claimTime,
            claimed: cd.claimTime != 0,
            hasXid: hasXid,
            xidName: xidName
        });
    }

    /// @inheritdoc IEpixAirdrop
    function getRecentClaims() external view returns (RecentClaim[] memory claims) {
        claims = new RecentClaim[](_recentCount);
        for (uint8 i = 0; i < _recentCount; i++) {
            // Walk backwards from most recent
            uint8 idx = uint8((uint256(_recentIndex) + _RECENT_SIZE - 1 - i) % _RECENT_SIZE);
            RecentClaimData storage rc = _recentClaims[idx];
            string memory xidName = "";
            if (rc.xidBoosted) {
                (string memory name, string memory tld) = _tryReverseResolve(rc.claimer);
                if (bytes(name).length > 0) {
                    xidName = string(abi.encodePacked(name, ".", tld));
                }
            }
            claims[i] = RecentClaim({
                claimer: rc.claimer,
                amount: uint256(rc.amount),
                timestamp: rc.timestamp,
                xidBoosted: rc.xidBoosted,
                xidName: xidName
            });
        }
    }

    // -----------------------------------------------------------------------
    //  Internal
    // -----------------------------------------------------------------------

    /// @dev Check if an address has an xID registered.
    ///      Wraps in try/catch so a precompile failure defaults to false (F-04).
    function _hasXid(address addr) private view returns (bool) {
        (string memory name,) = _tryReverseResolve(addr);
        return bytes(name).length > 0;
    }

    /// @dev Try to reverse-resolve an address via the xID precompile.
    ///      Returns empty strings if the precompile reverts or is unavailable.
    function _tryReverseResolve(address addr) private view returns (string memory name, string memory tld) {
        try XID.reverseResolve(addr) returns (string memory n, string memory t) {
            return (n, t);
        } catch {
            return ("", "");
        }
    }
}
