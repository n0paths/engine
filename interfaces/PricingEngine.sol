/// @title IPricingEngine
/// @notice Common interface for deterministic derivatives pricing engines.
/// @dev All decimal values use 18-decimal fixed-point arithmetic unless stated otherwise.
interface IPricingEngine {
    /// @notice Current market state used by the pricing model.
    ///
    /// @param spot Current underlying price, scaled by 1e18.
    /// @param volatility Annualized volatility, scaled by 1e18.
    ///        Example: 60% volatility = 0.60e18.
    /// @param riskFreeRate Continuously compounded annual risk-free rate,
    ///        scaled by 1e18.
    /// @param dividendYield Continuously compounded annual dividend/carry yield,
    ///        scaled by 1e18.
    struct MarketState {
        uint256 spot;
        uint256 volatility;
        int256 riskFreeRate;
        int256 dividendYield;
    }

    /// @notice Parameters for an arithmetic-average Asian call option.
    ///
    /// @param strike Strike price, scaled by 1e18.
    /// @param timeToExpiry Time remaining until expiry expressed in years,
    ///        scaled by 1e18.
    ///        Example: 0.5 years = 0.5e18.
    /// @param observations Number of equally spaced averaging observations.
    struct AsianOption {
        uint256 strike;
        uint256 timeToExpiry;
        uint256 observations;
    }

    /// @notice Intermediate moments and fitted distribution parameters.
    ///
    /// @param firstMoment E[A].
    /// @param secondMoment E[A^2].
    /// @param effectiveVariance Variance of ln(A) under the moment-matched
    ///        lognormal approximation.
    /// @param logMean Mean of ln(A) under the fitted lognormal distribution.
    struct Distribution {
        uint256 firstMoment;
        uint256 secondMoment;
        uint256 effectiveVariance;
        int256 logMean;
    }

    /// @notice Complete result returned by the pricing engine.
    ///
    /// @param price Present value of the option payoff.
    /// @param undiscountedPayoff Expected payoff before discounting.
    /// @param discountFactor exp(-rT).
    /// @param distribution Moment-matched distribution used by the engine.
    struct PriceResult {
        uint256 price;
        uint256 undiscountedPayoff;
        uint256 discountFactor;
        Distribution distribution;
    }

    /// @notice First-order risk sensitivities exposed by the initial engine.
    ///
    /// @dev Delta and vega may be evaluated using deterministic central
    ///      finite differences. They therefore contain numerical
    ///      approximation error but no sampling error.
    ///
    /// @param delta Sensitivity of price to the underlying spot.
    /// @param vega Sensitivity of price to annualized volatility.
    struct Greeks {
        int256 delta;
        int256 vega;
    }

    /// @notice Price an arithmetic-average Asian call.
    /// @dev The implementation must be deterministic:
    ///      identical inputs must produce identical outputs.
    function priceAsianCall(
        MarketState calldata market,
        AsianOption calldata option
    ) external pure returns (PriceResult memory result);

    /// @notice Calculate the supported risk sensitivities.
    function greeksAsianCall(
        MarketState calldata market,
        AsianOption calldata option
    ) external pure returns (Greeks memory result);
}
