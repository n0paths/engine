/**
 * n0paths reference pricing implementation
 *
 * Deterministic moment-matching approximation for a discretely monitored
 * arithmetic-average Asian call under risk-neutral GBM.
 *
 * This implementation intentionally uses native floating-point arithmetic
 * and Math.exp / Math.log rather than reproducing the Solidity fixed-point
 * implementation.
 *
 * It acts as an off-chain numerical reference for:
 *   - model development
 *   - test-vector generation
 *   - Solidity parity testing
 *   - benchmark experiments
 */

export interface MarketState {
  spot: number;
  volatility: number;
  riskFreeRate: number;
  dividendYield: number;
}

export interface AsianOption {
  strike: number;
  timeToExpiry: number;
  observations: number;
}

export interface Moments {
  firstMoment: number;
  secondMoment: number;
}

export interface Distribution {
  firstMoment: number;
  secondMoment: number;
  effectiveVariance: number;
  effectiveVolatility: number;
  logMean: number;
}

export interface PriceResult {
  price: number;
  undiscountedPayoff: number;
  discountFactor: number;

  distribution: Distribution;

  d1: number | null;
  d2: number | null;
}

export interface Greeks {
  delta: number;
  vega: number;
}

const SQRT_TWO_PI = Math.sqrt(2 * Math.PI);

/**
 * Standard normal probability density function.
 */
export function normalPdf(x: number): number {
  return Math.exp(-0.5 * x * x) / SQRT_TWO_PI;
}

/**
 * Error-function approximation.
 *
 * Maximum error is sufficient for the reference/UI layer here, while
 * remaining dependency-free.
 */
