// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IEpixAirdrop
/// @notice Interface for the Epix Airdrop contract.
///         Pool-based airdrop where claim amount is proportional to pool balance.
///         xID holders get a 10x boost. Anyone can fund the pool.
interface IEpixAirdrop {
    // -----------------------------------------------------------------------
    //  Structs
    // -----------------------------------------------------------------------

    /// @notice Info about the airdrop pool state.
    struct PoolInfo {
        uint256 balance;
        uint256 totalClaimed;
        uint32 totalClaimers;
        uint256 claimRateBps;
        uint256 maxClaim;
        uint256 maxClaimXid;
        uint256 minClaim;
        uint256 xidMultiplier;
    }

    /// @notice Info about a claimer's history.
    struct ClaimerInfo {
        uint256 amountClaimed;
        uint64 claimTime;
        bool claimed;
        bool hasXid;
        string xidName;
    }

    /// @notice A recent claim entry.
    struct RecentClaim {
        address claimer;
        uint256 amount;
        uint64 timestamp;
        bool xidBoosted;
        string xidName;
    }

    // -----------------------------------------------------------------------
    //  Events
    // -----------------------------------------------------------------------

    /// @notice Emitted when someone claims the airdrop.
    event Claimed(address indexed claimer, uint256 amount, bool xidBoosted);

    /// @notice Emitted when someone funds the pool.
    event Funded(address indexed funder, uint256 amount);

    // -----------------------------------------------------------------------
    //  Write Functions
    // -----------------------------------------------------------------------

    /// @notice Claim an airdrop. Each address may claim only once.
    ///         Amount is proportional to pool balance.
    ///         xID holders receive a 10x multiplier on the base claim rate.
    function claim() external;

    // -----------------------------------------------------------------------
    //  Read Functions
    // -----------------------------------------------------------------------

    /// @notice Get the current pool state.
    function getPoolInfo() external view returns (PoolInfo memory info);

    /// @notice Get the estimated claim amount for an address.
    /// @param claimer The address to check
    /// @return amount The estimated claim amount (0 if below minimum)
    /// @return xidBoosted Whether the xID boost would apply
    function estimateClaim(address claimer) external view returns (uint256 amount, bool xidBoosted);

    /// @notice Get info about a claimer.
    /// @param claimer The address to look up
    /// @return info The claimer's stats
    function getClaimerInfo(address claimer) external view returns (ClaimerInfo memory info);

    /// @notice Get the last 5 recent claims.
    /// @return claims Array of recent claims (most recent first), may be shorter than 5
    function getRecentClaims() external view returns (RecentClaim[] memory claims);
}
