// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {N0PathsEngine} from "../src/N0PathsEngine.sol";
import {IPricingEngine} from "../src/interfaces/IPricingEngine.sol";

/// @title N0PathsEngineTest
/// @notice Core behavioral tests for the n0paths pricing engine.
///
/// @dev This file intentionally avoids hard-coding an unverified
///      reference price. Numerical parity tests are added separately
///      against independently generated reference vectors.
contract N0PathsEngineTest {
    uint256 internal constant WAD = 1e18;

    N0PathsEngine internal engine;

    function setUp() public {
        engine = new N0PathsEngine();
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _defaultMarket()
        internal
        pure
        returns (IPricingEngine.MarketState memory)
    {
        return IPricingEngine.MarketState({
            spot: 100e18,
            volatility: 60e16, // 60%
            riskFreeRate: 4e16, // 4%
            dividendYield: 0
        });
    }

    function _defaultOption()
        internal
        pure
        returns (IPricingEngine.AsianOption memory)
    {
        return IPricingEngine.AsianOption({
            strike: 100e18,
            timeToExpiry: 1e18,
            observations: 30
        });
    }

    function _price(
        IPricingEngine.MarketState memory market,
        IPricingEngine.AsianOption memory option
    ) internal view returns (uint256) {
        return engine.price(market, option);
    }

    // -------------------------------------------------------------------------
    // Metadata
    // -------------------------------------------------------------------------

    function testScaleIsWad() public view {
        require(
            engine.scale() == WAD,
            "unexpected fixed-point scale"
        );
    }

    function testVersionIsSet() public view {
        bytes memory version = bytes(engine.version());

        require(
            version.length != 0,
            "version must not be empty"
        );
    }

    // -------------------------------------------------------------------------
    // Determinism
    // -------------------------------------------------------------------------

    function testSameInputsProduceSamePrice() public view {
        IPricingEngine.MarketState memory market =
            _defaultMarket();

        IPricingEngine.AsianOption memory option =
            _defaultOption();

        uint256 first = _price(market, option);
        uint256 second = _price(market, option);
        uint256 third = _price(market, option);

        require(first == second, "price changed");
        require(second == third, "price changed");
    }

    function testSameInputsProduceSameFullResult() public view {
        IPricingEngine.MarketState memory market =
            _defaultMarket();

        IPricingEngine.AsianOption memory option =
            _defaultOption();

        IPricingEngine.PriceResult memory a =
            engine.priceAsianCall(market, option);

        IPricingEngine.PriceResult memory b =
            engine.priceAsianCall(market, option);

        require(a.price == b.price, "price mismatch");

        require(
            a.undiscountedPayoff == b.undiscountedPayoff,
            "payoff mismatch"
        );

        require(
            a.discountFactor == b.discountFactor,
            "discount mismatch"
        );

        require(
            a.distribution.firstMoment ==
                b.distribution.firstMoment,
            "M1 mismatch"
        );

        require(
            a.distribution.secondMoment ==
                b.distribution.secondMoment,
            "M2 mismatch"
        );

        require(
            a.distribution.effectiveVariance ==
                b.distribution.effectiveVariance,
            "variance mismatch"
        );

        require(
            a.distribution.logMean ==
                b.distribution.logMean,
            "log mean mismatch"
        );
    }

    // -------------------------------------------------------------------------
    // Basic pricing behavior
    // -------------------------------------------------------------------------

    function testPriceIsNonNegative() public view {
        IPricingEngine.MarketState memory market =
            _defaultMarket();

        IPricingEngine.AsianOption memory option =
            _defaultOption();

        uint256 value = _price(market, option);

        // uint256 already guarantees non-negativity.
        // This assertion also ensures the call completes successfully.
        require(
            value <= type(uint256).max,
            "unreachable"
        );
    }

    function testPriceDecreasesWhenStrikeIncreases() public view {
        IPricingEngine.MarketState memory market =
            _defaultMarket();

        IPricingEngine.AsianOption memory lowStrike =
            _defaultOption();

        IPricingEngine.AsianOption memory highStrike =
            _defaultOption();

        lowStrike.strike = 90e18;
        highStrike.strike = 110e18;

        uint256 lowStrikePrice =
            _price(market, lowStrike);

        uint256 highStrikePrice =
            _price(market, highStrike);

        require(
            lowStrikePrice >= highStrikePrice,
            "price must decrease with strike"
        );
    }

    function testPriceIncreasesWhenSpotIncreases() public view {
        IPricingEngine.MarketState memory lowSpot =
            _defaultMarket();

        IPricingEngine.MarketState memory highSpot =
            _defaultMarket();

        IPricingEngine.AsianOption memory option =
            _defaultOption();

        lowSpot.spot = 90e18;
        highSpot.spot = 110e18;

        uint256 lowSpotPrice =
            _price(lowSpot, option);

        uint256 highSpotPrice =
            _price(highSpot, option);

        require(
            highSpotPrice >= lowSpotPrice,
            "price must increase with spot"
        );
    }

    function testHigherVolatilityDoesNotLowerCallPrice()
        public
        view
    {
        IPricingEngine.MarketState memory lowVol =
            _defaultMarket();

        IPricingEngine.MarketState memory highVol =
            _defaultMarket();

        IPricingEngine.AsianOption memory option =
            _defaultOption();

        lowVol.volatility = 20e16;  // 20%
        highVol.volatility = 80e16; // 80%

        uint256 lowVolPrice =
            _price(lowVol, option);

        uint256 highVolPrice =
            _price(highVol, option);

        require(
            highVolPrice >= lowVolPrice,
            "price decreased with volatility"
        );
    }

    // -------------------------------------------------------------------------
    // Zero-volatility behavior
    // -------------------------------------------------------------------------

    function testZeroVolatilityIsDeterministic() public view {
        IPricingEngine.MarketState memory market =
            _defaultMarket();

        IPricingEngine.AsianOption memory option =
            _defaultOption();

        market.volatility = 0;

        uint256 first = _price(market, option);
        uint256 second = _price(market, option);

        require(
            first == second,
            "zero-vol price changed"
        );
    }

    function testZeroVolatilityProducesZeroEffectiveVariance()
        public
        view
    {
        IPricingEngine.MarketState memory market =
            _defaultMarket();

        IPricingEngine.AsianOption memory option =
            _defaultOption();

        market.volatility = 0;

        IPricingEngine.PriceResult memory result =
            engine.priceAsianCall(market, option);

        // Fixed-point rounding can theoretically leave a microscopic
        // residual in later implementations. The current implementation
        // should resolve to exactly zero for this scenario.
        require(
            result.distribution.effectiveVariance == 0,
            "zero vol should imply zero fitted variance"
        );
    }

    // -------------------------------------------------------------------------
    // Distribution sanity
    // -------------------------------------------------------------------------

    function testSecondMomentAtLeastSquareOfFirstMoment()
        public
        view
    {
        IPricingEngine.MarketState memory market =
            _defaultMarket();

        IPricingEngine.AsianOption memory option =
            _defaultOption();

        IPricingEngine.PriceResult memory result =
            engine.priceAsianCall(market, option);

        uint256 m1 = result.distribution.firstMoment;
        uint256 m2 = result.distribution.secondMoment;

        uint256 m1Squared = (m1 * m1) / WAD;

        require(
            m2 >= m1Squared,
            "invalid moment relationship"
        );
    }

    function testDiscountFactorBelowOneForPositiveRate()
        public
        view
    {
        IPricingEngine.MarketState memory market =
            _defaultMarket();

        IPricingEngine.AsianOption memory option =
            _defaultOption();

        IPricingEngine.PriceResult memory result =
            engine.priceAsianCall(market, option);

        require(
            result.discountFactor < WAD,
            "positive rate should discount"
        );

        require(
            result.discountFactor > 0,
            "discount factor must be positive"
        );
    }

    // -------------------------------------------------------------------------
    // Greeks
    // -------------------------------------------------------------------------

    function testDeltaIsNonNegative() public view {
        IPricingEngine.MarketState memory market =
            _defaultMarket();

        IPricingEngine.AsianOption memory option =
            _defaultOption();

        IPricingEngine.Greeks memory result =
            engine.greeksAsianCall(market, option);

        require(
            result.delta >= 0,
            "call delta should be non-negative"
        );
    }

    function testVegaIsNonNegative() public view {
        IPricingEngine.MarketState memory market =
            _defaultMarket();

        IPricingEngine.AsianOption memory option =
            _defaultOption();

        IPricingEngine.Greeks memory result =
            engine.greeksAsianCall(market, option);

        require(
            result.vega >= 0,
            "call vega should be non-negative"
        );
    }

    function testGreeksAreDeterministic() public view {
        IPricingEngine.MarketState memory market =
            _defaultMarket();

        IPricingEngine.AsianOption memory option =
            _defaultOption();

        IPricingEngine.Greeks memory a =
            engine.greeksAsianCall(market, option);

        IPricingEngine.Greeks memory b =
            engine.greeksAsianCall(market, option);

        require(a.delta == b.delta, "delta changed");
        require(a.vega == b.vega, "vega changed");
    }

    // -------------------------------------------------------------------------
    // Input validation
    // -------------------------------------------------------------------------

    function testZeroSpotReverts() public {
        IPricingEngine.MarketState memory market =
            _defaultMarket();

        IPricingEngine.AsianOption memory option =
            _defaultOption();

        market.spot = 0;

        (bool success, ) = address(engine).call(
            abi.encodeCall(
                engine.priceAsianCall,
                (market, option)
            )
        );

        require(!success, "zero spot must revert");
    }

    function testZeroStrikeReverts() public {
        IPricingEngine.MarketState memory market =
            _defaultMarket();

        IPricingEngine.AsianOption memory option =
            _defaultOption();

        option.strike = 0;

        (bool success, ) = address(engine).call(
            abi.encodeCall(
                engine.priceAsianCall,
                (market, option)
            )
        );

        require(!success, "zero strike must revert");
    }

    function testZeroExpiryReverts() public {
        IPricingEngine.MarketState memory market =
            _defaultMarket();

        IPricingEngine.AsianOption memory option =
            _defaultOption();

        option.timeToExpiry = 0;

        (bool success, ) = address(engine).call(
            abi.encodeCall(
                engine.priceAsianCall,
                (market, option)
            )
        );

        require(!success, "zero expiry must revert");
    }

    function testZeroObservationsReverts() public {
        IPricingEngine.MarketState memory market =
            _defaultMarket();

        IPricingEngine.AsianOption memory option =
            _defaultOption();

        option.observations = 0;

        (bool success, ) = address(engine).call(
            abi.encodeCall(
                engine.priceAsianCall,
                (market, option)
            )
        );

        require(
            !success,
            "zero observations must revert"
        );
    }
}