export function erf(x: number): number {
  const sign = x < 0 ? -1 : 1;
  const ax = Math.abs(x);

  const p = 0.3275911;

  const a1 = 0.254829592;
  const a2 = -0.284496736;
  const a3 = 1.421413741;
  const a4 = -1.453152027;
  const a5 = 1.061405429;

  const t = 1 / (1 + p * ax);

  const polynomial =
    (((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t);

  const y =
    1 -
    polynomial *
      Math.exp(-ax * ax);

  return sign * y;
}

/**
 * Standard normal cumulative distribution function.
 */
export function normalCdf(x: number): number {
  if (x <= -10) return 0;
  if (x >= 10) return 1;

  return 0.5 * (1 + erf(x / Math.SQRT2));
}

/**
 * Validate public model inputs.
 */
export function validateInputs(
  market: MarketState,
  option: AsianOption,
): void {
  if (!Number.isFinite(market.spot) || market.spot <= 0) {
    throw new Error("spot must be positive and finite");
  }

  if (
    !Number.isFinite(market.volatility) ||
    market.volatility < 0
  ) {
    throw new Error(
      "volatility must be non-negative and finite",
    );
  }

  if (!Number.isFinite(market.riskFreeRate)) {
    throw new Error("riskFreeRate must be finite");
  }

  if (!Number.isFinite(market.dividendYield)) {
    throw new Error("dividendYield must be finite");
  }

  if (!Number.isFinite(option.strike) || option.strike <= 0) {
    throw new Error("strike must be positive and finite");
  }

  if (
    !Number.isFinite(option.timeToExpiry) ||
    option.timeToExpiry <= 0
  ) {
    throw new Error(
      "timeToExpiry must be positive and finite",
    );
  }

  if (
    !Number.isInteger(option.observations) ||
    option.observations <= 0
  ) {
    throw new Error(
      "observations must be a positive integer",
    );
  }
}

/**
 * Compute the first two moments of the arithmetic average:
 *
 *     A = (1/n) Σ S(t_i)
 *
 * with equally spaced observation times:
 *
 *     t_i = iT/n
 *
 * Under risk-neutral GBM:
 *
 *     dS/S = (r-q)dt + sigma dW
 *
 * we have:
 *
 *     E[S(t_i)]
 *       = S0 exp((r-q)t_i)
 *
 * and:
 *
 *     E[S(t_i)S(t_j)]
 *       = S0² exp(
 *           (r-q)(t_i+t_j)
 *           + sigma² min(t_i,t_j)
 *         )
 */
export function arithmeticAsianMoments(
  market: MarketState,
  option: AsianOption,
): Moments {
  validateInputs(market, option);

  const {
    spot,
    volatility,
    riskFreeRate,
    dividendYield,
  } = market;

  const {
    timeToExpiry,
    observations,
  } = option;

  const drift = riskFreeRate - dividendYield;
  const variance = volatility * volatility;

  let firstSum = 0;

  for (let i = 1; i <= observations; i += 1) {
    const ti =
      (timeToExpiry * i) /
      observations;

    firstSum +=
      spot *
      Math.exp(drift * ti);
  }

  const firstMoment =
    firstSum /
    observations;

  let secondSum = 0;

  for (let i = 1; i <= observations; i += 1) {
    const ti =
      (timeToExpiry * i) /
      observations;

    for (let j = 1; j <= observations; j += 1) {
      const tj =
        (timeToExpiry * j) /
        observations;

      const minTime =
        Math.min(ti, tj);

      const exponent =
        drift * (ti + tj) +
        variance * minTime;

      secondSum +=
        spot *
        spot *
        Math.exp(exponent);
    }
  }

  const secondMoment =
    secondSum /
    (observations * observations);

  return {
    firstMoment,
    secondMoment,
  };
}

/**
 * Fit a lognormal distribution to the first two moments.
 *
 * If:
 *
 *     ln(A) ~ N(mu_A, sigma_A²)
 *
 * then:
 *
 *     sigma_A² = ln(M2 / M1²)
 *
 *     mu_A = ln(M1) - 0.5 sigma_A²
 */
export function fitLognormal(
  moments: Moments,
): Distribution {
  const {
    firstMoment,
    secondMoment,
  } = moments;

  if (
    firstMoment <= 0 ||
    secondMoment <= 0
  ) {
    throw new Error(
      "moments must be positive",
    );
  }

  const firstMomentSquared =
    firstMoment * firstMoment;

  /*
   * Floating-point arithmetic may occasionally produce an extremely
   * small violation of M2 >= M1² in a degenerate case.
   */
  const rawRatio =
    secondMoment /
    firstMomentSquared;

  const tolerance = 1e-14;

  if (rawRatio < 1 - tolerance) {
    throw new Error(
      `invalid moments: M2/M1^2 = ${rawRatio}`,
    );
  }

  const ratio =
    Math.max(1, rawRatio);

  const effectiveVariance =
    Math.log(ratio);

  const effectiveVolatility =
    Math.sqrt(effectiveVariance);

  const logMean =
    Math.log(firstMoment) -
    0.5 * effectiveVariance;

  return {
    firstMoment,
    secondMoment,
    effectiveVariance,
    effectiveVolatility,
    logMean,
  };
}

/**
 * Price an arithmetic-average Asian call using the moment-matched
 * lognormal approximation.
 */
export function priceAsianCall(
  market: MarketState,
  option: AsianOption,
): PriceResult {
  validateInputs(market, option);

  const moments =
    arithmeticAsianMoments(
      market,
      option,
    );

  const distribution =
    fitLognormal(moments);

  const discountFactor =
    Math.exp(
      -market.riskFreeRate *
        option.timeToExpiry,
    );

  /*
   * Degenerate distribution.
   *
   * With zero effective variance the arithmetic average is deterministic,
   * so the expected payoff reduces to intrinsic value of that average.
   */
  if (
    distribution.effectiveVariance <=
    Number.EPSILON
  ) {
    const undiscountedPayoff =
      Math.max(
        distribution.firstMoment -
          option.strike,
        0,
      );

    return {
      price:
        discountFactor *
        undiscountedPayoff,

      undiscountedPayoff,
      discountFactor,

      distribution,

      d1: null,
      d2: null,
    };
  }

  const sigmaA =
    distribution.effectiveVolatility;

  const logStrike =
    Math.log(option.strike);

  const d2 =
    (
      distribution.logMean -
      logStrike
    ) /
    sigmaA;

  const d1 =
    d2 + sigmaA;

  const expectedAssetTerm =
    distribution.firstMoment *
    normalCdf(d1);

  const expectedStrikeTerm =
    option.strike *
    normalCdf(d2);

  const undiscountedPayoff =
    Math.max(
      expectedAssetTerm -
        expectedStrikeTerm,
      0,
    );

  const price =
    discountFactor *
    undiscountedPayoff;

  return {
    price,
    undiscountedPayoff,
    discountFactor,

    distribution,

    d1,
    d2,
  };
}

/**
 * Deterministic finite-difference Greeks.
 *
 * Delta:
 *
 *     [V(S+h) - V(S-h)] / 2h
 *
 * Vega:
 *
 *     [V(sigma+h) - V(sigma-h)] / 2h
 *
 * Vega is returned per 1.00 absolute volatility change.
 */
export function greeksAsianCall(
  market: MarketState,
  option: AsianOption,
): Greeks {
  validateInputs(market, option);

  const spotBump =
    market.spot * 0.0001;

  if (spotBump <= 0) {
    throw new Error(
      "spot bump is too small",
    );
  }

  const spotUp: MarketState = {
    ...market,
    spot:
      market.spot +
      spotBump,
  };

  const spotDown: MarketState = {
    ...market,
    spot:
      market.spot -
      spotBump,
  };

  const priceSpotUp =
    priceAsianCall(
      spotUp,
      option,
    ).price;

  const priceSpotDown =
    priceAsianCall(
      spotDown,
      option,
    ).price;

  const delta =
    (
      priceSpotUp -
      priceSpotDown
    ) /
    (2 * spotBump);

  const volatilityBump = 0.0001;

  const volUp: MarketState = {
    ...market,
    volatility:
      market.volatility +
      volatilityBump,
  };

  let vega: number;

  if (
    market.volatility >
    volatilityBump
  ) {
    const volDown: MarketState = {
      ...market,
      volatility:
        market.volatility -
        volatilityBump,
    };

    const priceVolUp =
      priceAsianCall(
        volUp,
        option,
      ).price;

    const priceVolDown =
      priceAsianCall(
        volDown,
        option,
      ).price;

    vega =
      (
        priceVolUp -
        priceVolDown
      ) /
      (2 * volatilityBump);
  } else {
    /*
     * At the sigma = 0 boundary use the same deterministic forward
     * difference convention as the Solidity implementation.
     */
    const basePrice =
      priceAsianCall(
        market,
        option,
      ).price;

    const priceVolUp =
      priceAsianCall(
        volUp,
        option,
      ).price;

    vega =
      (
        priceVolUp -
        basePrice
      ) /
      volatilityBump;
  }

  return {
    delta,
    vega,
  };
}

/**
 * Default research scenario used across the repository.
 */
export const DEFAULT_MARKET: MarketState = {
  spot: 100,
  volatility: 0.60,
  riskFreeRate: 0.04,
  dividendYield: 0,
};

export const DEFAULT_OPTION: AsianOption = {
  strike: 100,
  timeToExpiry: 1,
  observations: 30,
};

/**
 * Run directly:
 *
 *     npm run reference
 */
function main(): void {
  const result =
    priceAsianCall(
      DEFAULT_MARKET,
      DEFAULT_OPTION,
    );

  const greeks =
    greeksAsianCall(
      DEFAULT_MARKET,
      DEFAULT_OPTION,
    );

  console.log(
    "n0paths reference engine\n",
  );

  console.log("inputs");
  console.log({
    market: DEFAULT_MARKET,
    option: DEFAULT_OPTION,
  });

  console.log("\nmoments");
  console.log({
    M1:
      result.distribution.firstMoment,
    M2:
      result.distribution.secondMoment,
  });

  console.log("\nfitted distribution");
  console.log({
    variance:
      result.distribution.effectiveVariance,
    sigma:
      result.distribution.effectiveVolatility,
    mu:
      result.distribution.logMean,
  });

  console.log("\npricing");
  console.log({
    d1: result.d1,
    d2: result.d2,
    expectedPayoff:
      result.undiscountedPayoff,
    discountFactor:
      result.discountFactor,
    price:
      result.price,
  });

  console.log("\ngreeks");
  console.log(greeks);
}

const executedDirectly =
  process.argv[1]?.endsWith(
    "reference/pricing.ts",
  ) ||
  process.argv[1]?.endsWith(
    "reference\\pricing.ts",
  );

if (executedDirectly) {
  main();
}
