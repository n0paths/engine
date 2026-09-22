[![test](https://github.com/n0paths/n0paths-/actions/workflows/test.yml/badge.svg)](https://github.com/n0paths/n0paths-/actions/workflows/test.yml)

# n0paths engine

**Deterministic pricing primitives for onchain markets.**

`n0paths` is an experimental Solidity pricing engine for derivatives whose payoff depends on a distribution that can be approximated from deterministic moments.

The first implementation prices a discretely monitored arithmetic-average Asian call under risk-neutral geometric Brownian motion (GBM), using exact first and second moments of the arithmetic average followed by a lognormal moment-matching approximation.

The objective is a pricing path that is deterministic, reproducible, and suitable for further investigation in constrained execution environments such as the EVM.

> Research software. Not audited. Not production-ready.

---

## Model

For observation times

\[
t_i = \frac{iT}{n},
\qquad i = 1,\ldots,n
\]

define the arithmetic average

\[
A = \frac{1}{n}\sum_{i=1}^{n}S(t_i).
\]

The call payoff at expiry is

\[
(A-K)^+.
\]

Under risk-neutral GBM,

\[
\frac{dS_t}{S_t}
=
(r-q)\,dt+\sigma\,dW_t,
\]

where:

- \(S_0\) is spot,
- \(K\) is strike,
- \(T\) is time to expiry,
- \(r\) is the continuously compounded risk-free rate,
- \(q\) is the continuous dividend/carry yield,
- \(\sigma\) is volatility.

The engine computes the first two moments of \(A\).

### First moment

\[
M_1
=
E[A]
=
\frac{1}{n}
\sum_{i=1}^{n}
S_0 e^{(r-q)t_i}.
\]

### Second moment

\[
M_2
=
E[A^2]
=
\frac{1}{n^2}
\sum_{i=1}^{n}
\sum_{j=1}^{n}
S_0^2
e^{
(r-q)(t_i+t_j)
+
\sigma^2\min(t_i,t_j)
}.
\]

These moments are exact under the stated discrete-monitoring GBM assumptions, subject to numerical fixed-point error in the Solidity implementation.

---

## Lognormal moment matching

The arithmetic average itself is not generally lognormal.

`n0paths` therefore fits a lognormal random variable to \(M_1\) and \(M_2\).

Assume

\[
\ln A
\sim
N(\mu_A,\sigma_A^2).
\]

Then

\[
\sigma_A^2
=
\ln\left(
\frac{M_2}{M_1^2}
\right)
\]

and

\[
\mu_A
=
\ln(M_1)
-
\frac{1}{2}\sigma_A^2.
\]

For the fitted distribution,

\[
d_2
=
\frac{\mu_A-\ln K}{\sigma_A},
\]

\[
d_1
=
d_2+\sigma_A.
\]

The undiscounted expected call payoff is approximated by

\[
E[(A-K)^+]
\approx
M_1\Phi(d_1)
-
K\Phi(d_2),
\]

and the time-zero price is

\[
V_0
=
e^{-rT}
E[(A-K)^+].
\]

Here \(\Phi\) denotes the standard normal CDF.

---

## Architecture

```text
Market inputs
     │
     ▼
┌─────────────────────┐
│    AsianMoments     │
│                     │
│  exact M1 and M2    │
│  under GBM          │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│    AsianPricing     │
│                     │
│ lognormal moment    │
│ matching            │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ NormalDistribution  │
│ TranscendentalMath  │
│ FixedPointMath      │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   N0PathsEngine     │
│                     │
│ price + risk API    │
└─────────────────────┘
```

The implementation is split into small components so that numerical primitives, stochastic-model moments, distribution fitting, and the public engine interface can be tested independently.

---

## Repository

```text
src/
├── N0PathsEngine.sol
├── interfaces/
│   └── IPricingEngine.sol
└── libraries/
    ├── FixedPointMath.sol
    ├── TranscendentalMath.sol
    ├── NormalDistribution.sol
    ├── AsianMoments.sol
    └── AsianPricing.sol

test/
├── N0PathsEngine.t.sol
├── Math.t.sol
├── AsianMoments.t.sol
└── AsianPricing.t.sol

reference/
└── pricing.ts

scripts/
└── generate-vectors.ts
```

---

## Numerical convention

Solidity values use 18-decimal fixed-point arithmetic.

```text
1.00        -> 1e18
100.00      -> 100e18
60% vol     -> 0.60e18
4% rate     -> 0.04e18
1 year      -> 1e18
```

For example:

```solidity
IPricingEngine.MarketState memory market =
    IPricingEngine.MarketState({
        spot: 100e18,
        volatility: 60e16,
        riskFreeRate: 4e16,
        dividendYield: 0
    });

IPricingEngine.AsianOption memory option =
    IPricingEngine.AsianOption({
        strike: 100e18,
        timeToExpiry: 1e18,
        observations: 30
    });
```

Observation times are equally spaced and exclude \(t=0\):

\[
t_i=iT/n.
\]

The final observation occurs at \(T\).

---

## Public API

### Price

```solidity
function priceAsianCall(
    MarketState calldata market,
    AsianOption calldata option
)
    external
    pure
    returns (PriceResult memory result);
```

The result exposes more than the final scalar price so the numerical path can be inspected:

```solidity
struct PriceResult {
    uint256 price;
    uint256 undiscountedPayoff;
    uint256 discountFactor;
    Distribution distribution;
}
```

The fitted distribution contains:

```solidity
struct Distribution {
    uint256 firstMoment;
    uint256 secondMoment;
    uint256 effectiveVariance;
    int256 logMean;
}
```

### Greeks

```solidity
function greeksAsianCall(
    MarketState calldata market,
    AsianOption calldata option
)
    external
    pure
    returns (Greeks memory result);
```

The current implementation exposes:

```solidity
struct Greeks {
    int256 delta;
    int256 vega;
}
```

Delta and Vega are currently calculated using deterministic finite differences.

Vega is expressed per `1.00` absolute change in volatility. Divide it by `100` for sensitivity to a one-percentage-point volatility move.

---

## Reference implementation

`reference/pricing.ts` is an independent off-chain implementation of the same model.

It intentionally uses JavaScript floating-point arithmetic together with native `Math.exp` and `Math.log`, rather than reproducing the Solidity fixed-point implementation.

Run it with:

```bash
npm install
npm run reference
```

It reports the intermediate quantities used by the pricing model, including:

```text
M1
M2
effective variance
effective volatility
log mean
d1
d2
expected payoff
discount factor
price
delta
vega
```

The reference implementation is intended to help distinguish model-level differences from Solidity fixed-point and approximation errors.

---

## Reference vectors

Reference scenarios can be generated with:

```bash
npm run vectors
```

This writes:

```text
reference/vectors.json
```

The scenarios include variations in:

- volatility,
- moneyness,
- maturity,
- dividend/carry yield,
- interest rates,
- observation count,
- zero volatility.

A single-observation case is also included.

When

\[
n=1,
\]

the arithmetic average reduces to

\[
A=S(T).
\]

Under GBM, \(S(T)\) is exactly lognormal. This provides a useful limiting case for checking the moment-matching implementation against the corresponding European call calculation.

---

## Testing

Run the Solidity suite:

```bash
forge test
```

Run with detailed traces:

```bash
forge test -vvv
```

Run formatting checks:

```bash
forge fmt --check
```

Type-check the reference implementation:

```bash
npx tsc --noEmit
```

Or run the repository checks individually:

```bash
forge build
forge test
npm run reference
npm run vectors
```

GitHub Actions is configured to run the Solidity and TypeScript validation paths automatically.

---

## What is deterministic here?

For fixed inputs and a fixed implementation, the pricing path contains no stochastic sampling step.

Conceptually:

```text
market state
    ↓
GBM moments
    ↓
distribution parameters
    ↓
expected payoff
    ↓
discounted price
```

This removes sampling variance from the pricing computation itself.

It does **not** remove:

- model risk,
- parameter-estimation error,
- oracle risk,
- approximation error,
- fixed-point numerical error,
- implementation risk.

In particular:

> zero sampling error does not imply zero pricing error.

---

## Approximation boundary

The distinction between exact and approximate parts of the method is important.

Under the stated GBM model and observation schedule:

```text
M1                         exact model quantity
M2                         exact model quantity
lognormal fit              approximation
payoff under fitted law    approximation
Solidity arithmetic        finite precision
```

The arithmetic average of correlated lognormal prices is not itself generally lognormal.

The engine therefore should not be described as producing an exact arithmetic Asian option price.

---

## Current limitations

This repository is an experimental research implementation.

Current limitations include:

- arithmetic Asian calls only,
- discrete equally spaced future observations,
- GBM market dynamics,
- constant volatility,
- constant continuously compounded rates and carry,
- lognormal moment matching,
- 18-decimal fixed-point arithmetic,
- approximate transcendental functions,
- approximate normal CDF,
- finite-difference Greeks,
- \(O(n^2)\) second-moment computation,
- no oracle integration,
- no volatility-estimation module,
- no production deployment assumptions.

The current \(O(n^2)\) moment implementation prioritizes transparency of the mathematical formula over gas optimization. A production-oriented implementation would require further numerical, complexity, and gas analysis.

---

## Security

This code has not been audited.

Do not use it to custody funds, settle production derivatives, or make assumptions about economic safety without independent review.

Important areas for further hardening include:

- explicit input-domain bounds,
- overflow analysis,
- extreme rate and volatility behavior,
- maximum observation counts,
- numerical error bounds,
- gas-denial considerations,
- approximation error analysis,
- adversarial oracle inputs,
- differential testing against independent implementations.

---

## Status

`n0paths` is currently a research prototype.

The repository is being built around three separate questions:

1. **Model correctness** — are the mathematical quantities implemented as specified?
2. **Numerical correctness** — how closely does fixed-point Solidity reproduce the reference calculation?
3. **Execution practicality** — what accuracy, bytecode, and gas trade-offs appear under EVM constraints?

Claims about accuracy, gas cost, or production suitability should be backed by reproducible benchmarks before being treated as project results.

---

## License

MIT
