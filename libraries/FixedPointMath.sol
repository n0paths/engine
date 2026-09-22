
/// @notice Minimal fixed-point arithmetic primitives used by n0paths.
/// @dev Values are represented as 18-decimal WAD fixed-point numbers.
///
///      1.0  = 1e18
///      0.5  = 5e17
///      100  = 100e18
///
///      This library intentionally keeps the core arithmetic small.
///      Transcendental functions such as exp() and ln() are implemented
///      separately so their numerical assumptions can be tested in isolation.
library FixedPointMath {
    uint256 internal constant WAD = 1e18;
    int256 internal constant WAD_INT = 1e18;

    error DivisionByZero();
    error SignedOverflow();
    error NegativeToUnsigned();

    /// @notice Multiply two unsigned WAD values.
    /// @dev Computes (x * y) / 1e18.
    function mulWad(uint256 x, uint256 y) internal pure returns (uint256) {
        if (x == 0 || y == 0) return 0;

        return mulDiv(x, y, WAD);
    }

    /// @notice Divide one unsigned WAD value by another.
    /// @dev Computes (x * 1e18) / y.
    function divWad(uint256 x, uint256 y) internal pure returns (uint256) {
        if (y == 0) revert DivisionByZero();

        return mulDiv(x, WAD, y);
    }

    /// @notice Multiply two signed WAD values.
    function mulWadSigned(int256 x, int256 y) internal pure returns (int256) {
        if (x == 0 || y == 0) return 0;

        bool negative = (x < 0) != (y < 0);

        uint256 ax = abs(x);
        uint256 ay = abs(y);

        uint256 result = mulDiv(ax, ay, WAD);

        if (result > uint256(type(int256).max)) {
            revert SignedOverflow();
        }

        int256 signedResult = int256(result);

        return negative ? -signedResult : signedResult;
    }

    /// @notice Divide one signed WAD value by another.
    function divWadSigned(int256 x, int256 y) internal pure returns (int256) {
        if (y == 0) revert DivisionByZero();
        if (x == 0) return 0;

        bool negative = (x < 0) != (y < 0);

        uint256 ax = abs(x);
        uint256 ay = abs(y);

        uint256 result = mulDiv(ax, WAD, ay);

        if (result > uint256(type(int256).max)) {
            revert SignedOverflow();
        }

        int256 signedResult = int256(result);

        return negative ? -signedResult : signedResult;
    }

    /// @notice Convert an unsigned integer into WAD representation.
    function toWad(uint256 x) internal pure returns (uint256) {
        return x * WAD;
    }

    /// @notice Convert a WAD value back to its integer component.
    function fromWad(uint256 x) internal pure returns (uint256) {
        return x / WAD;
    }

    /// @notice Convert a non-negative signed integer to uint256.
    function toUint(int256 x) internal pure returns (uint256) {
        if (x < 0) revert NegativeToUnsigned();

        return uint256(x);
    }

    /// @notice Return the absolute value of a signed integer as uint256.
    /// @dev Handles int256.min without evaluating `-x` in signed arithmetic.
    function abs(int256 x) internal pure returns (uint256 result) {
        assembly ("memory-safe") {
            let mask := sar(255, x)
            result := sub(xor(x, mask), mask)
        }
    }

    /// @notice Full-precision floor(x * y / denominator).
    /// @dev Uses a 512-bit intermediate product so x * y does not need
    ///      to fit inside uint256.
    ///
    ///      Based on the standard mulDiv construction used by modern
    ///      Solidity fixed-point libraries.
    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        if (denominator == 0) revert DivisionByZero();

        unchecked {
            uint256 prod0;
            uint256 prod1;

            assembly ("memory-safe") {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Product fits in 256 bits.
            if (prod1 == 0) {
                return prod0 / denominator;
            }

            // Result would overflow uint256.
            require(denominator > prod1, "MULDIV_OVERFLOW");

            uint256 remainder;

            assembly ("memory-safe") {
                remainder := mulmod(x, y, denominator)

                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator.
            uint256 twos = denominator & (~denominator + 1);

            assembly ("memory-safe") {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)

                twos := add(
                    div(sub(0, twos), twos),
                    1
                )
            }

            prod0 |= prod1 * twos;

            // Compute modular inverse of denominator mod 2^256.
            uint256 inverse = (3 * denominator) ^ 2;

            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;

            result = prod0 * inverse;

            return result;
        }
    }
}
