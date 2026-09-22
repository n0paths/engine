# Method

## Scope

`n0paths` currently implements a deterministic approximation for a
discretely monitored arithmetic-average Asian call.

The implementation separates three layers:

1. stochastic-model assumptions,
2. deterministic moment calculation,
3. payoff approximation from a fitted distribution.

The current model is intentionally narrow. It is a research primitive rather
than a general derivatives framework.

---

## Contract

Consider an arithmetic-average Asian call with payoff

\[
(A-K)^+
\]

where

\[
A =
\frac{1}{n}
\sum_{i=1}^{n} S(t_i).
\]

The observation schedule is

\[
t_i = \frac{iT}{n},
\qquad
i=1,\ldots,n.
\]

Therefore:

- \(t=0\) is not included in the average,
- observations are equally spaced,
- the final observation occurs at \(T\),
- all observations have equal weight.

This convention is part of the model definition.

Changing the observation schedule changes the instrument being priced.

---

## Market model

The underlying follows risk-neutral geometric Brownian motion:

\[
\frac{dS_t}{S_t}
=
(r-q)\,dt
+
\sigma\,dW_t.
\]

Equivalently,

\[
S_t
=
S_0
\exp
\left[
\left(
r-q-\frac{1}{2}\sigma^2
\right)t
+
\sigma W_t
\right].
\]

Parameters are assumed constant over the pricing horizon:

\[
S_0 > 0,
\]

\[
\sigma \ge 0,
\]

with constant \(r\), \(q\), and \(T>0\).

The current implementation does not model:

- stochastic volatility,
- jumps,
- local volatility,
- discrete dividends,
- stochastic interest rates,
- stochastic carry,
- volatility smiles or surfaces,
- path-dependent volatility dynamics.

Those may be separate model extensions rather than implicit modifications to
the current method.

---

## First moment

For risk-neutral GBM,

\[
E[S(t_i)]
=
S_0 e^{(r-q)t_i}.
\]

Therefore,

\[
M_1
=
E[A]
=
\frac{1}{n}
\sum_{i=1}^{n}
S_0 e^{(r-q)t_i}.
\]

For the specified GBM model and observation schedule, this is an exact model
quantity.

The Solidity implementation evaluates the expression using fixed-point
arithmetic, so the computed representation may contain numerical rounding
error.

---

## Second moment

Starting from

\[
A^2
=
\frac{1}{n^2}
\sum_{i=1}^{n}
\sum_{j=1}^{n}
S(t_i)S(t_j),
\]

we require the joint GBM moment

\[
E[S(t_i)S(t_j)].
\]

Because

\[
\operatorname{Cov}(W_{t_i},W_{t_j})
=
\min(t_i,t_j),
\]

the joint moment is

\[
E[S(t_i)S(t_j)]
=
S_0^2
\exp
\left[
(r-q)(t_i+t_j)
+
\sigma^2\min(t_i,t_j)
\right].
\]

Hence

\[
M_2
=
E[A^2]
=
\frac{1}{n^2}
\sum_{i=1}^{n}
\sum_{j=1}^{n}
S_0^2
\exp
\left[
(r-q)(t_i+t_j)
+
\sigma^2\min(t_i,t_j)
\right].
\]

Again, this is an exact moment under the stated model assumptions.

The current Solidity implementation evaluates the double sum directly and
therefore has computational complexity

\[
O(n^2).
\]

This representation is intentionally transparent. Algebraic reduction and gas
optimization can be investigated separately without changing the model
definition.

---

## Variance identity

The arithmetic-average variance is

\[
\operatorname{Var}(A)
=
M_2-M_1^2.
\]

Therefore a valid pair of moments must satisfy

\[
M_2 \ge M_1^2.
\]

For deterministic cases,

\[
M_2=M_1^2.
\]

An implementation using finite-precision arithmetic may produce a small
rounding discrepancy around this boundary. Such discrepancies are numerical
effects, not model variance.

They should be handled explicitly rather than interpreted as economic
uncertainty.

---

## Lognormal moment matching

