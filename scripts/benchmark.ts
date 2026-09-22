import {
  type AsianOption,
  type MarketState,
  priceAsianCall,
} from "../reference/pricing.js";

interface Scenario {
  name: string;
  market: MarketState;
  option: AsianOption;
}

interface MonteCarloResult {
  price: number;
  standardError: number;
  paths: number;
  seed: number;
}

interface BenchmarkResult {
  name: string;

  deterministicPrice: number;
  monteCarloPrice: number;
  monteCarloStandardError: number;

  absoluteError: number;
  relativeError: number;

  zScore: number | null;

  paths: number;
  seed: number;
}

const PATHS = 500_000;
const SEED = 0x6e307061; // "n0pa"

const scenarios: Scenario[] = [
  {
    name: "baseline",
    market: {
      spot: 100,
      volatility: 0.60,
      riskFreeRate: 0.04,
      dividendYield: 0,
    },
    option: {
      strike: 100,
      timeToExpiry: 1,
      observations: 30,
    },
  },
  {
    name: "low_volatility",
    market: {
      spot: 100,
      volatility: 0.20,
      riskFreeRate: 0.04,
      dividendYield: 0,
    },
    option: {
      strike: 100,
      timeToExpiry: 1,
      observations: 30,
    },
  },
  {
    name: "high_volatility",
    market: {
      spot: 100,
      volatility: 1.00,
      riskFreeRate: 0.04,
      dividendYield: 0,
    },
    option: {
      strike: 100,
      timeToExpiry: 1,
      observations: 30,
    },
  },
  {
    name: "short_maturity",
    market: {
      spot: 100,
      volatility: 0.50,
      riskFreeRate: 0.04,
      dividendYield: 0,
    },
    option: {
      strike: 100,
      timeToExpiry: 1 / 12,
      observations: 30,
    },
  },
  {
    name: "positive_yield",
    market: {
      spot: 100,
      volatility: 0.40,
      riskFreeRate: 0.05,
      dividendYield: 0.02,
    },
    option: {
      strike: 100,
      timeToExpiry: 1,
      observations: 24,
    },
  },
  {
    name: "single_observation",
    market: {
      spot: 100,
      volatility: 0.40,
      riskFreeRate: 0.03,
      dividendYield: 0,
    },
    option: {
      strike: 100,
      timeToExpiry: 1,
      observations: 1,
    },
  },
];

/**
 * Small deterministic PRNG.
 *
 * This is not cryptographic randomness. It exists only so benchmark runs
 * are reproducible across executions.
 */
class Mulberry32 {
  private state: number;

  constructor(seed: number) {
    this.state = seed >>> 0;
  }

  next(): number {
    this.state =
      (this.state + 0x6d2b79f5) >>> 0;

    let x = this.state;

    x = Math.imul(
      x ^ (x >>> 15),
      x | 1,
    );

    x ^=
      x +
      Math.imul(
        x ^ (x >>> 7),
        x | 61,
      );

    return (
      ((x ^ (x >>> 14)) >>> 0) /
      4294967296
    );
  }
}

/**
 * Box-Muller transform.
 *
 * Two standard normal samples are produced per pair of uniforms.
 */
class NormalGenerator {
  private readonly rng: Mulberry32;

  private spare: number | null = null;

  constructor(seed: number) {
    this.rng = new Mulberry32(seed);
  }

  next(): number {
    if (this.spare !== null) {
      const value = this.spare;
      this.spare = null;
      return value;
    }

    let u1 = this.rng.next();
    const u2 = this.rng.next();

    // log(0) is undefined.
    if (u1 <= 0) {
      u1 = Number.MIN_VALUE;
    }

    const radius =
      Math.sqrt(
        -2 * Math.log(u1),
      );

    const angle =
      2 * Math.PI * u2;

    const z0 =
      radius * Math.cos(angle);

    const z1 =
      radius * Math.sin(angle);

    this.spare = z1;

    return z0;
  }
}

/**
 * Monte Carlo reference for the same discrete arithmetic-average payoff.
 *
 * Exact GBM transitions are used between observation times:
 *
 * S(t + dt) =
 *   S(t) exp(
 *     (r - q - sigma^2 / 2) dt
 *     + sigma sqrt(dt) Z
 *   )
 *
 * There is therefore no Euler time-discretization error between monitoring
 * dates. Remaining statistical uncertainty is reported as standard error.
 */
