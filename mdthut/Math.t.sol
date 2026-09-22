// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FixedPointMath} from "../src/libraries/FixedPointMath.sol";
import {TranscendentalMath} from "../src/libraries/TranscendentalMath.sol";
import {NormalDistribution} from "../src/libraries/NormalDistribution.sol";

/// @notice Exposes internal library functions for unit testing only.
contract MathHarness {
    function mulWad(
        uint256 x,
        uint256 y
    ) external pure returns (uint256) {
        return FixedPointMath.mulWad(x, y);
    }

    function divWad(
        uint256 x,
        uint256 y
    ) external pure returns (uint256) {
        return FixedPointMath.divWad(x, y);
    }

    function exp(
        int256 x
    ) external pure returns (uint256) {
        return TranscendentalMath.exp(x);
    }

    function ln(
        uint256 x
    ) external pure returns (int256) {
        return TranscendentalMath.ln(x);
    }

    function pdf(
        int256 x
    ) external pure returns (uint256) {
        return NormalDistribution.pdf(x);
    }

    function cdf(
        int256 x
    ) external pure returns (uint256) {
        return NormalDistribution.cdf(x);
    }
}

/// @title MathTest
/// @notice Sanity and numerical-property tests for n0paths math primitives.
contract MathTest {
    uint256 internal constant WAD = 1e18;

    MathHarness internal math;

    function setUp() public {
        math = new MathHarness();
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

    function _absDiffSigned(
        int256 a,
        int256 b
    ) internal pure returns (uint256) {
        if (a >= b) {
            return uint256(a - b);
        }

        return uint256(b - a);
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

    function _assertApproxSigned(
        int256 actual,
        int256 expected,
        uint256 tolerance,
        string memory message
    ) internal pure {
        require(
            _absDiffSigned(actual, expected) <= tolerance,
            message
        );
    }

    // -------------------------------------------------------------------------
    // Fixed-point arithmetic
    // -------------------------------------------------------------------------

    function testMulWadIdentity() public view {
        uint256 x = 123456789000000000000;

        require(
            math.mulWad(x, WAD) == x,
            "mul WAD identity failed"
        );
    }

    function testMulWadHalf() public view {
        uint256 result = math.mulWad(
            10e18,
            5e17
        );

        require(
            result == 5e18,
            "10 * 0.5 != 5"
        );
    }

    function testDivWadIdentity() public view {
        uint256 x = 42e18;

        require(
            math.divWad(x, WAD) == x,
            "div WAD identity failed"
        );
    }

    function testDivWadHalf() public view {
        uint256 result = math.divWad(
            5e18,
            10e18
        );

        require(
            result == 5e17,
            "5 / 10 != 0.5"
        );
    }

    // -------------------------------------------------------------------------
    // exp()
    // -------------------------------------------------------------------------

    function testExpZero() public view {
        require(
            math.exp(0) == WAD,
            "exp(0) != 1"
        );
    }

    function testExpOne() public view {
        uint256 actual = math.exp(1e18);

        uint256 expected =
            2718281828459045235;

        _assertApprox(
            actual,
            expected,
            1e4,
            "exp(1) inaccurate"
        );
    }

    function testExpNegativeOne() public view {
        uint256 actual = math.exp(-1e18);

        uint256 expected =
            367879441171442322;

        _assertApprox(
            actual,
            expected,
            1e4,
            "exp(-1) inaccurate"
        );
    }

    function testExpMonotonic() public view {
        uint256 a = math.exp(-1e18);
        uint256 b = math.exp(0);
        uint256 c = math.exp(1e18);

        require(a < b, "exp not increasing");
        require(b < c, "exp not increasing");
    }

    // -------------------------------------------------------------------------
    // ln()
    // -------------------------------------------------------------------------

    function testLnOne() public view {
        require(
            math.ln(WAD) == 0,
            "ln(1) != 0"
        );
    }

    function testLnE() public view {
        uint256 e =
            2718281828459045235;

        int256 actual = math.ln(e);

        _assertApproxSigned(
            actual,
            1e18,
            1e4,
            "ln(e) inaccurate"
        );
    }

    function testLnHalf() public view {
        int256 actual =
            math.ln(5e17);

        int256 expected =
            -693147180559945309;

        _assertApproxSigned(
            actual,
            expected,
            1e4,
            "ln(0.5) inaccurate"
        );
    }

    function testLnMonotonic() public view {
        int256 a = math.ln(5e17);
        int256 b = math.ln(WAD);
        int256 c = math.ln(2e18);

        require(a < b, "ln not increasing");
        require(b < c, "ln not increasing");
    }

    // -------------------------------------------------------------------------
    // exp / ln round-trip
    // -------------------------------------------------------------------------

    function testExpLnRoundTripOne() public view {
        uint256 x = WAD;

        uint256 reconstructed =
            math.exp(math.ln(x));

        _assertApprox(
            reconstructed,
            x,
            1e4,
            "exp(ln(1)) failed"
        );
    }

    function testExpLnRoundTripHalf() public view {
        uint256 x = 5e17;

        uint256 reconstructed =
            math.exp(math.ln(x));

        _assertApprox(
            reconstructed,
            x,
            1e4,
            "exp(ln(0.5)) failed"
        );
    }

    function testExpLnRoundTripTwo() public view {
        uint256 x = 2e18;

        uint256 reconstructed =
            math.exp(math.ln(x));

        _assertApprox(
            reconstructed,
            x,
            1e4,
            "exp(ln(2)) failed"
        );
    }

    function testLnExpRoundTrip() public view {
        int256 x = 4e17;

        int256 reconstructed =
            math.ln(math.exp(x));

        _assertApproxSigned(
            reconstructed,
            x,
            1e4,
            "ln(exp(x)) failed"
        );
    }

    // -------------------------------------------------------------------------
    // Normal PDF
    // -------------------------------------------------------------------------

    function testPdfZero() public view {
        uint256 actual =
            math.pdf(0);

        uint256 expected =
            398942280401432677;

        _assertApprox(
            actual,
            expected,
            10,
            "phi(0) inaccurate"
        );
    }

    function testPdfSymmetry() public view {
        uint256 positive =
            math.pdf(15e17);

        uint256 negative =
            math.pdf(-15e17);

        require(
            positive == negative,
            "PDF symmetry failed"
        );
    }

    function testPdfFallsAwayFromZero() public view {
        uint256 atZero =
            math.pdf(0);

        uint256 atOne =
            math.pdf(1e18);

        uint256 atTwo =
            math.pdf(2e18);

        require(
            atZero > atOne,
            "PDF shape invalid"
        );

        require(
            atOne > atTwo,
            "PDF shape invalid"
        );
    }

    // -------------------------------------------------------------------------
    // Normal CDF
    // -------------------------------------------------------------------------

    function testCdfZeroApproximatelyHalf() public view {
        uint256 actual =
            math.cdf(0);

        _assertApprox(
            actual,
            5e17,
            1e11,
            "Phi(0) inaccurate"
        );
    }

    function testCdfMonotonic() public view {
        uint256 a =
            math.cdf(-2e18);

        uint256 b =
            math.cdf(-1e18);

        uint256 c =
            math.cdf(0);

        uint256 d =
            math.cdf(1e18);

        uint256 e =
            math.cdf(2e18);

        require(a < b, "CDF not increasing");
        require(b < c, "CDF not increasing");
        require(c < d, "CDF not increasing");
        require(d < e, "CDF not increasing");
    }

    function testCdfSymmetryAtOne() public view {
        uint256 positive =
            math.cdf(1e18);

        uint256 negative =
            math.cdf(-1e18);

        uint256 sum =
            positive + negative;

        _assertApprox(
            sum,
            WAD,
            10,
            "CDF symmetry failed"
        );
    }

    function testCdfKnownValueAtOne() public view {
        uint256 actual =
            math.cdf(1e18);

        // Phi(1) ~= 0.841344746
        uint256 expected =
            841344746068542900;

        // Abramowitz-Stegun 7.1.26 is an approximation,
        // so use a tolerance appropriate to that method.
        _assertApprox(
            actual,
            expected,
            1e11,
            "Phi(1) outside tolerance"
        );
    }

    function testCdfExtremeTails() public view {
        require(
            math.cdf(-10e18) == 0,
            "negative tail not clamped"
        );

        require(
            math.cdf(10e18) == WAD,
            "positive tail not clamped"
        );
    }

    // -------------------------------------------------------------------------
    // Domain behavior
    // -------------------------------------------------------------------------

    function testLnZeroReverts() public {
        (bool success, ) =
            address(math).call(
                abi.encodeCall(
                    math.ln,
                    (uint256(0))
                )
            );

        require(
            !success,
            "ln(0) must revert"
        );
    }
}