A sum of correlated lognormal random variables is not generally lognormal.

Therefore the arithmetic average

\[
A =
\frac{1}{n}
\sum_i S(t_i)
\]

does not generally have a lognormal distribution.

The pricing method approximates its distribution by a lognormal random
variable \(\tilde A\):

\[
\ln \tilde A
\sim
N(\mu_A,\sigma_A^2).
\]

The fitted distribution is required to reproduce the first two moments:

\[
E[\tilde A]=M_1,
\]

\[
E[\tilde A^2]=M_2.
\]

For a lognormal random variable,

\[
E[\tilde A]
=
e^{\mu_A+\frac{1}{2}\sigma_A^2},
\]

and

\[
E[\tilde A^2]
=
e^{2\mu_A+2\sigma_A^2}.
\]

Solving for the fitted parameters gives

\[
\sigma_A^2
=
\ln
\left(
\frac{M_2}{M_1^2}
\right),
\]

and

\[
\mu_A
=
\ln(M_1)
-
\frac{1}{2}\sigma_A^2.
\]

The notation \(\sigma_A^2\) here describes the variance of the fitted
**logarithm**, not the variance of \(A\) itself.

---

## Expected payoff

For the fitted lognormal variable,

\[
E[(\tilde A-K)^+]
=
M_1\Phi(d_1)
-
K\Phi(d_2),
\]

where

\[
d_2
=
\frac{\mu_A-\ln K}{\sigma_A},
\]

and

\[
d_1
=
d_2+\sigma_A.
\]

The time-zero price is

\[
V_0
=
e^{-rT}
\left[
M_1\Phi(d_1)
-
K\Phi(d_2)
\right].
\]

The current Solidity implementation evaluates \(\Phi\) using a deterministic
normal-CDF approximation.

---

## Degenerate variance

If

\[
\sigma_A^2=0,
\]

the fitted distribution is deterministic.

In that case,

\[
A=M_1
\]

under the fitted model and the payoff reduces to

\[
(M_1-K)^+.
\]

The price is therefore

\[
V_0
=
e^{-rT}
(M_1-K)^+.
\]

This branch also avoids division by zero in \(d_1\) and \(d_2\).

---

## Single-observation limiting case

A useful model identity occurs when

\[
n=1.
\]

Then

\[
A=S(T).
\]

Under GBM, \(S(T)\) is exactly lognormal.

Its first moment is

\[
M_1
=
S_0 e^{(r-q)T},
\]

and its second moment is

\[
M_2
=
S_0^2
e^{2(r-q)T+\sigma^2T}.
\]

Therefore

\[
\ln
\left(
\frac{M_2}{M_1^2}
\right)
=
\sigma^2T.
\]

The moment-matched distribution is consequently the exact GBM terminal
distribution.

For \(n=1\), the pricing method should therefore reduce to the corresponding
European call price under the same GBM assumptions, apart from numerical
approximation in the implementation.

This identity is used as a validation test.

---

## Exact versus approximate

The method contains both exact model quantities and approximations.

| Component | Status |
| --- | --- |
| GBM first moment | Exact under model |
| GBM joint second moment | Exact under model |
| Arithmetic-average \(M_1\) | Exact under model |
| Arithmetic-average \(M_2\) | Exact under model |
| Lognormal law for arithmetic average | Approximation |
| Payoff under fitted lognormal law | Approximation |
| Solidity `exp` / `ln` | Numerical approximation |
| Solidity normal CDF | Numerical approximation |
| Solidity fixed-point representation | Finite precision |
| Finite-difference Greeks | Numerical approximation |

This distinction matters when interpreting an observed pricing difference.

A difference can originate from several separate sources:

\[
\text{total observed difference}
\]

\[
=
\text{model difference}
+
\text{distribution approximation}
+
\text{numerical approximation}
+
\text{reference uncertainty}.
\]

These components should not be reported as though they were the same error.

---

## Validation strategy

The repository uses several validation layers.

### Mathematical identities

Tests verify structural properties such as:

