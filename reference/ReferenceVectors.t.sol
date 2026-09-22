// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {N0PathsEngine} from "../src/N0PathsEngine.sol";
import {IPricingEngine} from "../src/interfaces/IPricingEngine.sol";

/// @title ReferenceVectorsTest
/// @notice Differential tests against the independent TypeScript reference model.
/// @dev Expected values are WAD-scaled versions of reference/vectors.json.
contract ReferenceVectorsTest {
    uint256 internal constant WAD = 1e18;

    // Initial numerical tolerances.
    //
    // These are intentionally explicit. If a test fails, investigate the
    // numerical difference before widening them.
    uint256 internal constant PRICE_REL_TOL = 1e13; // 1e-5
    uint256 internal constant MOMENT_REL_TOL = 1e12; // 1e-6
    uint256 internal constant VARIANCE_ABS_TOL = 1e12; // 1e-6

    N0PathsEngine internal engine;

    function setUp() public {
        engine = new N0PathsEngine();
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

    function _relativeErrorWad(
        uint256 actual,
        uint256 expected
    ) internal pure returns (uint256) {
        if (expected == 0) {
            return actual == 0
                ? 0
                : type(uint256).max;
        }

        uint256 difference =
            _absDiff(actual, expected);

        return
            (difference * WAD) /
            expected;
    }

    function _assertRelative(
        uint256 actual,
        uint256 expected,
        uint256 tolerance,
        string memory message
    ) internal pure {
        require(
            _relativeErrorWad(
                actual,
                expected
            ) <= tolerance,
            message
        );
    }

    function _assertAbsolute(
        uint256 actual,
        uint256 expected,
        uint256 tolerance,
        string memory message
    ) internal pure {
        require(
            _absDiff(actual, expected) <=
                tolerance,
            message
        );
    }

    function _price(
        uint256 spot,
        uint256 strike,
        uint256 volatility,
        int256 rate,
        int256 yield,
        uint256 expiry,
        uint256 observations
    )
        internal
        view
        returns (
            IPricingEngine.PriceResult memory
        )
    {
        IPricingEngine.MarketState memory market =
            IPricingEngine.MarketState({
                spot: spot,
                volatility: volatility,
                riskFreeRate: rate,
                dividendYield: yield
            });

        IPricingEngine.AsianOption memory option =
            IPricingEngine.AsianOption({
                strike: strike,
                timeToExpiry: expiry,
                observations: observations
            });

        return
            engine.priceAsianCall(
                market,
                option
            );
    }

    // -------------------------------------------------------------------------
    // Baseline
    // -------------------------------------------------------------------------

    function testReferenceBaseline()
        public
        view
    {
        IPricingEngine.PriceResult memory result =
            _price(
                100e18,
                100e18,
                60e16,
                4e16,
                0,
                1e18,
                30
            );

        // TypeScript reference:
        //
        // M1    = 102.09496855305899
        // M2    = 11881.73392281763
        // var   = 0.13095064664867465
        // price = 14.968725889379861

        uint256 expectedM1 =
            102094968553058990000;

        uint256 expectedM2 =
            11881733922817630000000;

        uint256 expectedVariance =
            130950646648674650;

        uint256 expectedPrice =
            14968725889379861000;

        _assertRelative(
            result.distribution.firstMoment,
            expectedM1,
            MOMENT_REL_TOL,
            "baseline M1 mismatch"
        );

        _assertRelative(
            result.distribution.secondMoment,
            expectedM2,
            MOMENT_REL_TOL,
            "baseline M2 mismatch"
        );

        _assertAbsolute(
            result.distribution.effectiveVariance,
            expectedVariance,
            VARIANCE_ABS_TOL,
            "baseline variance mismatch"
        );

        _assertRelative(
            result.price,
            expectedPrice,
            PRICE_REL_TOL,
            "baseline price mismatch"
        );
    }

    // -------------------------------------------------------------------------
    // Low volatility
    // -------------------------------------------------------------------------

    function testReferenceLowVolatility()
        public
        view
    {
        IPricingEngine.PriceResult memory result =
            _price(
                100e18,
                100e18,
                20e16,
                4e16,
                0,
                1e18,
                30
            );

        uint256 expectedM1 =
            102094968553058990000;

        uint256 expectedM2 =
            10572300352013683000000;

        uint256 expectedVariance =
            14185796744935138;

        uint256 expectedPrice =
            5686345756032494000;

        _assertRelative(
            result.distribution.firstMoment,
            expectedM1,
            MOMENT_REL_TOL,
            "low-vol M1 mismatch"
        );

        _assertRelative(
            result.distribution.secondMoment,
            expectedM2,
            MOMENT_REL_TOL,
            "low-vol M2 mismatch"
        );

        _assertAbsolute(
            result.distribution.effectiveVariance,
            expectedVariance,
            VARIANCE_ABS_TOL,
            "low-vol variance mismatch"
        );

        _assertRelative(
            result.price,
            expectedPrice,
            PRICE_REL_TOL,
            "low-vol price mismatch"
        );
    }

    // -------------------------------------------------------------------------
    // High volatility
    // -------------------------------------------------------------------------

    function testReferenceHighVolatility()
        public
        view
    {
        IPricingEngine.PriceResult memory result =
            _price(
                100e18,
                100e18,
                1e18,
                4e16,
                0,
                1e18,
                30
            );

        uint256 expectedM1 =
            102094968553058990000;

        uint256 expectedM2 =
            15282119308652944000000;

        uint256 expectedVariance =
            382631862596104300;

        uint256 expectedPrice =
            24600889549043360000;

        _assertRelative(
            result.distribution.firstMoment,
            expectedM1,
            MOMENT_REL_TOL,
            "high-vol M1 mismatch"
        );

        _assertRelative(
            result.distribution.secondMoment,
            expectedM2,
            MOMENT_REL_TOL,
            "high-vol M2 mismatch"
        );

        _assertAbsolute(
            result.distribution.effectiveVariance,
            expectedVariance,
            VARIANCE_ABS_TOL,
            "high-vol variance mismatch"
        );

        _assertRelative(
            result.price,
            expectedPrice,
            PRICE_REL_TOL,
            "high-vol price mismatch"
        );
    }

    // -------------------------------------------------------------------------
    // Positive dividend / carry yield
    // -------------------------------------------------------------------------

    function testReferencePositiveYield()
        public
        view
    {
        IPricingEngine.PriceResult memory result =
            _price(
                100e18,
                100e18,
                40e16,
                5e16,
                2e16,
                1e18,
                24
            );

        uint256 expectedM1 =
            101578573342239350000;

        uint256 expectedM2 =
            10932530095392987000000;

        uint256 expectedVariance =
            57832794915154960;

        uint256 expectedPrice =
            9946113406771430000;

        _assertRelative(
            result.distribution.firstMoment,
            expectedM1,
            MOMENT_REL_TOL,
            "yield M1 mismatch"
        );

        _assertRelative(
            result.distribution.secondMoment,
            expectedM2,
            MOMENT_REL_TOL,
            "yield M2 mismatch"
        );

        _assertAbsolute(
            result.distribution.effectiveVariance,
            expectedVariance,
            VARIANCE_ABS_TOL,
            "yield variance mismatch"
        );

        _assertRelative(
            result.price,
            expectedPrice,
            PRICE_REL_TOL,
            "yield price mismatch"
        );
    }

    // -------------------------------------------------------------------------
    // Negative interest rate
    // -------------------------------------------------------------------------

    function testReferenceNegativeRate()
        public
        view
    {
        IPricingEngine.PriceResult memory result =
            _price(
                100e18,
                100e18,
                35e16,
                -1e16,
                0,
                1e18,
                12
            );

        uint256 expectedM1 =
            99460209240472340000;

        uint256 expectedM2 =
            10362099437977706000000;

        uint256 expectedVariance =
            46394829637627893;

        uint256 expectedPrice =
            8369351836373859000;

        _assertRelative(
            result.distribution.firstMoment,
            expectedM1,
            MOMENT_REL_TOL,
            "negative-rate M1 mismatch"
        );

        _assertRelative(
            result.distribution.secondMoment,
            expectedM2,
            MOMENT_REL_TOL,
            "negative-rate M2 mismatch"
        );

        _assertAbsolute(
            result.distribution.effectiveVariance,
            expectedVariance,
            VARIANCE_ABS_TOL,
            "negative-rate variance mismatch"
        );

        _assertRelative(
            result.price,
            expectedPrice,
            PRICE_REL_TOL,
            "negative-rate price mismatch"
        );
    }

    // -------------------------------------------------------------------------
    // Single observation
    // -------------------------------------------------------------------------

    function testReferenceSingleObservation()
        public
        view
    {
        IPricingEngine.PriceResult memory result =
            _price(
                100e18,
                100e18,
                40e16,
                3e16,
                0,
                1e18,
                1
            );

        uint256 expectedM1 =
            103045453395351700000;

        uint256 expectedM2 =
            12460767305873807000000;

        uint256 expectedVariance =
            159999999999999670;

        uint256 expectedPrice =
            17138732604179896000;

        _assertRelative(
            result.distribution.firstMoment,
            expectedM1,
            MOMENT_REL_TOL,
            "single M1 mismatch"
        );

        _assertRelative(
            result.distribution.secondMoment,
            expectedM2,
            MOMENT_REL_TOL,
            "single M2 mismatch"
        );

        _assertAbsolute(
            result.distribution.effectiveVariance,
            expectedVariance,
            VARIANCE_ABS_TOL,
            "single variance mismatch"
        );

        _assertRelative(
            result.price,
            expectedPrice,
            PRICE_REL_TOL,
            "single price mismatch"
        );
    }

    // -------------------------------------------------------------------------
    // Zero volatility
    // -------------------------------------------------------------------------

    function testReferenceZeroVolatility()
        public
        view
    {
        IPricingEngine.PriceResult memory result =
            _price(
                100e18,
                100e18,
                0,
                4e16,
                0,
                1e18,
                30
            );

        uint256 expectedM1 =
            102094968553058990000;

        uint256 expectedPrice =
            2012823661135301000;

        _assertRelative(
            result.distribution.firstMoment,
            expectedM1,
            MOMENT_REL_TOL,
            "zero-vol M1 mismatch"
        );

        /*
         * The mathematical reference variance is exactly zero.
         *
         * Fixed-point summation can introduce a tiny M2 vs M1^2
         * discrepancy. This assertion is deliberately strict enough
         * to expose that behavior rather than hiding it.
         */
        _assertAbsolute(
            result.distribution.effectiveVariance,
            0,
            VARIANCE_ABS_TOL,
            "zero-vol variance mismatch"
        );

        _assertRelative(
            result.price,
            expectedPrice,
            PRICE_REL_TOL,
            "zero-vol price mismatch"
        );
    }
}
