
/// @title TranscendentalMath
/// @notice Deterministic fixed-point exponential and natural logarithm functions.
/// @dev Inputs and outputs use signed 18-decimal WAD fixed-point arithmetic.
///
///      Examples:
///          exp(0)      = 1e18
///          exp(1e18)   ≈ 2.718281828e18
///          ln(1e18)    = 0
///          ln(e * 1e18) ≈ 1e18
///
///      The implementation uses range reduction followed by convergent series.
///      It is designed for the bounded numerical domain used by the pricing
///      engine, rather than as a general-purpose arbitrary-range math library.
library TranscendentalMath {
    int256 internal constant WAD = 1e18;

    // ln(2), scaled by 1e18.
    int256 internal constant LN2 = 693147180559945309;

    // Pricing inputs should never approach these bounds.
    // They also protect intermediate arithmetic from unreasonable inputs.
    int256 internal constant MAX_EXP_INPUT = 100e18;
    int256 internal constant MIN_EXP_INPUT = -100e18;

    error ExpOverflow();
    error LnUndefined();
    error InputOutOfRange();

    /// @notice Compute e^x.
    /// @param x Signed WAD value.
    /// @return result e^x as unsigned WAD.
    function exp(int256 x) internal pure returns (uint256 result) {
        if (x > MAX_EXP_INPUT) revert ExpOverflow();

        // At the lower bound the result is tiny relative to WAD precision.
        if (x < MIN_EXP_INPUT) return 0;

        if (x == 0) return uint256(WAD);

        // Reduce:
        //
        //     x = k * ln(2) + r
        //
        // with r kept close to zero. Then:
        //
        //     exp(x) = 2^k * exp(r)
        //
        int256 k = x / LN2;
        int256 r = x - k * LN2;

        // Improve convergence by keeping |r| <= ln(2)/2.
        int256 halfLn2 = LN2 / 2;

        if (r > halfLn2) {
            k += 1;
            r -= LN2;
        } else if (r < -halfLn2) {
            k -= 1;
            r += LN2;
        }

        int256 expR = _expSeries(r);

        if (expR <= 0) return 0;

        uint256 unsignedExpR = uint256(expR);

        if (k >= 0) {
            uint256 shift = uint256(k);

            if (shift >= 256) revert ExpOverflow();
            if (unsignedExpR > (type(uint256).max >> shift)) {
                revert ExpOverflow();
            }

            result = unsignedExpR << shift;
        } else {
            uint256 shift = uint256(-k);

            if (shift >= 256) return 0;

            result = unsignedExpR >> shift;
        }
    }

    /// @notice Compute the natural logarithm ln(x).
    /// @param x Positive unsigned WAD value.
    /// @return result ln(x), signed and scaled by 1e18.
    function ln(uint256 x) internal pure returns (int256 result) {
        if (x == 0) revert LnUndefined();

        // Normalize x into:
        //
        //     m in [1, 2)
        //
        // such that:
        //
        //     x = m * 2^k
        //
        // and therefore:
        //
        //     ln(x) = ln(m) + k * ln(2)
        //
        uint256 m = x;
        int256 k = 0;

        while (m >= 2e18) {
            m >>= 1;
            k += 1;
        }

        while (m < 1e18) {
            // Prevent overflow from malformed/extreme inputs.
            if (m > type(uint256).max / 2) {
                revert InputOutOfRange();
            }

            m <<= 1;
            k -= 1;
        }

        // Use:
        //
        //              m - 1
        //     z = -------------
        //              m + 1
        //
        // then:
        //
        //     ln(m) = 2 * (
        //         z
        //       + z^3 / 3
        //       + z^5 / 5
        //       + ...
        //     )
        //
        // Since m ∈ [1,2), z ∈ [0,1/3), giving fast convergence.
        int256 numerator = int256(m) - WAD;
        int256 denominator = int256(m) + WAD;

        int256 z = FixedPointMath.divWadSigned(
            numerator,
            denominator
        );

        int256 z2 = FixedPointMath.mulWadSigned(z, z);

        int256 term = z;
        int256 sum = term;

        // Terms through z^39 / 39.
        // For |z| <= 1/3 this is comfortably below WAD precision
        // for the pricing domain.
        for (uint256 n = 3; n <= 39; n += 2) {
            term = FixedPointMath.mulWadSigned(term, z2);
            sum += term / int256(n);
        }

        int256 lnM = 2 * sum;

        result = lnM + k * LN2;
    }

    /// @notice Internal Taylor expansion for exp(r).
    /// @dev r is range-reduced to approximately [-ln(2)/2, ln(2)/2].
    function _expSeries(int256 r) private pure returns (int256 sum) {
        sum = WAD;

        int256 term = WAD;

        // exp(r) = Σ r^n / n!
        //
        // With |r| <= ln(2)/2, 24 terms provide substantially more
        // precision than required by the pricing engine's WAD output.
        for (uint256 n = 1; n <= 24; ++n) {
            term = FixedPointMath.mulWadSigned(term, r);
            term /= int256(n);

            sum += term;

            // Once the term is below one WAD unit it can no longer
            // materially improve the 18-decimal result.
            if (term == 0) break;
        }
    }
}