\[
M_2 \ge M_1^2,
\]

spot scaling,

\[
M_1(cS)=cM_1(S),
\]

\[
M_2(cS)=c^2M_2(S),
\]

and independence of \(M_1\) from volatility under GBM.

### Independent floating-point implementation

`reference/pricing.ts` implements the model using JavaScript floating-point
arithmetic and native transcendental functions.

It does not reuse the Solidity fixed-point implementation.

The purpose is differential testing.

### Reference vectors

`scripts/generate-vectors.ts` generates deterministic scenarios into

```text
reference/vectors.json
```

for comparison with Solidity results.

### Single-observation identity

The \(n=1\) case is checked against the corresponding European-call
calculation.

### Simulation benchmark

`scripts/benchmark.ts` compares the moment-matched price against a seeded
Monte Carlo simulation using exact GBM transitions between observation dates.

The simulation reports its standard error.

This benchmark is intended to investigate the distribution approximation,
rather than to define the Solidity implementation.

---

## Error interpretation

Suppose the deterministic approximation produces

\[
V_D
\]

and a Monte Carlo experiment produces

\[
V_{MC}
\pm SE.
\]

The raw difference

\[
|V_D-V_{MC}|
\]

must not automatically be interpreted as exact approximation error because
the Monte Carlo estimate itself contains sampling uncertainty.

The benchmark therefore also reports

\[
z =
\frac{V_D-V_{MC}}{SE}.
\]

A reproducible benchmark should always record at least:

- model inputs,
- observation convention,
- number of simulated paths,
- random seed or random-number method,
- Monte Carlo standard error,
- deterministic price,
- reference price.

---

## Greeks

The current public engine exposes Delta and Vega.

They are computed by deterministic finite differences around the pricing
function.

For spot \(S\),

\[
\Delta
\approx
\frac{
V(S+h_S)-V(S-h_S)
}{
2h_S
}.
\]

For volatility \(\sigma\),

\[
\nu
\approx
\frac{
V(\sigma+h_\sigma)-V(\sigma-h_\sigma)
}{
2h_\sigma
}.
\]

At the zero-volatility boundary, a forward difference is used because negative
volatility is outside the model domain.

The current Vega convention is sensitivity per `1.00` absolute volatility
change.

Therefore sensitivity per one volatility percentage point is

\[
\frac{\nu}{100}.
\]

Finite-difference Greeks introduce their own numerical error and should not be
confused with analytic derivatives of the approximation.

---

## Solidity units

The Solidity implementation uses 18-decimal fixed-point values.

\[
1
\longleftrightarrow
10^{18}.
\]

Examples:

```text
100 spot       = 100e18
100 strike     = 100e18
60% volatility = 0.60e18
4% rate        = 0.04e18
1 year         = 1e18
```

Signed quantities such as rates and fitted log means use signed WAD values.

---

## Current computational structure

For \(n\) observations:

```text
first moment      O(n)
second moment     O(n²)
distribution fit  O(1)
payoff            O(1)
```

Thus the current implementation is dominated by the second-moment double sum.

This is not assumed to be the final EVM implementation.

Any optimized formulation should be checked against the transparent
implementation and the independent reference before replacing it.

---

## Non-goals of the current method

The current implementation does not claim to provide:

- an exact arithmetic Asian option price,
- calibrated market volatility,
- an oracle design,
- an implied-volatility surface,
- production settlement guarantees,
- audited numerical bounds,
- optimal EVM gas consumption,
- universal derivatives pricing.

Those are separate research and engineering problems.

---

## Summary

The current pricing pipeline is

```text
inputs
  │
  ▼
risk-neutral GBM
  │
  ▼
exact discrete M1 and M2
  │
  ▼
moment-matched lognormal distribution
  │
  ▼
deterministic expected payoff
  │
  ▼
discounting
  │
  ▼
price
```

The central methodological boundary is:

> the moments are exact under the stated GBM assumptions; the lognormal
> representation of the arithmetic average is an approximation.

Keeping that boundary explicit is necessary for meaningful validation of the
engine.
