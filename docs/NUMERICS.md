# Numerical Design

## Scope

`n0paths` evaluates a continuous mathematical model inside a finite-precision
integer environment.

This creates a distinction between:

1. the mathematical pricing method,
2. its floating-point reference implementation,
3. its Solidity fixed-point implementation.

This document describes the numerical conventions used by the Solidity layer
and the validation rules around them.

---

## Fixed-point representation

The engine uses signed and unsigned 18-decimal fixed-point arithmetic.

The scaling constant is

\[
W = 10^{18}.
\]

A real value \(x\) is represented approximately as

\[
x_W = \lfloor xW \rfloor
\]

or by the corresponding rounded integer produced by the operation that
generated it.

Examples:

```text
1.00       -> 1e18
100.00     -> 100e18
0.60       -> 6e17
0.04       -> 4e16
-0.01      -> -1e16
```

The unit itself is not a currency unit. It is a numerical scaling convention.

---

## Multiplication

For two unsigned WAD values \(x_W\) and \(y_W\),

\[
xy
\approx
\frac{x_Wy_W}{W}.
\]

The implementation therefore computes

```text
mulWad(x, y) = floor(x * y / 1e18)
```

using a full-precision `mulDiv` routine.

The intermediate product may require up to 512 bits even when the final result
fits into 256 bits.

Using a full-precision multiplication/division routine avoids unnecessary
overflow from evaluating the intermediate product directly in 256 bits.

---

## Division

For WAD values,

\[
\frac{x}{y}
\approx
\frac{x_W W}{y_W}.
\]

The implementation computes

```text
divWad(x, y) = floor(x * 1e18 / y)
```

and rejects division by zero.

As with multiplication, full-precision intermediate arithmetic is used where
required.

---

## Signed arithmetic

Rates, carry values, logarithms, and normal-distribution arguments may be
negative.

The engine therefore uses signed WAD arithmetic for quantities such as

\[
r,
\quad
q,
\quad
\mu_A,
\quad
d_1,
\quad
d_2.
\]

Conversion between signed and unsigned representations must be explicit.

A negative signed value must not silently become an unsigned integer.

---

## Rounding

Integer division truncates.

Consequently, fixed-point expressions generally satisfy

\[
\widehat f(x)
\ne
f(x)
\]

exactly, where \(\widehat f\) denotes the Solidity numerical implementation.

A single truncation may be very small, but repeated operations can accumulate
error.

This is particularly relevant for:

- exponential series,
- logarithmic series,
- double summation of moments,
- moment ratios,
- finite differences,
- values close to mathematical boundaries.

No claim of exact real-number arithmetic is made.

---

## Exponential function

`TranscendentalMath.exp` evaluates

\[
e^x
\]

for signed WAD input.

The implementation uses range reduction

\[
x = k\ln 2 + r,
\]

so that

\[
e^x = 2^k e^r.
\]

The reduced exponential is evaluated using a finite series.

Range reduction is important because directly evaluating a Taylor series far
from zero would converge slowly and produce poor fixed-point behavior.

The current implementation explicitly limits the supported input domain.

Inputs outside that domain are considered numerical-domain errors rather than
values for which arbitrary saturation behavior should be assumed.

---

## Logarithm

`TranscendentalMath.ln` evaluates

\[
\ln x
\]

for positive unsigned WAD input.

The argument is normalized into a range near one and the logarithm is then
evaluated using the identity

\[
\ln m
=
2
\left(
z
+
\frac{z^3}{3}
+
\frac{z^5}{5}
+
\cdots
\right),
\]

where

\[
z =
\frac{m-1}{m+1}.
\]

The power-of-two normalization is restored through multiples of

\[
\ln 2.
\]

The logarithm is undefined for

\[
x \le 0.
\]

Since the Solidity API receives an unsigned argument, zero is the relevant
explicit invalid boundary.

---

## exp / ln consistency

For values inside the supported numerical domain, validation checks relations
such as

\[
\ln(e^x) \approx x
\]

and

\[
e^{\ln x} \approx x.
\]

These are numerical consistency checks.

They do not imply that either implementation is exact.

A tolerance is required because both functions are approximations evaluated
using integer arithmetic.

