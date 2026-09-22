import {IPricingEngine} from "./interfaces/IPricingEngine.sol";
import {AsianPricing} from "./libraries/AsianPricing.sol";

/// @title N0PathsEngine
/// @notice Deterministic pricing engine for onchain derivatives.
/// @dev Initial implementation supports discretely monitored
///      arithmetic-average Asian call options.
///
///      Pricing pipeline:
///
///          market state
///              ↓
///          exact GBM moments
///              ↓
///          moment-matched lognormal distribution
///              ↓
///          expected payoff
///              ↓
///          discounted option price
///
///      No mutable state, oracle reads, randomness, or external calls
///      occur inside the pricing calculation.
///
///      Identical inputs therefore produce identical outputs.
contract N0PathsEngine is IPricingEngine {
    uint256 private constant WAD = 1e18;

    // Relative bump used for spot when evaluating delta:
    //
    //     h_S = S * 0.01%
    //
    // 1 basis point = 0.0001 = 1e14 WAD.
    uint256 private constant SPOT_BUMP_RATE = 1e14;

    // Absolute volatility bump:
    //
    //     h_sigma = 0.01%
    //
    // expressed in volatility units.
    uint256 private constant VOL_BUMP = 1e14;

    error InvalidSpot();
    error InvalidStrike();
    error InvalidExpiry();
    error InvalidObservations();
    error SpotBumpTooSmall();
    error VolatilityBumpTooSmall();

    /// @inheritdoc IPricingEngine
    function priceAsianCall(
        MarketState calldata market,
        AsianOption calldata option
    ) external pure override returns (PriceResult memory result) {
        _validate(market, option);

        AsianPricing.PricingResult memory priced = AsianPricing.priceCall(
            market.spot,
            option.strike,
            market.volatility,
            market.riskFreeRate,
            market.dividendYield,
            option.timeToExpiry,
            option.observations
        );

        result = _toPriceResult(priced);
    }

    /// @inheritdoc IPricingEngine
    /// @dev Delta and vega are computed using deterministic central
    ///      finite differences.
    ///
    ///      delta ≈ [V(S+h) - V(S-h)] / (2h)
    ///
    ///      vega  ≈ [V(sigma+h) - V(sigma-h)] / (2h)
    ///
    ///      Vega is returned per 1.00 change in volatility.
    ///      For example, to obtain sensitivity to a one percentage-point
    ///      volatility move, divide the returned vega by 100.
    function greeksAsianCall(
        MarketState calldata market,
        AsianOption calldata option
    ) external pure override returns (Greeks memory result) {
        _validate(market, option);

        result.delta = _delta(market, option);
        result.vega = _vega(market, option);
    }

    /// @notice Convenience method returning only the scalar option price.
    /// @dev Useful for integrations that do not require intermediate
    ///      distribution parameters.
    function price(
        MarketState calldata market,
        AsianOption calldata option
    ) external pure returns (uint256) {
        _validate(market, option);

        return _price(
            market.spot,
            market.volatility,
            market,
            option
        );
    }

    /// @notice Return the fixed-point scale used by the engine.
    function scale() external pure returns (uint256) {
        return WAD;
    }

    /// @notice Human-readable engine version.
    function version() external pure returns (string memory) {
        return "0.1.0";
    }

    function _delta(
        MarketState calldata market,
        AsianOption calldata option
    ) private pure returns (int256) {
        uint256 bump = (market.spot * SPOT_BUMP_RATE) / WAD;

        if (bump == 0 || bump >= market.spot) {
            revert SpotBumpTooSmall();
        }

        uint256 priceUp = _price(
            market.spot + bump,
            market.volatility,
            market,
            option
        );

        uint256 priceDown = _price(
            market.spot - bump,
            market.volatility,
            market,
            option
        );

        int256 numerator = _signedDifference(
            priceUp,
            priceDown
        );

        // Both price and spot are WAD-scaled:
        //
        // delta =
        //     (priceUp - priceDown)
        //     ---------------------
        //            2 * bump
        //
        // To keep the result WAD-scaled we multiply the numerator by WAD.
        resultCheck(numerator);

        return
            (numerator * int256(WAD)) /
            int256(2 * bump);
    }

    function _vega(
        MarketState calldata market,
        AsianOption calldata option
    ) private pure returns (int256) {
        uint256 bump = VOL_BUMP;

        uint256 volatilityUp = market.volatility + bump;

        uint256 volatilityDown;

        if (market.volatility > bump) {
            volatilityDown = market.volatility - bump;
        } else {
            // Central difference is undefined at the lower boundary.
            // Use a deterministic forward difference instead.
            uint256 basePrice = _price(
                market.spot,
                market.volatility,
                market,
                option
            );

            uint256 upPrice = _price(
                market.spot,
                volatilityUp,
                market,
                option
            );

            int256 forwardDifference = _signedDifference(
                upPrice,
                basePrice
            );

            resultCheck(forwardDifference);

            return
                (forwardDifference * int256(WAD)) /
                int256(bump);
        }

        if (volatilityUp <= volatilityDown) {
            revert VolatilityBumpTooSmall();
        }

        uint256 priceUp = _price(
            market.spot,
            volatilityUp,
            market,
            option
        );

        uint256 priceDown = _price(
            market.spot,
            volatilityDown,
            market,
            option
        );

        int256 numerator = _signedDifference(
            priceUp,
            priceDown
        );

        resultCheck(numerator);

        return
            (numerator * int256(WAD)) /
            int256(2 * bump);
    }

    function _price(
        uint256 spot,
        uint256 volatility,
        MarketState calldata market,
        AsianOption calldata option
    ) private pure returns (uint256) {
        AsianPricing.PricingResult memory priced = AsianPricing.priceCall(
            spot,
            option.strike,
            volatility,
            market.riskFreeRate,
            market.dividendYield,
            option.timeToExpiry,
            option.observations
        );

        return priced.price;
    }

    function _toPriceResult(
        AsianPricing.PricingResult memory priced
    ) private pure returns (PriceResult memory result) {
        result.price = priced.price;
        result.undiscountedPayoff = priced.undiscountedPayoff;
        result.discountFactor = priced.discountFactor;

        result.distribution = Distribution({
            firstMoment: priced.firstMoment,
            secondMoment: priced.secondMoment,
            effectiveVariance: priced.effectiveVariance,
            logMean: priced.logMean
        });
    }

    function _validate(
        MarketState calldata market,
        AsianOption calldata option
    ) private pure {
        if (market.spot == 0) revert InvalidSpot();
        if (option.strike == 0) revert InvalidStrike();
        if (option.timeToExpiry == 0) revert InvalidExpiry();
        if (option.observations == 0) {
            revert InvalidObservations();
        }
    }

    /// @dev Convert the difference between two uint256 values into
    ///      a signed integer without unsigned underflow.
    function _signedDifference(
        uint256 a,
        uint256 b
    ) private pure returns (int256) {
        if (a >= b) {
            uint256 difference = a - b;

            require(
                difference <= uint256(type(int256).max),
                "SIGNED_DIFFERENCE_OVERFLOW"
            );

            return int256(difference);
        }

        uint256 difference = b - a;

        require(
            difference <= uint256(type(int256).max),
            "SIGNED_DIFFERENCE_OVERFLOW"
        );

        return -int256(difference);
    }

    /// @dev Guard multiplication by WAD used by finite differences.
    function resultCheck(int256 value) private pure {
        if (value == 0) return;

        uint256 absolute = value < 0
            ? uint256(-value)
            : uint256(value);

        require(
            absolute <= uint256(type(int256).max) / WAD,
            "GREEK_OVERFLOW"
        );
    }
}
