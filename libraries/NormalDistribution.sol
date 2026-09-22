
import {FixedPointMath} from "./FixedPointMath.sol";
import {TranscendentalMath} from "./TranscendentalMath.sol";

/// @title NormalDistribution
/// @notice Deterministic standard-normal PDF and CDF for WAD fixed-point values.
/// @dev Inputs and outputs use 18-decimal fixed-point arithmetic.
///
///      pdf(x) = φ(x)
///      cdf(x) = Φ(x)
///
///      The CDF uses the Abramowitz-Stegun 7.1.26 approximation.
///      It is deterministic and sufficiently accurate for the initial
///      n0paths pricing engine, subject to validation against the
///      off-chain reference implementation.
library NormalDistribution {
    int256 internal constant WAD = 1e18;

    // 1 / sqrt(2*pi)
    uint256 internal constant INV_SQRT_2PI = 398942280401432677;

    // Abramowitz-Stegun approximation coefficients.
    int256 internal constant P = 231641900000000000;

    int256 internal constant B1 = 319381530000000000;
    int256 internal constant B2 = -356563782000000000;
    int256 internal constant B3 = 1781477937000000000;
    int256 internal constant B4 = -1821255978000000000;
    int256 internal constant B5 = 1330274429000000000;

    /// @notice Standard normal probability density function.
    ///
    /// @param x Signed WAD value.
    /// @return result φ(x), scaled by 1e18.
    function pdf(int256 x) internal pure returns (uint256 result) {
        int256 xSquared = FixedPointMath.mulWadSigned(x, x);

        // exponent = -x² / 2
        int256 exponent = -(xSquared / 2);

        uint256 exponential = TranscendentalMath.exp(exponent);

        result = FixedPointMath.mulWad(
            INV_SQRT_2PI,
            exponential
        );
    }

    /// @notice Standard normal cumulative distribution function.
    ///
    /// @param x Signed WAD value.
    /// @return result Φ(x), scaled by 1e18.
    function cdf(int256 x) internal pure returns (uint256 result) {
        // Beyond these values the tails are far below the precision
        // relevant to the pricing engine.
        if (x <= -10e18) return 0;
        if (x >= 10e18) return uint256(WAD);

        bool negative = x < 0;

        uint256 axUnsigned = FixedPointMath.abs(x);

        // Safe because |x| <= 10e18 after the guards above.
        int256 ax = int256(axUnsigned);

        // t = 1 / (1 + p*x)
        int256 px = FixedPointMath.mulWadSigned(P, ax);

        int256 denominator = WAD + px;

        int256 t = FixedPointMath.divWadSigned(
            WAD,
            denominator
        );

        // Polynomial:
        //
        // b1*t
        // + b2*t²
        // + b3*t³
        // + b4*t⁴
        // + b5*t⁵
        //
        // Horner form:
        //
        // t * (
        //     b1 + t * (
        //         b2 + t * (
        //             b3 + t * (
        //                 b4 + t*b5
        //             )
        //         )
        //     )
        // )
        int256 polynomial = B5;

        polynomial =
            B4 +
            FixedPointMath.mulWadSigned(t, polynomial);

        polynomial =
            B3 +
            FixedPointMath.mulWadSigned(t, polynomial);

        polynomial =
            B2 +
            FixedPointMath.mulWadSigned(t, polynomial);

        polynomial =
            B1 +
            FixedPointMath.mulWadSigned(t, polynomial);

        polynomial = FixedPointMath.mulWadSigned(
            t,
            polynomial
        );

        uint256 density = pdf(ax);

        int256 tail = FixedPointMath.mulWadSigned(
            int256(density),
            polynomial
        );

        int256 positiveCdf = WAD - tail;

        if (positiveCdf < 0) {
            positiveCdf = 0;
        }

        if (positiveCdf > WAD) {
            positiveCdf = WAD;
        }

        if (negative) {
            result = uint256(WAD - positiveCdf);
        } else {
            result = uint256(positiveCdf);
        }
    }
}
