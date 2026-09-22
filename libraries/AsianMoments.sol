import {FixedPointMath} from "./FixedPointMath.sol";
import {TranscendentalMath} from "./TranscendentalMath.sol";

/// @title AsianMoments
/// @notice Moments of a discretely monitored arithmetic average under GBM.
/// @dev All monetary values and model parameters use 18-decimal WAD arithmetic.
///
///      Under the risk-neutral GBM model:
///
///          dS_t / S_t = (r - q) dt + sigma dW_t
///
///      and for:
///
///          A = (1/n) * sum_i S(t_i)
///
///      this library computes:
///
///          M1 = E[A]
///          M2 = E[A^2]
///
///      for equally spaced observation times:
///
///          t_i = iT/n,  i = 1,...,n
///
///      These moments are later used to fit a lognormal approximation
///      to the arithmetic average.
library AsianMoments {
    uint256 internal constant WAD = 1e18;

    error ZeroSpot();
    error ZeroObservations();
    error InvalidTime();
    error MomentOverflow();

    struct Moments {
        uint256 first;
        uint256 second;
    }

    /// @notice Compute E[A] and E[A^2] for an arithmetic Asian average.
    ///
    /// @param spot Current underlying price, WAD.
    /// @param volatility Annualized volatility, WAD.
    /// @param riskFreeRate Continuously compounded annual rate, signed WAD.
    /// @param dividendYield Continuously compounded annual yield, signed WAD.
    /// @param timeToExpiry Time to expiry in years, WAD.
    /// @param observations Number of equally spaced future observations.
    function compute(
        uint256 spot,
        uint256 volatility,
        int256 riskFreeRate,
        int256 dividendYield,
        uint256 timeToExpiry,
        uint256 observations
    ) internal pure returns (Moments memory result) {
        if (spot == 0) revert ZeroSpot();
        if (observations == 0) revert ZeroObservations();
        if (timeToExpiry == 0) revert InvalidTime();

        int256 drift = riskFreeRate - dividendYield;

        // sigma^2
        uint256 variance = FixedPointMath.mulWad(
            volatility,
            volatility
        );

        uint256 firstSum;
        uint256 secondSum;

        // E[S(t_i)] terms.
        for (uint256 i = 1; i <= observations; ++i) {
            uint256 ti = FixedPointMath.mulDiv(
                timeToExpiry,
                i,
                observations
            );

            int256 driftTime = FixedPointMath.mulWadSigned(
                drift,
                int256(ti)
            );

            uint256 growth = TranscendentalMath.exp(driftTime);

            uint256 expectedSpot = FixedPointMath.mulWad(
                spot,
                growth
            );

            if (type(uint256).max - firstSum < expectedSpot) {
                revert MomentOverflow();
            }

            firstSum += expectedSpot;
        }

        result.first = firstSum / observations;

        // For GBM:
        //
        // E[S(t_i) S(t_j)]
        //
        // = S0^2
        //   * exp(
        //       (r-q)(t_i+t_j)
        //       + sigma^2 * min(t_i,t_j)
        //     )
        //
        // Therefore:
        //
        // E[A^2]
        //
        // = (1/n^2)
        //   * sum_i sum_j E[S(t_i)S(t_j)]
        //
        uint256 spotSquared = FixedPointMath.mulWad(
            spot,
            spot
        );

        for (uint256 i = 1; i <= observations; ++i) {
            uint256 ti = FixedPointMath.mulDiv(
                timeToExpiry,
                i,
                observations
            );

            for (uint256 j = 1; j <= observations; ++j) {
                uint256 tj = FixedPointMath.mulDiv(
                    timeToExpiry,
                    j,
                    observations
                );

                uint256 minTime = ti < tj ? ti : tj;

                // (r-q)(ti + tj)
                //
                // Compute the two products separately so ti + tj
                // cannot overflow before fixed-point multiplication.
                int256 driftTi = FixedPointMath.mulWadSigned(
                    drift,
                    int256(ti)
                );

                int256 driftTj = FixedPointMath.mulWadSigned(
                    drift,
                    int256(tj)
                );

                int256 driftContribution = driftTi + driftTj;

                // sigma^2 * min(ti, tj)
                uint256 covarianceUnsigned = FixedPointMath.mulWad(
                    variance,
                    minTime
                );

                if (
                    covarianceUnsigned >
                    uint256(type(int256).max)
                ) {
                    revert MomentOverflow();
                }

                int256 exponent =
                    driftContribution +
                    int256(covarianceUnsigned);

                uint256 growth = TranscendentalMath.exp(
                    exponent
                );

                uint256 crossMoment = FixedPointMath.mulWad(
                    spotSquared,
                    growth
                );

                if (
                    type(uint256).max - secondSum <
                    crossMoment
                ) {
                    revert MomentOverflow();
                }

                secondSum += crossMoment;
            }
        }

        uint256 denominator =
            observations * observations;

        result.second = secondSum / denominator;
    }
}