---

## Normal PDF

The standard normal probability density is

\[
\phi(x)
=
\frac{1}{\sqrt{2\pi}}
e^{-x^2/2}.
\]

The implementation uses a fixed WAD representation of

\[
\frac{1}{\sqrt{2\pi}}.
\]

Useful structural checks include

\[
\phi(0)
=
\frac{1}{\sqrt{2\pi}},
\]

\[
\phi(-x)=\phi(x),
\]

and decreasing density as \(|x|\) moves sufficiently far from zero.

---

## Normal CDF

The standard normal CDF is

\[
\Phi(x)
=
P(Z\le x).
\]

The Solidity implementation uses a deterministic polynomial approximation
rather than numerical integration.

For positive \(x\), the approximation has the general structure

\[
\Phi(x)
\approx
1 -
\phi(x)
P(t),
\]

with

\[
t =
\frac{1}{1+px}.
\]

Negative inputs use normal symmetry:

\[
\Phi(-x)
=
1-\Phi(x).
\]

The implementation also clamps sufficiently extreme tails to zero or one.

This avoids spending computation on regions where the fixed-point output is
already effectively saturated.

---

## CDF error and pricing error

An error in \(\Phi(x)\) is not numerically identical to an error in the final
option price.

The pricing expression is

\[
V
=
e^{-rT}
\left[
M_1\Phi(d_1)
-
K\Phi(d_2)
\right].
\]

Therefore CDF errors are multiplied by economically scaled quantities such as
\(M_1\) and \(K\).

Validation should consequently test both:

- the CDF itself,
- the final price.

Testing only primitive-function error is insufficient.

---

## Square root

The fitted lognormal standard deviation is

\[
\sigma_A
=
\sqrt{\sigma_A^2}.
\]

Because \(\sigma_A^2\) is WAD-scaled, the integer square-root calculation must
preserve the fixed-point scale.

Conceptually,

\[
\sigma_{A,W}
=
\sqrt{
\sigma_{A,W}^2 W
}.
\]

The implementation uses an integer square-root method rather than converting
to floating point.

---

## Moment ratio

The fitted log variance is

\[
\sigma_A^2
=
\ln
\left(
\frac{M_2}{M_1^2}
\right).
\]

Mathematically,

\[
M_2 \ge M_1^2,
\]

and therefore

\[
\frac{M_2}{M_1^2}
\ge 1.
\]

Finite-precision arithmetic complicates the boundary case.

For a mathematically deterministic average,

\[
M_2=M_1^2,
\]

but independently rounded calculations may produce either

\[
\widehat M_2 >
\widehat {M_1^2}
\]

or

\[
\widehat M_2 <
\widehat {M_1^2}.
\]

A tiny discrepancy near this boundary must not automatically be interpreted as
positive or negative economic variance.

This case requires explicit numerical policy.

---

## Zero-variance policy

The mathematical rule is simple:

\[
M_2=M_1^2
\quad\Rightarrow\quad
\sigma_A^2=0.
\]

The implementation should distinguish:

```text
materially invalid moments
```

from

```text
small fixed-point discrepancy around the deterministic boundary
```

rather than accepting every negative discrepancy or reverting on every
single-unit difference.

Any tolerance introduced for this purpose must:

- be explicit,
- be narrowly scoped,
- have tests around both sides of the boundary,
- not mask materially inconsistent moments.

Until those bounds are validated, the repository should not claim a formal
numerical error guarantee.

---

## Finite-difference Greeks

Delta and Vega are currently evaluated by finite differences.

For a function \(V(x)\), the central approximation is

\[
V'(x)
\approx
\frac{
V(x+h)-V(x-h)
}{
2h
}.
\]

The truncation error decreases as \(h\) becomes smaller only until numerical
rounding begins to dominate.

Therefore the smallest possible integer bump is not automatically the best
bump.

The current implementation uses explicit bump conventions so that Greek
outputs remain deterministic.

Changing a bump size changes the numerical definition of the reported Greek
and should therefore be treated as a versioned behavior change.

---

## Boundary finite differences

Central differences cannot always be used at a model boundary.

For example,

