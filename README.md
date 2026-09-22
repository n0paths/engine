# n0paths engine

Deterministic pricing primitives for onchain markets.

[![test](https://github.com/n0paths/engine/actions/workflows/test.yml/badge.svg)](https://github.com/n0paths/engine/actions/workflows/test.yml)

`n0paths/engine` is an experimental pricing engine for deterministic derivatives valuation.

The first implemented instrument is a discretely monitored arithmetic Asian call under risk-neutral geometric Brownian motion.

The engine computes the first two moments of the arithmetic average analytically, fits a lognormal distribution to those moments, and evaluates the resulting call payoff deterministically.

```text
market state
     │
     ▼
GBM moment equations
     │
     ▼
exact M₁ and M₂
     │
     ▼
lognormal moment fit
     │
     ▼
deterministic payoff approximation
     │
     ▼
discounted price
```

The same inputs produce the same outputs.

---

## Model

Under the risk-neutral measure, the underlying follows geometric Brownian motion:

$$
dS_t = (r-q)S_t\,dt + \sigma S_t\,dW_t
$$

where:

- $S_t$ is the underlying price,
- $r$ is the continuously compounded risk-free rate,
- $q$ is the continuous dividend or convenience yield,
- $\sigma$ is volatility,
- $W_t$ is a standard Brownian motion.

The engine currently assumes constant $r$, $q$, and $\sigma$ over the life of the option.

---

## Arithmetic Asian call

For $n$ equally spaced future observations,

$$
t_i = \frac{iT}{n},
\qquad i=1,\ldots,n
$$

where $T$ is time to expiry.

The observation schedule excludes $t=0$ and includes $T$.

The arithmetic average is

$$
A =
\frac{1}{n}
\sum_{i=1}^{n} S(t_i)
$$

and the call payoff at expiry is

$$
(A-K)^+
=
\max(A-K,0)
$$

where $K$ is the strike.

---

## First moment

Under risk-neutral GBM,

$$
\mathbb{E}[S(t_i)]
=
S_0 e^{(r-q)t_i}
$$

therefore the first moment of the arithmetic average is

$$
M_1
=
\mathbb{E}[A]
=
\frac{S_0}{n}
\sum_{i=1}^{n}
e^{(r-q)t_i}.
$$

This quantity is computed directly from the model assumptions.

---

## Second moment

For two monitoring dates $t_i$ and $t_j$,

$$
\mathbb{E}[S(t_i)S(t_j)]
=
S_0^2
\exp
\left(
(r-q)(t_i+t_j)
+
\sigma^2\min(t_i,t_j)
\right).
$$

The second moment of the arithmetic average is therefore

$$
M_2
=
\mathbb{E}[A^2]
=
\frac{S_0^2}{n^2}
\sum_{i=1}^{n}
\sum_{j=1}^{n}
\exp
\left(
(r-q)(t_i+t_j)
+
\sigma^2\min(t_i,t_j)
\right).
$$

The first and second moments are analytical under the stated discrete GBM assumptions.

The current implementation evaluates the second moment in $O(n^2)$ time.

---

## Lognormal moment matching

The arithmetic average of lognormal variables is not itself generally lognormal.

The engine therefore approximates $A$ with a lognormal random variable whose first two moments match $M_1$ and $M_2$.

Let

$$
\ln A
\sim
\mathcal{N}(\mu_A,\sigma_A^2).
$$

Matching the first two moments gives

$$
\sigma_A^2
=
\ln
\left(
\frac{M_2}{M_1^2}
\right)
$$

and

$$
\mu_A
=
\ln(M_1)
-
\frac{1}{2}\sigma_A^2.
$$

This is the approximation boundary of the pricing method:

> $M_1$ and $M_2$ are analytical under the model.  
> The lognormal representation of the arithmetic average is an approximation.

---

## Pricing

For non-zero effective variance,

$$
d_2
=
\frac{
\mu_A-\ln K
}{
\sigma_A
}
$$

and

$$
d_1
=
d_2+\sigma_A.
$$

The undiscounted expected call payoff is approximated by

$$
\mathbb{E}[(A-K)^+]
\approx
M_1\Phi(d_1)
-
K\Phi(d_2),
$$

where $\Phi(\cdot)$ is the standard normal cumulative distribution function.

The time-zero price is

$$
V_0
=
e^{-rT}
\left[
M_1\Phi(d_1)
-
K\Phi(d_2)
\right].
$$

For a degenerate zero-variance distribution, the engine instead evaluates the deterministic payoff directly:

$$
V_0
=
e^{-rT}
\max(M_1-K,0).
$$

---

## Architecture

```text
src/
├── N0PathsEngine.sol
├── interfaces/
│   └── IPricingEngine.sol
└── libraries/
    ├── AsianMoments.sol
    ├── AsianPricing.sol
    ├── FixedPointMath.sol
    ├── NormalDistribution.sol
    └── TranscendentalMath.sol
```

The pricing pipeline is intentionally separated into numerical components:

```text
AsianMoments
     │
     ▼
M₁, M₂
     │
     ▼
AsianPricing
     │
     ├── lognormal fit
     ├── d₁ / d₂
     ├── normal CDF
     └── discounting
     │
     ▼
N0PathsEngine
```

`N0PathsEngine.sol` exposes the external pricing interface while the libraries contain the underlying numerical routines.

---

## Units

The Solidity implementation uses 18-decimal fixed-point arithmetic.

```text
1.0       = 1e18
100 USD   = 100e18
60% vol   = 0.60e18
4% rate   = 0.04e18
1 year    = 1e18
```

For example:

```solidity
uint256 spot = 100e18;
uint256 strike = 100e18;
uint256 volatility = 0.60e18;
int256 riskFreeRate = 0.04e18;
int256 dividendYield = 0;
uint256 timeToExpiry = 1e18;
uint256 observations = 30;
```

Rates and yields are signed.

Spot, strike, volatility, time to expiry, and observations are represented by unsigned values.

---

## Interface

The primary entry point is:

```solidity
priceAsianCall(
    MarketState calldata market,
    AsianOption calldata option
)
```

The market state contains:

```solidity
struct MarketState {
    uint256 spot;
    uint256 volatility;
    int256 riskFreeRate;
    int256 dividendYield;
}
```

The option definition contains:

```solidity
struct AsianOption {
    uint256 strike;
    uint256 timeToExpiry;
    uint256 observations;
}
```

The returned pricing result includes the price together with intermediate distribution information used by the engine.

---

## Greeks

The engine also exposes numerical Greeks for the arithmetic Asian call.

The current interface computes:

```text
Delta
Vega
```

These are obtained using deterministic finite differences around the same pricing function.

Delta uses a central spot bump.

Vega uses a central volatility bump when possible and a forward difference close to zero volatility.

The Greek calculation therefore inherits both the pricing approximation and finite-difference numerical error.

---

## Determinism

The Solidity pricing path does not depend on random sampling.

For fixed:

```text
spot
strike
volatility
risk-free rate
dividend yield
time to expiry
observation count
```

the same implementation produces the same result.

This removes Monte Carlo sampling variance from the onchain pricing computation.

It does **not** remove model error, approximation error, fixed-point error, or implementation error.

```text
0 sampling error ≠ 0 pricing error
```

---

## Numerical methods

The engine implements the numerical primitives required by the pricing model directly in Solidity.

These include:

```text
fixed-point multiplication and division
exp(x)
ln(x)
sqrt(x)
normal PDF
normal CDF
```

The implementation is designed around deterministic WAD arithmetic rather than floating-point arithmetic.

Approximation and rounding error therefore remain part of the numerical error budget.

See:

```text
docs/METHOD.md
docs/NUMERICS.md
```

for the mathematical and numerical details.

---

## Reference implementation

A TypeScript implementation is included under:

```text
reference/
```

It provides an independent floating-point representation of the pricing equations and is used to generate reference vectors.

```text
reference/pricing.ts
scripts/generate-vectors.ts
reference/vectors.json
```

The reference implementation is intended for validation and development.

It is not an oracle and should not be interpreted as an external source of market truth.

---

## Benchmarks

Experimental validation is maintained separately in:

`n0paths/benchmarks`

The benchmark suite compares the deterministic approximation against seeded Monte Carlo experiments using the same GBM assumptions and observation schedule.

The separation is intentional:

```text
engine
  → implementation

benchmarks
  → experiments and validation
```

Monte Carlo estimates should always be interpreted together with their sampling uncertainty.

---

## Testing

The repository uses Foundry for Solidity tests.

```bash
forge build
forge test
```

The CI workflow also runs fuzz testing:

```bash
forge test --fuzz-runs 10000
```

The test suite is intended to cover properties such as:

```text
deterministic repeatability
moment calculations
pricing monotonicity
zero-volatility behavior
fixed-point numerical primitives
reference-vector consistency
```

GitHub Actions runs the Solidity and TypeScript reference checks on pushes and pull requests.

---

## Approximation boundary

The engine should not be described as an exact closed-form solution for an arithmetic Asian option.

The distinction is:

```text
GBM first moment                    analytical
GBM second moment                   analytical
lognormal fit                       approximate
normal CDF implementation           numerical approximation
Solidity fixed-point arithmetic     numerical approximation
finite-difference Greeks            numerical approximation
```

The deterministic property concerns execution:

```text
same inputs → same outputs
```

It does not imply:

```text
same model → exact market price
```

---

## Current limitations

The current implementation is experimental.

Important limitations include:

- constant volatility, rates, and dividend yield,
- risk-neutral GBM dynamics,
- equally spaced future observations,
- no observation at $t=0$,
- lognormal moment matching for the arithmetic average,
- $O(n^2)$ second-moment evaluation,
- fixed-point approximation error,
- numerical normal-CDF approximation,
- finite-difference Greeks,
- no claim of production readiness or audit status.

The current engine should be treated as research software.

---

## Repository layout

```text
engine/
├── .github/
│   └── workflows/
│       └── test.yml
├── docs/
│   ├── METHOD.md
│   └── NUMERICS.md
├── reference/
│   ├── pricing.ts
│   └── vectors.json
├── scripts/
│   ├── benchmark.ts
│   └── generate-vectors.ts
├── src/
│   ├── interfaces/
│   │   └── IPricingEngine.sol
│   ├── libraries/
│   │   ├── AsianMoments.sol
│   │   ├── AsianPricing.sol
│   │   ├── FixedPointMath.sol
│   │   ├── NormalDistribution.sol
│   │   └── TranscendentalMath.sol
│   └── N0PathsEngine.sol
├── test/
├── foundry.toml
├── package.json
├── tsconfig.json
└── README.md
```

---

## Status

Experimental research software.

The project currently focuses on making the pricing method explicit, deterministic, reproducible, and testable before expanding the supported model and instrument surface.

No audit or production deployment is claimed.

---

## License

MIT
