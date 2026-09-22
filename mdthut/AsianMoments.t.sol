// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AsianMoments} from "../src/libraries/AsianMoments.sol";
import {FixedPointMath} from "../src/libraries/FixedPointMath.sol";
import {TranscendentalMath} from "../src/libraries/TranscendentalMath.sol";

/// @notice Exposes AsianMoments for isolated unit testing.
contract AsianMomentsHarness {
    function compute(
        uint256 spot,
        uint256 volatility,
        int256 riskFreeRate,
        int256 dividendYield,
        uint256 timeToExpiry,
        uint256 observations
    )
        external
        pure
        returns (
            uint256 firstMoment,
            uint256 secondMoment
        )
    {
        AsianMoments.Moments memory moments =
            AsianMoments.compute(
                spot,
                volatility,
                riskFreeRate,
                dividendYield,
                timeToExpiry,
                observations
            );

        return (
            moments.first,
            moments.second
        );
    }
}

/// @title AsianMomentsTest
/// @notice Unit tests for arithmetic-average GBM moments.
contract AsianMomentsTest {
    uint256 internal constant WAD = 1e18;

    AsianMomentsHarness internal moments;

    function setUp() public {
        moments = new AsianMomentsHarness();
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _absDiff(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return a >= b
            ? a - b
            : b - a;
    }

    function _assertApprox(
        uint256 actual,
        uint256 expected,
        uint256 tolerance,
        string memory message
    ) internal pure {
        require(
            _absDiff(actual, expected) <= tolerance,
            message
        );
    }

    // -------------------------------------------------------------------------
    // Basic moment properties
    // -------------------------------------------------------------------------

    function testMomentsArePositive() public view {
        (
            uint256 m1,
            uint256 m2
        ) = moments.compute(
            100e18,
            60e16,
            4e16,
            0,
            1e18,
            30
        );

        require(
            m1 > 0,
            "M1 must be positive"
        );

        require(
            m2 > 0,
            "M2 must be positive"
        );
    }

    function testSecondMomentAtLeastFirstMomentSquared()
        public
        view
    {
        (
            uint256 m1,
            uint256 m2
        ) = moments.compute(
            100e18,
            60e16,
            4e16,
            0,
            1e18,
            30
        );

        uint256 m1Squared =
            FixedPointMath.mulWad(
                m1,
                m1
            );

        require(
            m2 >= m1Squared,
            "M2 must be >= M1^2"
        );
    }

    // -------------------------------------------------------------------------
    // Zero drift
    // -------------------------------------------------------------------------

    function testZeroDriftFirstMomentEqualsSpot()
        public
        view
    {
        (
            uint256 m1,
        ) = moments.compute(
            100e18,
            50e16,
            0,
            0,
            1e18,
            30
        );

        require(
            m1 == 100e18,
            "zero drift should preserve E[A]"
        );
    }

    function testEqualRateAndYieldFirstMomentEqualsSpot()
        public
        view
    {
        (
            uint256 m1,
        ) = moments.compute(
            100e18,
            50e16,
            5e16,
            5e16,
            1e18,
            30
        );

        require(
            m1 == 100e18,
            "r=q should preserve E[A]"
        );
    }

    // -------------------------------------------------------------------------
    // Zero volatility
    // -------------------------------------------------------------------------

    function testZeroVolatilityHasNoMomentVariance()
        public
        view
    {
        (
            uint256 m1,
            uint256 m2
        ) = moments.compute(
            100e18,
            0,
            0,
            0,
            1e18,
            30
        );

        uint256 m1Squared =
            FixedPointMath.mulWad(
                m1,
                m1
            );

        require(
            m1 == 100e18,
            "unexpected deterministic M1"
        );

        require(
            m2 == m1Squared,
            "zero vol should imply M2=M1^2"
        );
    }

    function testZeroVolatilityPositiveDrift()
        public
        view
    {
        (
            uint256 m1,
            uint256 m2
        ) = moments.compute(
            100e18,
            0,
            4e16,
            0,
            1e18,
            12
        );

        require(
            m1 > 100e18,
            "positive drift should raise average"
        );

        uint256 m1Squared =
            FixedPointMath.mulWad(
                m1,
                m1
            );

        /*
         * Important:
         *
         * Even when sigma = 0, observations at different times have
         * different deterministic values when drift != 0.
         *
         * Since A itself is still deterministic:
         *
         *     E[A^2] = E[A]^2
         *
         * Small fixed-point rounding differences are allowed.
         */
        _assertApprox(
            m2,
            m1Squared,
            100_000,
            "deterministic moments inconsistent"
        );
    }

    // -------------------------------------------------------------------------
    // Single-observation limiting case
    // -------------------------------------------------------------------------

    function testSingleObservationFirstMoment()
        public
        view
    {
        uint256 spot = 100e18;
        int256 rate = 4e16;
        uint256 expiry = 1e18;

        (
            uint256 m1,
        ) = moments.compute(
            spot,
            60e16,
            rate,
            0,
            expiry,
            1
        );

        int256 rT =
            FixedPointMath.mulWadSigned(
                rate,
                int256(expiry)
            );

        uint256 expectedGrowth =
            TranscendentalMath.exp(rT);

        uint256 expected =
            FixedPointMath.mulWad(
                spot,
                expectedGrowth
            );

        _assertApprox(
            m1,
            expected,
            10,
            "single-observation M1 incorrect"
        );
    }

    function testSingleObservationSecondMoment()
        public
        view
    {
        uint256 spot = 100e18;
        uint256 sigma = 60e16;
        int256 rate = 4e16;
        uint256 expiry = 1e18;

        (
            ,
            uint256 m2
        ) = moments.compute(
            spot,
            sigma,
            rate,
            0,
            expiry,
            1
        );

        uint256 spotSquared =
            FixedPointMath.mulWad(
                spot,
                spot
            );

        uint256 sigmaSquared =
            FixedPointMath.mulWad(
                sigma,
                sigma
            );

        // For one observation at T:
        //
        // E[S_T^2]
        //
        // = S0^2 * exp(
        //     2(r-q)T + sigma^2 T
        //   )

        int256 rT =
            FixedPointMath.mulWadSigned(
                rate,
                int256(expiry)
            );

        uint256 varianceTime =
            FixedPointMath.mulWad(
                sigmaSquared,
                expiry
            );

        int256 exponent =
            2 * rT +
            int256(varianceTime);

        uint256 growth =
            TranscendentalMath.exp(
                exponent
            );

        uint256 expected =
            FixedPointMath.mulWad(
                spotSquared,
                growth
            );

        _assertApprox(
            m2,
            expected,
            100,
            "single-observation M2 incorrect"
        );
    }

    // -------------------------------------------------------------------------
    // Volatility behavior
    // -------------------------------------------------------------------------

    function testFirstMomentIndependentOfVolatility()
        public
        view
    {
        (
            uint256 lowVolM1,
        ) = moments.compute(
            100e18,
            20e16,
            4e16,
            0,
            1e18,
            30
        );

        (
            uint256 highVolM1,
        ) = moments.compute(
            100e18,
            100e16,
            4e16,
            0,
            1e18,
            30
        );

        require(
            lowVolM1 == highVolM1,
            "M1 should not depend on sigma"
        );
    }

    function testSecondMomentIncreasesWithVolatility()
        public
        view
    {
        (
            ,
            uint256 lowVolM2
        ) = moments.compute(
            100e18,
            20e16,
            4e16,
            0,
            1e18,
            30
        );

        (
            ,
            uint256 highVolM2
        ) = moments.compute(
            100e18,
            80e16,
            4e16,
            0,
            1e18,
            30
        );

        require(
            highVolM2 > lowVolM2,
            "M2 should increase with sigma"
        );
    }

    // -------------------------------------------------------------------------
    // Spot scaling
    // -------------------------------------------------------------------------

    function testFirstMomentScalesLinearlyWithSpot()
        public
        view
    {
        (
            uint256 m1A,
        ) = moments.compute(
            100e18,
            40e16,
            4e16,
            0,
            1e18,
            12
        );

        (
            uint256 m1B,
        ) = moments.compute(
            200e18,
            40e16,
            4e16,
            0,
            1e18,
            12
        );

        _assertApprox(
            m1B,
            2 * m1A,
            10,
            "M1 not linear in spot"
        );
    }

    function testSecondMomentScalesQuadraticallyWithSpot()
        public
        view
    {
        (
            ,
            uint256 m2A
        ) = moments.compute(
            100e18,
            40e16,
            4e16,
            0,
            1e18,
            12
        );

        (
            ,
            uint256 m2B
        ) = moments.compute(
            200e18,
            40e16,
            4e16,
            0,
            1e18,
            12
        );

        _assertApprox(
            m2B,
            4 * m2A,
            100,
            "M2 not quadratic in spot"
        );
    }

    // -------------------------------------------------------------------------
    // Observation count
    // -------------------------------------------------------------------------

    function testObservationCountChangesMoments()
        public
        view
    {
        (
            uint256 m1Single,
            uint256 m2Single
        ) = moments.compute(
            100e18,
            50e16,
            4e16,
            0,
            1e18,
            1
        );

        (
            uint256 m1Many,
            uint256 m2Many
        ) = moments.compute(
            100e18,
            50e16,
            4e16,
            0,
            1e18,
            30
        );

        require(
            m1Single != m1Many,
            "observation schedule should affect M1"
        );

        require(
            m2Single != m2Many,
            "observation schedule should affect M2"
        );
    }

    // -------------------------------------------------------------------------
    // Invalid inputs
    // -------------------------------------------------------------------------

    function testZeroSpotReverts() public {
        (bool success, ) =
            address(moments).call(
                abi.encodeCall(
                    moments.compute,
                    (
                        uint256(0),
                        uint256(50e16),
                        int256(4e16),
                        int256(0),
                        uint256(1e18),
                        uint256(30)
                    )
                )
            );

        require(
            !success,
            "zero spot must revert"
        );
    }

    function testZeroExpiryReverts() public {
        (bool success, ) =
            address(moments).call(
                abi.encodeCall(
                    moments.compute,
                    (
                        uint256(100e18),
                        uint256(50e16),
                        int256(4e16),
                        int256(0),
                        uint256(0),
                        uint256(30)
                    )
                )
            );

        require(
            !success,
            "zero expiry must revert"
        );
    }

    function testZeroObservationsReverts() public {
        (bool success, ) =
            address(moments).call(
                abi.encodeCall(
                    moments.compute,
                    (
                        uint256(100e18),
                        uint256(50e16),
                        int256(4e16),
                        int256(0),
                        uint256(1e18),
                        uint256(0)
                    )
                )
            );

        require(
            !success,
            "zero observations must revert"
        );
    }
}