\[
\sigma \ge 0.
\]

At

\[
\sigma=0,
\]

the point

\[
\sigma-h
\]

is outside the valid model domain.

The implementation therefore uses a one-sided difference at this boundary.

This means the zero-volatility Vega calculation has different truncation
properties from an interior central difference.

---

## Overflow domains

Fixed-point scaling does not remove integer limits.

Potentially large expressions include:

\[
S_0^2,
\]

\[
e^x,
\]

moment sums,

\[
n^2,
\]

and finite-difference intermediate values.

The existence of a mathematical result does not imply that every possible
256-bit encoded input is numerically supported.

The engine should eventually define explicit operational bounds for:

- spot,
- strike,
- volatility,
- rates,
- dividend yield,
- maturity,
- observation count.

Until those bounds are formally established and enforced, arbitrary extreme
inputs should not be considered supported.

---

## Observation count

The current second-moment implementation performs a double sum.

Its computational cost grows approximately as

\[
n^2.
\]

This creates two separate concerns:

1. arithmetic complexity,
2. EVM gas consumption.

A mathematically valid observation count may therefore still be operationally
unsuitable for an onchain call.

A production-oriented interface should enforce a tested upper bound rather
than accepting an effectively unbounded `uint256`.

---

## Numerical reference layers

The repository distinguishes three useful references.

### Mathematical identities

These test properties that should hold independently of implementation details.

Examples include

\[
\Phi(0)=0.5
\]

and, under the model,

\[
M_2 \ge M_1^2.
\]

### Floating-point reference

`reference/pricing.ts` uses native floating-point transcendental functions.

It is useful for detecting Solidity fixed-point implementation differences.

It is not itself an arbitrary-precision proof.

### Monte Carlo benchmark

The simulation benchmark samples the underlying stochastic model directly.

It is useful for studying the pricing approximation.

It contains sampling uncertainty and therefore reports standard error.

These three layers answer different questions and should not be substituted
for one another.

---

## Tolerances

Tests use tolerances where exact integer equality is not mathematically
appropriate.

A tolerance is part of a test specification, not evidence that an error is
acceptable in production.

The current parity tests begin with explicit tolerances for:

```text
moment comparison
variance comparison
price comparison
```

Those values are provisional.

They should be tightened or otherwise revised using observed numerical error
across a documented input domain.

They must not be widened solely to make a failing test pass.

---

## Error budget

A useful validation decomposition is

\[
\epsilon_{\text{observed}}
=
\epsilon_{\text{model}}
+
\epsilon_{\text{distribution}}
+
\epsilon_{\text{transcendental}}
+
\epsilon_{\text{fixed-point}}
+
\epsilon_{\text{reference}}.
\]

Not every experiment contains every term.

For example, Solidity-to-TypeScript parity under identical formulas is mainly
concerned with

\[
\epsilon_{\text{transcendental}}
+
\epsilon_{\text{fixed-point}}.
\]

A comparison against Monte Carlo additionally exposes the distribution
approximation and sampling uncertainty.

---

## Determinism

For identical encoded inputs and identical engine code, the Solidity
calculation has no random component.

Therefore:

```text
same inputs
+ same code
= same integer outputs
```

This is what deterministic means in the current engine.

It does not mean:

```text
exact arithmetic
```

and it does not mean:

```text
exact market price
```

Determinism and correctness are separate properties.

---

## Numerical hardening checklist

Before treating the engine as production-oriented numerical infrastructure,
the following should be established:

- explicit supported input domains,
- overflow tests at every domain boundary,
- validated zero-variance handling,
- measured `exp` error across its supported range,
- measured `ln` error across its supported range,
- measured normal-CDF error across its supported range,
- Solidity/reference parity across a broad scenario grid,
- finite-difference stability tests,
- maximum supported observation count,
- gas measurements for supported observation counts,
- fuzz and invariant tests,
- independently reviewed numerical assumptions.

Until then, the engine should be described as research software.

---

## Principle

The numerical design follows one rule:

> numerical approximations should be explicit, bounded by tests, and kept
> separate from financial-model assumptions.

A deterministic result is useful only when the numerical path that produced it
is inspectable and reproducible.
