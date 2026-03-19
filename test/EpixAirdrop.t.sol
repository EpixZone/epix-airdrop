// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {EpixAirdrop} from "../src/EpixAirdrop.sol";
import {IEpixAirdrop} from "../src/IEpixAirdrop.sol";
import {XID_PRECOMPILE_ADDRESS} from "../src/IXID.sol";
import {MockXID} from "./mocks/MockXID.sol";

contract EpixAirdropTest is Test {
    EpixAirdrop airdrop;
    MockXID mockXid;

    address claimer1 = address(0x1001);
    address claimer2 = address(0x1002);
    address claimer3 = address(0x1003);
    address claimerNoXid = address(0x2001);
    address funder = address(0x3001);

    function setUp() public {
        // Deploy mock xID and etch to precompile address
        mockXid = new MockXID();
        vm.etch(XID_PRECOMPILE_ADDRESS, address(mockXid).code);

        // Register xIDs
        MockXID xid = MockXID(XID_PRECOMPILE_ADDRESS);
        xid.setResolution("alice", "epix", claimer1);
        xid.setResolution("bob", "epix", claimer2);
        xid.setResolution("charlie", "epix", claimer3);

        airdrop = new EpixAirdrop();

        // Fund accounts for gas
        vm.deal(claimer1, 1 ether);
        vm.deal(claimer2, 1 ether);
        vm.deal(claimer3, 1 ether);
        vm.deal(claimerNoXid, 1 ether);
        vm.deal(funder, 10_000_000 ether);
    }

    // -----------------------------------------------------------------------
    //  Funding
    // -----------------------------------------------------------------------

    function test_fund_receive() public {
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 100 ether}("");
        assertTrue(ok);
        assertEq(address(airdrop).balance, 100 ether);
    }

    function test_fund_fallback_reverts() public {
        // fallback() was removed (F-09) — only receive() accepts EPIX
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 50 ether}(hex"1234");
        assertFalse(ok);
    }

    function test_fund_emitsEvent() public {
        vm.prank(funder);
        vm.expectEmit(true, false, false, true, address(airdrop));
        emit IEpixAirdrop.Funded(funder, 200 ether);
        (bool ok,) = address(airdrop).call{value: 200 ether}("");
        assertTrue(ok);
    }

    function test_fund_zeroReverts() public {
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 0}("");
        assertFalse(ok);
    }

    // -----------------------------------------------------------------------
    //  Claiming - basic
    // -----------------------------------------------------------------------

    function test_claim_noXid_basicAmount() public {
        // Fund pool with 100,000 EPIX
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 100_000 ether}("");
        assertTrue(ok);

        // No xID: 100,000 * 10 / 10,000 = 100 EPIX
        uint256 balBefore = claimerNoXid.balance;
        vm.prank(claimerNoXid);
        airdrop.claim();
        uint256 received = claimerNoXid.balance - balBefore;
        assertEq(received, 100 ether);
    }

    function test_claim_withXid_boostedAmount() public {
        // Fund pool with 100,000 EPIX
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 100_000 ether}("");
        assertTrue(ok);

        // With xID: 100,000 * 10 * 10 / 10,000 = 1,000 EPIX
        uint256 balBefore = claimer1.balance;
        vm.prank(claimer1);
        airdrop.claim();
        uint256 received = claimer1.balance - balBefore;
        assertEq(received, 1_000 ether);
    }

    // -----------------------------------------------------------------------
    //  Claiming - one claim per address
    // -----------------------------------------------------------------------

    function test_claim_revertsOnSecondClaim() public {
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 100_000 ether}("");
        assertTrue(ok);

        vm.prank(claimer1);
        airdrop.claim();

        vm.prank(claimer1);
        vm.expectRevert("Already claimed");
        airdrop.claim();
    }

    function test_claim_differentAddressesCanClaim() public {
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 100_000 ether}("");
        assertTrue(ok);

        vm.prank(claimer1);
        airdrop.claim();

        vm.prank(claimer2);
        airdrop.claim();

        vm.prank(claimerNoXid);
        airdrop.claim();

        IEpixAirdrop.PoolInfo memory info = airdrop.getPoolInfo();
        assertEq(info.totalClaimers, 3);
    }

    // -----------------------------------------------------------------------
    //  Claiming - caps
    // -----------------------------------------------------------------------

    function test_claim_noXid_cappedAt1000() public {
        // Fund with 5M EPIX - 0.1% = 5,000, but cap is 1,000
        vm.deal(funder, 5_000_000 ether);
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 5_000_000 ether}("");
        assertTrue(ok);

        uint256 balBefore = claimerNoXid.balance;
        vm.prank(claimerNoXid);
        airdrop.claim();
        uint256 received = claimerNoXid.balance - balBefore;
        assertEq(received, 1_000 ether);
    }

    function test_claim_withXid_cappedAt10000() public {
        // Fund with 5M EPIX - 1% = 50,000, but cap is 10,000
        vm.deal(funder, 5_000_000 ether);
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 5_000_000 ether}("");
        assertTrue(ok);

        uint256 balBefore = claimer1.balance;
        vm.prank(claimer1);
        airdrop.claim();
        uint256 received = claimer1.balance - balBefore;
        assertEq(received, 10_000 ether);
    }

    function test_claim_billionPool_stillCapped() public {
        // 1 billion EPIX pool - should still cap at 1,000 / 10,000
        vm.deal(funder, 1_000_000_000 ether);
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 1_000_000_000 ether}("");
        assertTrue(ok);

        uint256 balBefore = claimerNoXid.balance;
        vm.prank(claimerNoXid);
        airdrop.claim();
        assertEq(claimerNoXid.balance - balBefore, 1_000 ether);

        balBefore = claimer1.balance;
        vm.prank(claimer1);
        airdrop.claim();
        assertEq(claimer1.balance - balBefore, 10_000 ether);
    }

    // -----------------------------------------------------------------------
    //  Claiming - minimum / pool exhausted
    // -----------------------------------------------------------------------

    function test_claim_revertsWhenBelowMinimum() public {
        // Fund with 999 EPIX - 0.1% = 0.999, below 1 EPIX minimum
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 999 ether}("");
        assertTrue(ok);

        vm.prank(claimerNoXid);
        vm.expectRevert("Pool exhausted");
        airdrop.claim();
    }

    function test_claim_xidCanStillClaimWhenNoXidCannot() public {
        // Fund with 500 EPIX - no xID: 0.5 EPIX (too low), xID: 5 EPIX (ok)
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 500 ether}("");
        assertTrue(ok);

        vm.prank(claimerNoXid);
        vm.expectRevert("Pool exhausted");
        airdrop.claim();

        uint256 balBefore = claimer1.balance;
        vm.prank(claimer1);
        airdrop.claim();
        assertEq(claimer1.balance - balBefore, 5 ether);
    }

    function test_claim_exactMinimum() public {
        // Fund with 1,000 EPIX - 0.1% = 1 EPIX, exactly the minimum
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 1_000 ether}("");
        assertTrue(ok);

        uint256 balBefore = claimerNoXid.balance;
        vm.prank(claimerNoXid);
        airdrop.claim();
        assertEq(claimerNoXid.balance - balBefore, 1 ether);
    }

    // -----------------------------------------------------------------------
    //  Claiming - pool drains across multiple addresses
    // -----------------------------------------------------------------------

    function test_claim_poolDrainsAcrossClaimers() public {
        // Fund with 10,000 EPIX, multiple different addresses claim
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 10_000 ether}("");
        assertTrue(ok);

        // claimer1 (xID): 10,000 * 1% = 100 EPIX
        vm.prank(claimer1);
        airdrop.claim();
        uint256 poolAfter1 = address(airdrop).balance;
        assertEq(poolAfter1, 9_900 ether);

        // claimerNoXid: 9,900 * 0.1% = 9.9 EPIX
        vm.prank(claimerNoXid);
        airdrop.claim();
        uint256 poolAfter2 = address(airdrop).balance;
        assertEq(poolAfter2, 9_900 ether - 9.9 ether);

        // Each subsequent claim is smaller
        assertTrue(poolAfter1 - poolAfter2 < 100 ether);
    }

    // -----------------------------------------------------------------------
    //  Claiming - multiple claimers
    // -----------------------------------------------------------------------

    function test_claim_multipleClaymers() public {
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 50_000 ether}("");
        assertTrue(ok);

        // claimer1 (xID): 50,000 * 1% = 500
        vm.prank(claimer1);
        airdrop.claim();

        // claimerNoXid: (50,000 - 500) * 0.1% = 49.5
        vm.prank(claimerNoXid);
        airdrop.claim();

        // claimer2 (xID): remaining * 1%
        vm.prank(claimer2);
        airdrop.claim();

        IEpixAirdrop.PoolInfo memory info = airdrop.getPoolInfo();
        assertEq(info.totalClaimers, 3);
        assertTrue(info.totalClaimed > 0);
        assertTrue(info.balance < 50_000 ether);
    }

    // -----------------------------------------------------------------------
    //  Claiming - emits event
    // -----------------------------------------------------------------------

    function test_claim_emitsEvent_noXid() public {
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 10_000 ether}("");
        assertTrue(ok);

        vm.prank(claimerNoXid);
        vm.expectEmit(true, false, false, true, address(airdrop));
        emit IEpixAirdrop.Claimed(claimerNoXid, 10 ether, false);
        airdrop.claim();
    }

    function test_claim_emitsEvent_withXid() public {
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 10_000 ether}("");
        assertTrue(ok);

        vm.prank(claimer1);
        vm.expectEmit(true, false, false, true, address(airdrop));
        emit IEpixAirdrop.Claimed(claimer1, 100 ether, true);
        airdrop.claim();
    }

    // -----------------------------------------------------------------------
    //  estimateClaim
    // -----------------------------------------------------------------------

    function test_estimateClaim_noXid() public {
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 50_000 ether}("");
        assertTrue(ok);

        (uint256 amount, bool boosted) = airdrop.estimateClaim(claimerNoXid);
        assertEq(amount, 50 ether); // 50,000 * 0.1%
        assertFalse(boosted);
    }

    function test_estimateClaim_withXid() public {
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 50_000 ether}("");
        assertTrue(ok);

        (uint256 amount, bool boosted) = airdrop.estimateClaim(claimer1);
        assertEq(amount, 500 ether); // 50,000 * 1%
        assertTrue(boosted);
    }

    function test_estimateClaim_returnsZeroWhenExhausted() public {
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 500 ether}("");
        assertTrue(ok);

        (uint256 amount,) = airdrop.estimateClaim(claimerNoXid);
        assertEq(amount, 0); // 500 * 0.1% = 0.5, below 1 EPIX
    }

    function test_estimateClaim_capped() public {
        vm.deal(funder, 1_000_000_000 ether);
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 1_000_000_000 ether}("");
        assertTrue(ok);

        (uint256 amountNoXid,) = airdrop.estimateClaim(claimerNoXid);
        assertEq(amountNoXid, 1_000 ether);

        (uint256 amountXid,) = airdrop.estimateClaim(claimer1);
        assertEq(amountXid, 10_000 ether);
    }

    function test_estimateClaim_returnsZeroAfterClaimed() public {
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 100_000 ether}("");
        assertTrue(ok);

        (uint256 amountBefore,) = airdrop.estimateClaim(claimer1);
        assertTrue(amountBefore > 0);

        vm.prank(claimer1);
        airdrop.claim();

        (uint256 amountAfter,) = airdrop.estimateClaim(claimer1);
        assertEq(amountAfter, 0);
    }

    // -----------------------------------------------------------------------
    //  getPoolInfo
    // -----------------------------------------------------------------------

    function test_getPoolInfo_initial() public view {
        IEpixAirdrop.PoolInfo memory info = airdrop.getPoolInfo();
        assertEq(info.balance, 0);
        assertEq(info.totalClaimed, 0);
        assertEq(info.totalClaimers, 0);
        assertEq(info.claimRateBps, 10);
        assertEq(info.maxClaim, 1_000 ether);
        assertEq(info.maxClaimXid, 10_000 ether);
        assertEq(info.minClaim, 1 ether);
        assertEq(info.xidMultiplier, 10);
    }

    function test_getPoolInfo_afterClaims() public {
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 10_000 ether}("");
        assertTrue(ok);

        vm.prank(claimer1);
        airdrop.claim();

        IEpixAirdrop.PoolInfo memory info = airdrop.getPoolInfo();
        assertEq(info.balance, 9_900 ether); // 10,000 - 100 (xID: 1%)
        assertEq(info.totalClaimed, 100 ether);
        assertEq(info.totalClaimers, 1);
    }

    function test_getPoolInfo_totalClaimers() public {
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 100_000 ether}("");
        assertTrue(ok);

        vm.prank(claimer1);
        airdrop.claim();
        vm.prank(claimer2);
        airdrop.claim();
        vm.prank(claimerNoXid);
        airdrop.claim();

        IEpixAirdrop.PoolInfo memory info = airdrop.getPoolInfo();
        assertEq(info.totalClaimers, 3);
    }

    // -----------------------------------------------------------------------
    //  getClaimerInfo
    // -----------------------------------------------------------------------

    function test_getClaimerInfo_neverClaimed() public view {
        IEpixAirdrop.ClaimerInfo memory ci = airdrop.getClaimerInfo(claimerNoXid);
        assertEq(ci.amountClaimed, 0);
        assertEq(ci.claimTime, 0);
        assertFalse(ci.claimed);
        assertFalse(ci.hasXid);
        assertEq(ci.xidName, "");
    }

    function test_getClaimerInfo_withXid() public {
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 10_000 ether}("");
        assertTrue(ok);

        vm.warp(1_700_000_000);
        vm.prank(claimer1);
        airdrop.claim();

        IEpixAirdrop.ClaimerInfo memory ci = airdrop.getClaimerInfo(claimer1);
        assertEq(ci.amountClaimed, 100 ether);
        assertEq(ci.claimTime, 1_700_000_000);
        assertTrue(ci.claimed);
        assertTrue(ci.hasXid);
        assertEq(ci.xidName, "alice.epix");
    }

    function test_getClaimerInfo_noXid() public {
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 10_000 ether}("");
        assertTrue(ok);

        vm.prank(claimerNoXid);
        airdrop.claim();

        IEpixAirdrop.ClaimerInfo memory ci = airdrop.getClaimerInfo(claimerNoXid);
        assertEq(ci.amountClaimed, 10 ether);
        assertTrue(ci.claimed);
        assertFalse(ci.hasXid);
        assertEq(ci.xidName, "");
    }

    // -----------------------------------------------------------------------
    //  getRecentClaims
    // -----------------------------------------------------------------------

    function test_getRecentClaims_empty() public view {
        IEpixAirdrop.RecentClaim[] memory claims = airdrop.getRecentClaims();
        assertEq(claims.length, 0);
    }

    function test_getRecentClaims_oneClaim() public {
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 10_000 ether}("");
        assertTrue(ok);

        vm.warp(1_700_000_000);
        vm.prank(claimer1);
        airdrop.claim();

        IEpixAirdrop.RecentClaim[] memory claims = airdrop.getRecentClaims();
        assertEq(claims.length, 1);
        assertEq(claims[0].claimer, claimer1);
        assertEq(claims[0].amount, 100 ether);
        assertEq(claims[0].timestamp, 1_700_000_000);
        assertTrue(claims[0].xidBoosted);
        assertEq(claims[0].xidName, "alice.epix");
    }

    function test_getRecentClaims_mostRecentFirst() public {
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 100_000 ether}("");
        assertTrue(ok);

        vm.warp(1000);
        vm.prank(claimer1);
        airdrop.claim();

        vm.warp(2000);
        vm.prank(claimerNoXid);
        airdrop.claim();

        vm.warp(3000);
        vm.prank(claimer2);
        airdrop.claim();

        IEpixAirdrop.RecentClaim[] memory claims = airdrop.getRecentClaims();
        assertEq(claims.length, 3);
        // Most recent first
        assertEq(claims[0].claimer, claimer2);
        assertEq(claims[0].timestamp, 3000);
        assertEq(claims[1].claimer, claimerNoXid);
        assertEq(claims[1].timestamp, 2000);
        assertEq(claims[2].claimer, claimer1);
        assertEq(claims[2].timestamp, 1000);
    }

    function test_getRecentClaims_circularBuffer() public {
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 100_000 ether}("");
        assertTrue(ok);

        // Make 7 claims from different addresses - only last 5 should be kept
        address claimer4 = address(0x1004);
        address claimer5 = address(0x1005);
        address claimer6 = address(0x2006);
        address claimer7 = address(0x2007);
        vm.deal(claimer4, 1 ether);
        vm.deal(claimer5, 1 ether);
        vm.deal(claimer6, 1 ether);
        vm.deal(claimer7, 1 ether);
        // Register xIDs for claimer4 and claimer5
        MockXID xid = MockXID(XID_PRECOMPILE_ADDRESS);
        xid.setResolution("dave", "epix", claimer4);
        xid.setResolution("eve", "epix", claimer5);

        vm.warp(1000);
        vm.prank(claimer1);
        airdrop.claim();
        vm.warp(2000);
        vm.prank(claimer2);
        airdrop.claim();
        vm.warp(3000);
        vm.prank(claimer3);
        airdrop.claim();
        vm.warp(4000);
        vm.prank(claimerNoXid);
        airdrop.claim();
        vm.warp(5000);
        vm.prank(claimer4);
        airdrop.claim();
        vm.warp(6000);
        vm.prank(claimer5);
        airdrop.claim();
        vm.warp(7000);
        vm.prank(claimer6);
        airdrop.claim();

        IEpixAirdrop.RecentClaim[] memory claims = airdrop.getRecentClaims();
        assertEq(claims.length, 5);
        // Most recent first: claims at 7000, 6000, 5000, 4000, 3000
        assertEq(claims[0].claimer, claimer6);
        assertEq(claims[0].timestamp, 7000);
        assertFalse(claims[0].xidBoosted); // claimer6 has no xID
        assertEq(claims[1].claimer, claimer5);
        assertEq(claims[1].timestamp, 6000);
        assertTrue(claims[1].xidBoosted);
        assertEq(claims[1].xidName, "eve.epix");
        assertEq(claims[2].claimer, claimer4);
        assertEq(claims[2].timestamp, 5000);
        assertEq(claims[3].claimer, claimerNoXid);
        assertEq(claims[3].timestamp, 4000);
        assertFalse(claims[3].xidBoosted);
        assertEq(claims[4].claimer, claimer3);
        assertEq(claims[4].timestamp, 3000);
        assertTrue(claims[4].xidBoosted);
        assertEq(claims[4].xidName, "charlie.epix");
    }

    // -----------------------------------------------------------------------
    //  Edge cases
    // -----------------------------------------------------------------------

    function test_claim_emptyPoolReverts() public {
        vm.prank(claimerNoXid);
        vm.expectRevert("Pool exhausted");
        airdrop.claim();
    }

    function test_fund_thenClaimThenFundAgain_stillBlocked() public {
        // Fund, claim, refund - second claim still blocked
        vm.prank(funder);
        (bool ok,) = address(airdrop).call{value: 1_000 ether}("");
        assertTrue(ok);

        vm.prank(claimerNoXid);
        airdrop.claim(); // 1 EPIX

        // Refund the pool
        vm.prank(funder);
        (ok,) = address(airdrop).call{value: 5_000 ether}("");
        assertTrue(ok);

        // Same address cannot claim again even after refund
        vm.prank(claimerNoXid);
        vm.expectRevert("Already claimed");
        airdrop.claim();

        // But a different address can
        vm.prank(claimer1);
        airdrop.claim();
    }
}
