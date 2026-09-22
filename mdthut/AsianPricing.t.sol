// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AsianPricing} from "../src/libraries/AsianPricing.sol";
import {FixedPointMath} from "../src/libraries/FixedPointMath.sol";
import {TranscendentalMath} from "../src/libraries/TranscendentalMath.sol";
import {NormalDistribution} from "../src/libraries/NormalDistribution.sol";

/// @notice Exposes AsianPricing for isolated unit testing.
contract AsianPricingHarness {
    function priceCall(
        uint256 spot,
        uint256 strike,
        uint256 volatility,
        int256 riskFreeRate,
        int256 dividendYield,
        uint256 timeToExpiry,
        uint256 observations
    )
        external
        pure
        returns (AsianPricing.PricingResult memory)
    {
        return AsianPricing.priceCall(
            spot,
            strike,
            volatility,
            riskFreeRate,
            dividendYield,
            timeToExpiry,
            observations
        );
    }
}

/// @title AsianPricingTest
/// @notice Tests the moment-matched arithmetic Asian pricing layer.
contract AsianPricingTest {
    uint256 internal constant WAD = 1e18;

    AsianPricingHarness internal pricing;

    function setUp() public {
        pricing = new AsianPricingHarness();
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _absDiff(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return a >= b ? a - b : b - a;
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

    function _defaultPrice()
        internal
        view
        returns (AsianPricing.PricingResult memory)
    {
        return pricing.priceCall(
            100e18,
            100e18,
            60e16,
            4e16,
            0,
            1e18,
            30
        );
    }

    // -------------------------------------------------------------------------
    // Basic result sanity
    // -------------------------------------------------------------------------

    function testPriceIsPositiveForBaseline()
        public
        view
    {
        AsianPricing.PricingResult memory result =
            _defaultPrice();

        require(
            result.price > 0,
            "baseline price should be positive"
        );
    }

    function testUndiscountedPayoffAtLeastPrice()
        public
        view
    {
        AsianPricing.PricingResult memory result =
            _defaultPrice();

        // Baseline r > 0, therefore discount factor < 1.
        require(
            result.undiscountedPayoff >= result.price,
            "discounted price exceeds payoff"
        );
    }

    function testDiscountFactorIsValid()
        public
        view
    {
        AsianPricing.PricingResult memory result =
            _defaultPrice();

        require(
            result.discountFactor > 0,
            "discount factor must be positive"
        );

        require(
            result.discountFactor < WAD,
            "positive rate should discount"
        );
    }

    function testEffectiveVarianceIsPositive()
        public
        view
    {
        AsianPricing.PricingResult memory result =
            _defaultPrice();

        require(
            result.effectiveVariance > 0,
            "variance should be positive"
        );
    }

    function testD1GreaterThanD2()
        public
        view
    {
        AsianPricing.PricingResult memory result =
            _defaultPrice();

        require(
            result.d1 > result.d2,
            "d1 must exceed d2"
        );
    }

    // -------------------------------------------------------------------------
    // Strike monotonicity
    // -------------------------------------------------------------------------

    function testPriceFallsAsStrikeRises()
        public
        view
    {
        uint256 lowStrikePrice =
            pricing.priceCall(
                100e18,
                80e18,
                60e16,
                4e16,
                0,
                1e18,
                30
            ).price;

        uint256 atmPrice =
            pricing.priceCall(
                100e18,
                100e18,
                60e16,
                4e16,
                0,
                1e18,
                30
            ).price;

        uint256 highStrikePrice =
            pricing.priceCall(
                100e18,
                120e18,
                60e16,
                4e16,
                0,
                1e18,
                30
            ).price;

        require(
            lowStrikePrice >= atmPrice,
            "80 strike below ATM price"
        );

        require(
            atmPrice >= highStrikePrice,
            "ATM below 120 strike price"
        );
    }

    // -------------------------------------------------------------------------
    // Spot monotonicity
    // -------------------------------------------------------------------------

    function testPriceRisesAsSpotRises()
        public
        view
    {
        uint256 low =
            pricing.priceCall(
                80e18,
                100e18,
                60e16,
                4e16,
                0,
                1e18,
                30
            ).price;

        uint256 mid =
            pricing.priceCall(
                100e18,
                100e18,
                60e16,
                4e16,
                0,
                1e18,
                30
            ).price;

        uint256 high =
            pricing.priceCall(
                120e18,
                100e18,
                60e16,
                4e16,
                0,
                1e18,
                30
            ).price;

        require(
            low <= mid,
            "price not increasing with spot"
        );

        require(
            mid <= high,
            "price not increasing with spot"
        );
    }

    // -------------------------------------------------------------------------
    // Volatility
    // -------------------------------------------------------------------------

    function testPriceRisesWithVolatility()
        public
        view
    {
        uint256 low =
            pricing.priceCall(
                100e18,
                100e18,
                20e16,
                4e16,
                0,
                1e18,
                30
            ).price;

        uint256 high =
            pricing.priceCall(
                100e18,
                100e18,
                80e16,
                4e16,
                0,
                1e18,
                30
            ).price;

        require(
            high >= low,
            "call price fell with volatility"
        );
    }

    // -------------------------------------------------------------------------
    // Zero-volatility branch
    // -------------------------------------------------------------------------

    function testZeroVolZeroDriftATMIsWorthZero()
        public
        view
    {
        AsianPricing.PricingResult memory result =
            pricing.priceCall(
                100e18,
                100e18,
                0,
                0,
                0,
                1e18,
                30
            );

        require(
            result.effectiveVariance == 0,
            "variance should be zero"
        );

        require(
            result.undiscountedPayoff == 0,
            "ATM deterministic payoff should be zero"
        );

        require(
            result.price == 0,
            "ATM deterministic price should be zero"
        );
    }

    function testZeroVolDeterministicITM()
        public
        view
    {
        AsianPricing.PricingResult memory result =
            pricing.priceCall(
                100e18,
                80e18,
                0,
                0,
                0,
                1e18,
                30
            );

        require(
            result.effectiveVariance == 0,
            "variance should be zero"
        );

        require(
            result.undiscountedPayoff == 20e18,
            "incorrect deterministic payoff"
        );

        require(
            result.price == 20e18,
            "incorrect deterministic price"
        );
    }

    // -------------------------------------------------------------------------
    // Single observation = European call
    // -------------------------------------------------------------------------

    function testSingleObservationMatchesEuropeanCall()
        public
        view
    {
        uint256 spot = 100e18;
        uint256 strike = 100e18;
        uint256 sigma = 40e16;
        int256 rate = 3e16;
        int256 yield = 1e16;
        uint256 expiry = 1e18;

        AsianPricing.PricingResult memory asian =
            pricing.priceCall(
                spot,
                strike,
                sigma,
                rate,
                yield,
                expiry,
                1
            );

        uint256 european = _europeanCall(
            spot,
            strike,
            sigma,
            rate,
            yield,
            expiry
        );

        // Both calculations use the same fixed-point exp/CDF primitives.
        // Only tiny rounding differences should remain.
        _assertApprox(
            asian.price,
            european,
            100_000,
            "n=1 should match European call"
        );
    }

    /// @dev Black-Scholes-style European call under continuous carry:
    ///
    ///      C =
    ///          S exp(-qT) Phi(d1)
    ///        - K exp(-rT) Phi(d2)
    ///
    ///      d1 =
    ///          [ln(S/K) + (r-q+0.5 sigma^2)T]
    ///          ---------------------------------
    ///                      sigma sqrt(T)
    ///
    ///      d2 = d1 - sigma sqrt(T)
    function _europeanCall(
        uint256 spot,
        uint256 strike,
        uint256 sigma,
        int256 rate,
        int256 yield,
        uint256 expiry
    ) internal pure returns (uint256) {
        uint256 sigmaSquared =
            FixedPointMath.mulWad(
                sigma,
                sigma
            );

        int256 carry =
            rate - yield;

        int256 halfVariance =
            int256(sigmaSquared / 2);

        int256 drift =
            carry + halfVariance;

        int256 driftTime =
            FixedPointMath.mulWadSigned(
                drift,
                int256(expiry)
            );

        uint256 spotStrikeRatio =
            FixedPointMath.divWad(
                spot,
                strike
            );

        int256 logMoneyness =
            TranscendentalMath.ln(
                spotStrikeRatio
            );

        uint256 sqrtT =
            AsianPricing.sqrtWad(
                expiry
            );

        uint256 sigmaSqrtT =
            FixedPointMath.mulWad(
                sigma,
                sqrtT
            );

        int256 d1 =
            FixedPointMath.divWadSigned(
                logMoneyness + driftTime,
                int256(sigmaSqrtT)
            );

        int256 d2 =
            d1 - int256(sigmaSqrtT);

        int256 qT =
            FixedPointMath.mulWadSigned(
                yield,
                int256(expiry)
            );

        int256 rT =
            FixedPointMath.mulWadSigned(
                rate,
                int256(expiry)
            );

        uint256 dividendDiscount =
            TranscendentalMath.exp(-qT);

        uint256 rateDiscount =
            TranscendentalMath.exp(-rT);

        uint256 spotPv =
            FixedPointMath.mulWad(
                spot,
                dividendDiscount
            );

        uint256 strikePv =
            FixedPointMath.mulWad(
                strike,
                rateDiscount
            );

        uint256 assetTerm =
            FixedPointMath.mulWad(
                spotPv,
                NormalDistribution.cdf(d1)
            );

        uint256 strikeTerm =
            FixedPointMath.mulWad(
                strikePv,
                NormalDistribution.cdf(d2)
            );

        if (assetTerm <= strikeTerm) {
            return 0;
        }

        return assetTerm - strikeTerm;
    }

    // -------------------------------------------------------------------------
    // Homogeneity
    // -------------------------------------------------------------------------

    function testPriceScalesWithSpotAndStrike()
        public
        view
    {
        uint256 base =
            pricing.priceCall(
                100e18,
                100e18,
                50e16,
                4e16,
                0,
                1e18,
                24
            ).price;

        uint256 doubled =
            pricing.priceCall(
                200e18,
                200e18,
                50e16,
                4e16,
                0,
                1e18,
                24
            ).price;

        _assertApprox(
            doubled,
            2 * base,
            100_000,
            "price not homogeneous"
        );
    }

    // -------------------------------------------------------------------------
    // Distribution consistency
    // -------------------------------------------------------------------------

    function testFittedDistributionReconstructsM1()
        public
        view
    {
        AsianPricing.PricingResult memory result =
            _defaultPrice();

        // For fitted lognormal:
        //
        // E[A] = exp(mu + variance / 2)

        int256 exponent =
            result.logMean +
            int256(
                result.effectiveVariance / 2
            );

        uint256 reconstructed =
            TranscendentalMath.exp(
                exponent
            );

        _assertApprox(
            reconstructed,
            result.firstMoment,
            100_000,
            "fitted distribution does not reconstruct M1"
        );
    }

    function testFittedDistributionReconstructsM2()
        public
        view
    {
        AsianPricing.PricingResult memory result =
            _defaultPrice();

        // For lognormal X:
        //
        // E[X^2] = exp(2mu + 2variance)

        int256 exponent =
            2 * result.logMean +
            2 * int256(
                result.effectiveVariance
            );

        uint256 reconstructed =
            TranscendentalMath.exp(
                exponent
            );

        _assertApprox(
            reconstructed,
            result.secondMoment,
            1_000_000,
            "fitted distribution does not reconstruct M2"
        );
    }

    // -------------------------------------------------------------------------
    // Invalid input
    // -------------------------------------------------------------------------

    function testZeroStrikeReverts()
        public
    {
        (bool success, ) =
            address(pricing).call(
                abi.encodeCall(
                    pricing.priceCall,
                    (
                        uint256(100e18),
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
            "zero strike must revert"
        );
    }
}
