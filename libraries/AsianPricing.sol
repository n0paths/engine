import {FixedPointMath} from "./FixedPointMath.sol";
import {TranscendentalMath} from "./TranscendentalMath.sol";
import {NormalDistribution} from "./NormalDistribution.sol";
import {AsianMoments} from "./AsianMoments.sol";

/// @title AsianPricing
/// @notice Deterministic moment-matching approximation for arithmetic Asian calls.
/// @dev Fits a lognormal distribution to the first two moments of the
///      arithmetic average and evaluates the expected call payoff analytically.
///
///      A = (1/n) * sum_i S(t_i)
///
///      M1 = E[A]
///      M2 = E[A^2]
///
///      The fitted lognormal distribution satisfies:
///
///          sigma_A^2 = ln(M2 / M1^2)
///
///          mu_A = ln(M1) - 0.5 * sigma_A^2
///
///      If ln(A) ~ N(mu_A, sigma_A^2), then:
///
///          E[(A-K)+]
///              = M1 * Phi(d1) - K * Phi(d2)
///
///      where:
///
///          d2 = (mu_A - ln(K)) / sigma_A
///          d1 = d2 + sigma_A
///
///      The present value is:
///
///          price = exp(-rT) * E[(A-K)+]
///
///      This is an approximation for arithmetic-average options.
///      It eliminates Monte Carlo sampling error, but not model or
///      distribution-approximation error.
library AsianPricing {
    uint256 internal constant WAD = 1e18;

    error ZeroStrike();
    error InvalidMoments();
    error NumericalDomain();

    struct PricingResult {
        uint256 price;
        uint256 undiscountedPayoff;
        uint256 discountFactor;

        uint256 firstMoment;
        uint256 secondMoment;

        uint256 effectiveVariance;
        int256 logMean;

        int256 d1;
        int256 d2;
    }

    /// @notice Price a discretely monitored arithmetic Asian call.
    function priceCall(
        uint256 spot,
        uint256 strike,
        uint256 volatility,
        int256 riskFreeRate,
        int256 dividendYield,
        uint256 timeToExpiry,
        uint256 observations
    ) internal pure returns (PricingResult memory result) {
        if (strike == 0) revert ZeroStrike();

        AsianMoments.Moments memory moments = AsianMoments.compute(
            spot,
            volatility,
            riskFreeRate,
            dividendYield,
            timeToExpiry,
            observations
        );

        result.firstMoment = moments.first;
        result.secondMoment = moments.second;

        if (moments.first == 0 || moments.second == 0) {
            revert InvalidMoments();
        }

        // M1^2, still represented as WAD.
        uint256 firstMomentSquared = FixedPointMath.mulWad(
            moments.first,
            moments.first
        );

        if (moments.second < firstMomentSquared) {
            // Mathematically M2 >= M1^2.
            //
            // A violation means fixed-point rounding or an upstream
            // numerical issue has pushed the moments outside the
            // valid distribution domain.
            revert InvalidMoments();
        }

        // ratio = M2 / M1^2
        uint256 momentRatio = FixedPointMath.divWad(
            moments.second,
            firstMomentSquared
        );

        int256 varianceSigned = TranscendentalMath.ln(
            momentRatio
        );

        if (varianceSigned < 0) {
            revert NumericalDomain();
        }

        result.effectiveVariance = uint256(varianceSigned);

        // mu_A = ln(M1) - 0.5 * sigma_A^2
        result.logMean =
            TranscendentalMath.ln(moments.first) -
            varianceSigned / 2;

        // Discount factor exp(-rT).
        int256 rT = FixedPointMath.mulWadSigned(
            riskFreeRate,
            int256(timeToExpiry)
        );

        result.discountFactor = TranscendentalMath.exp(-rT);

        // Degenerate zero-variance case.
        //
        // If A is deterministic, the option value is simply the
        // discounted intrinsic payoff of that deterministic average.
        if (result.effectiveVariance == 0) {
            if (moments.first <= strike) {
                result.undiscountedPayoff = 0;
                result.price = 0;

                return result;
            }

            result.undiscountedPayoff =
                moments.first - strike;

            result.price = FixedPointMath.mulWad(
                result.discountFactor,
                result.undiscountedPayoff
            );

            return result;
        }

        uint256 sigmaA = sqrtWad(
            result.effectiveVariance
        );

        if (sigmaA == 0) {
            revert NumericalDomain();
        }

        int256 logStrike = TranscendentalMath.ln(strike);

        // d2 = (mu_A - ln(K)) / sigma_A
        result.d2 = FixedPointMath.divWadSigned(
            result.logMean - logStrike,
            int256(sigmaA)
        );

        // d1 = d2 + sigma_A
        result.d1 = result.d2 + int256(sigmaA);

        uint256 phiD1 = NormalDistribution.cdf(
            result.d1
        );

        uint256 phiD2 = NormalDistribution.cdf(
            result.d2
        );

        uint256 expectedAssetTerm = FixedPointMath.mulWad(
            moments.first,
            phiD1
        );

        uint256 expectedStrikeTerm = FixedPointMath.mulWad(
            strike,
            phiD2
        );

        // Numerical approximations near extreme tails can theoretically
        // produce a tiny negative payoff. Clamp that case to zero.
        if (expectedAssetTerm <= expectedStrikeTerm) {
            result.undiscountedPayoff = 0;
            result.price = 0;

            return result;
        }

        result.undiscountedPayoff =
            expectedAssetTerm - expectedStrikeTerm;

        result.price = FixedPointMath.mulWad(
            result.discountFactor,
            result.undiscountedPayoff
        );
    }

    /// @notice Square root of a WAD value.
    /// @dev If x represents X * 1e18, sqrtWad(x) returns sqrt(X) * 1e18.
    function sqrtWad(
        uint256 x
    ) internal pure returns (uint256) {
        if (x == 0) return 0;

        // sqrt(x * WAD)
        //
        // effectiveVariance in the intended pricing domain is small,
        // so this multiplication is safe for valid model inputs.
        if (x > type(uint256).max / WAD) {
            revert NumericalDomain();
        }

        return _sqrt(x * WAD);
    }

    /// @notice Integer square root using Babylonian iteration.
    function _sqrt(
        uint256 x
    ) private pure returns (uint256 result) {
        if (x == 0) return 0;

        uint256 z = (x + 1) / 2;
        result = x;

        while (z < result) {
            result = z;
            z = (x / z + z) / 2;
        }
    }
}