function monteCarloAsianCall(
  market: MarketState,
  option: AsianOption,
  paths: number,
  seed: number,
): MonteCarloResult {
  if (
    !Number.isInteger(paths) ||
    paths <= 1
  ) {
    throw new Error(
      "paths must be an integer greater than one",
    );
  }

  const {
    spot,
    volatility,
    riskFreeRate,
    dividendYield,
  } = market;

  const {
    strike,
    timeToExpiry,
    observations,
  } = option;

  const dt =
    timeToExpiry /
    observations;

  const drift =
    (
      riskFreeRate -
      dividendYield -
      0.5 *
        volatility *
        volatility
    ) *
    dt;

  const diffusion =
    volatility *
    Math.sqrt(dt);

  const discountFactor =
    Math.exp(
      -riskFreeRate *
        timeToExpiry,
    );

  const normal =
    new NormalGenerator(seed);

  /*
   * Welford's online algorithm lets us estimate the payoff mean and
   * variance without retaining every simulated path.
   */
  let mean = 0;
  let m2 = 0;

  for (
    let path = 1;
    path <= paths;
    path += 1
  ) {
    let underlying = spot;
    let averageSum = 0;

    for (
      let observation = 0;
      observation < observations;
      observation += 1
    ) {
      const z = normal.next();

      underlying *= Math.exp(
        drift +
          diffusion * z,
      );

      averageSum += underlying;
    }

    const average =
      averageSum /
      observations;

    const payoff =
      Math.max(
        average - strike,
        0,
      );

    const discountedPayoff =
      discountFactor * payoff;

    const delta =
      discountedPayoff - mean;

    mean += delta / path;

    const delta2 =
      discountedPayoff - mean;

    m2 += delta * delta2;
  }

  const sampleVariance =
    m2 /
    (paths - 1);

  const standardError =
    Math.sqrt(
      sampleVariance / paths,
    );

  return {
    price: mean,
    standardError,
    paths,
    seed,
  };
}

function benchmarkScenario(
  scenario: Scenario,
  index: number,
): BenchmarkResult {
  const deterministic =
    priceAsianCall(
      scenario.market,
      scenario.option,
    );

  /*
   * Give every scenario a distinct but reproducible stream.
   */
  const scenarioSeed =
    (SEED + index) >>> 0;

  const mc =
    monteCarloAsianCall(
      scenario.market,
      scenario.option,
      PATHS,
      scenarioSeed,
    );

  const absoluteError =
    Math.abs(
      deterministic.price -
        mc.price,
    );

  const relativeError =
    mc.price === 0
      ? absoluteError === 0
        ? 0
        : Number.POSITIVE_INFINITY
      : absoluteError /
        Math.abs(mc.price);

  const zScore =
    mc.standardError > 0
      ? (
          deterministic.price -
          mc.price
        ) /
        mc.standardError
      : null;

  return {
    name: scenario.name,

    deterministicPrice:
      deterministic.price,

    monteCarloPrice:
      mc.price,

    monteCarloStandardError:
      mc.standardError,

    absoluteError,
    relativeError,
    zScore,

    paths: mc.paths,
    seed: mc.seed,
  };
}

function formatPercent(
  value: number,
): string {
  if (!Number.isFinite(value)) {
    return "n/a";
  }

  return `${(value * 100).toFixed(4)}%`;
}

function main(): void {
  console.log(
    "n0paths approximation benchmark\n",
  );

  console.log(
    `Monte Carlo paths per scenario: ${PATHS.toLocaleString()}`,
  );

  console.log(
    `Base seed: ${SEED}\n`,
  );

  const results =
    scenarios.map(
      benchmarkScenario,
    );

  console.table(
    results.map((result) => ({
      scenario:
        result.name,

      deterministic:
        result.deterministicPrice.toFixed(8),

      monteCarlo:
        result.monteCarloPrice.toFixed(8),

      mcSE:
        result.monteCarloStandardError.toFixed(8),

      absError:
        result.absoluteError.toFixed(8),

      relError:
        formatPercent(
          result.relativeError,
        ),

      z:
        result.zScore === null
          ? "n/a"
          : result.zScore.toFixed(2),
    })),
  );

  console.log(
    "\nInterpretation:",
  );

  console.log(
    [
      "- deterministic is the lognormal moment-matching price",
      "- monteCarlo is a seeded simulation of the discrete GBM payoff",
      "- mcSE is Monte Carlo standard error",
      "- absError includes approximation difference and finite MC sampling noise",
      "- z reports the price difference in units of Monte Carlo standard error",
    ].join("\n"),
  );
}

main();
