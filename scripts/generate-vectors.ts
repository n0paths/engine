import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

import {
  type AsianOption,
  type MarketState,
  greeksAsianCall,
  priceAsianCall,
} from "../reference/pricing.js";

interface Scenario {
  name: string;
  description: string;
  market: MarketState;
  option: AsianOption;
}

interface Vector {
  name: string;
  description: string;

  inputs: {
    market: MarketState;
    option: AsianOption;
  };

  expected: {
    price: number;
    undiscountedPayoff: number;
    discountFactor: number;

    firstMoment: number;
    secondMoment: number;

    effectiveVariance: number;
    effectiveVolatility: number;
    logMean: number;

    d1: number | null;
    d2: number | null;

    delta: number;
    vega: number;
  };
}

interface VectorFile {
  metadata: {
    project: string;
    model: string;
    generatedBy: string;
    units: string;
    notes: string[];
  };

  vectors: Vector[];
}

const scenarios: Scenario[] = [
  {
    name: "baseline",
    description:
      "ATM, 60% volatility, 4% rate, one year, 30 observations",
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
    description:
      "ATM contract under relatively low volatility",
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
    description:
      "ATM contract under high volatility",
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
    name: "in_the_money",
    description:
      "Arithmetic Asian call with strike below spot",
    market: {
      spot: 120,
      volatility: 0.45,
      riskFreeRate: 0.03,
      dividendYield: 0,
    },
    option: {
      strike: 100,
      timeToExpiry: 1,
      observations: 30,
    },
  },

  {
    name: "out_of_the_money",
    description:
      "Arithmetic Asian call with strike above spot",
    market: {
      spot: 80,
      volatility: 0.45,
      riskFreeRate: 0.03,
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
    description:
      "One-month maturity with daily-style observation count",
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
    name: "long_maturity",
    description:
      "Two-year maturity",
    market: {
      spot: 100,
      volatility: 0.50,
      riskFreeRate: 0.04,
      dividendYield: 0,
    },
    option: {
      strike: 100,
      timeToExpiry: 2,
      observations: 48,
    },
  },

  {
    name: "positive_dividend_yield",
    description:
      "Non-zero continuous dividend or carry yield",
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
    name: "negative_rate",
    description:
      "Negative continuously compounded risk-free rate",
    market: {
      spot: 100,
      volatility: 0.35,
      riskFreeRate: -0.01,
      dividendYield: 0,
    },
    option: {
      strike: 100,
      timeToExpiry: 1,
      observations: 12,
    },
  },

  {
    name: "single_observation",
    description:
      "One observation; useful as a limiting sanity case",
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

  {
    name: "zero_volatility",
    description:
      "Degenerate deterministic underlying path under GBM",
    market: {
      spot: 100,
      volatility: 0,
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
    name: "deep_itm",
    description:
      "Deep in-the-money call",
    market: {
      spot: 150,
      volatility: 0.30,
      riskFreeRate: 0.04,
      dividendYield: 0,
    },
    option: {
      strike: 75,
      timeToExpiry: 0.5,
      observations: 12,
    },
  },

  {
    name: "deep_otm",
    description:
      "Deep out-of-the-money call",
    market: {
      spot: 75,
      volatility: 0.30,
      riskFreeRate: 0.04,
      dividendYield: 0,
    },
    option: {
      strike: 150,
      timeToExpiry: 0.5,
      observations: 12,
    },
  },
];

function generateVector(
  scenario: Scenario,
): Vector {
  const pricing = priceAsianCall(
    scenario.market,
    scenario.option,
  );

  const greeks = greeksAsianCall(
    scenario.market,
    scenario.option,
  );

  return {
    name: scenario.name,
    description: scenario.description,

    inputs: {
      market: scenario.market,
      option: scenario.option,
    },

    expected: {
      price: pricing.price,
      undiscountedPayoff:
        pricing.undiscountedPayoff,
      discountFactor:
        pricing.discountFactor,

      firstMoment:
        pricing.distribution.firstMoment,

      secondMoment:
        pricing.distribution.secondMoment,

      effectiveVariance:
        pricing.distribution.effectiveVariance,

      effectiveVolatility:
        pricing.distribution.effectiveVolatility,

      logMean:
        pricing.distribution.logMean,

      d1: pricing.d1,
      d2: pricing.d2,

      delta: greeks.delta,
      vega: greeks.vega,
    },
  };
}

function assertFiniteVector(
  vector: Vector,
): void {
  const numericValues: Array<
    [string, number | null]
  > = [
    ["price", vector.expected.price],
    [
      "undiscountedPayoff",
      vector.expected.undiscountedPayoff,
    ],
    [
      "discountFactor",
      vector.expected.discountFactor,
    ],
    [
      "firstMoment",
      vector.expected.firstMoment,
    ],
    [
      "secondMoment",
      vector.expected.secondMoment,
    ],
    [
      "effectiveVariance",
      vector.expected.effectiveVariance,
    ],
    [
      "effectiveVolatility",
      vector.expected.effectiveVolatility,
    ],
    ["logMean", vector.expected.logMean],
    ["d1", vector.expected.d1],
    ["d2", vector.expected.d2],
    ["delta", vector.expected.delta],
    ["vega", vector.expected.vega],
  ];

  for (const [field, value] of numericValues) {
    if (value === null) {
      continue;
    }

    if (!Number.isFinite(value)) {
      throw new Error(
        `${vector.name}: ${field} is not finite`,
      );
    }
  }

  if (vector.expected.price < 0) {
    throw new Error(
      `${vector.name}: negative option price`,
    );
  }

  if (
    vector.expected.secondMoment <
    vector.expected.firstMoment *
      vector.expected.firstMoment *
      (1 - 1e-12)
  ) {
    throw new Error(
      `${vector.name}: invalid moment relationship`,
    );
  }

  if (
    vector.expected.discountFactor <= 0
  ) {
    throw new Error(
      `${vector.name}: invalid discount factor`,
    );
  }
}

async function main(): Promise<void> {
  const vectors =
    scenarios.map(generateVector);

  for (const vector of vectors) {
    assertFiniteVector(vector);
  }

  const output: VectorFile = {
    metadata: {
      project: "n0paths",
      model:
        "Arithmetic Asian call / GBM / lognormal moment matching",

      generatedBy:
        "scripts/generate-vectors.ts",

      units:
        "Human-readable decimal values; Solidity equivalents use 1e18 WAD scaling",

      notes: [
        "These values are generated by the independent TypeScript reference implementation.",
        "They are not Monte Carlo estimates.",
        "Arithmetic-average pricing uses a moment-matched lognormal approximation.",
        "Zero sampling error does not imply zero model or approximation error.",
        "Generated values must not be described as audited production benchmarks."
      ],
    },

    vectors,
  };

  const outputPath = resolve(
    process.cwd(),
    "reference",
    "vectors.json",
  );

  await mkdir(
    dirname(outputPath),
    {
      recursive: true,
    },
  );

  await writeFile(
    outputPath,
    `${JSON.stringify(output, null, 2)}\n`,
    "utf8",
  );

  console.log(
    `generated ${vectors.length} reference vectors`,
  );

  console.log(outputPath);

  console.log("\nbaseline:");

  const baseline =
    vectors.find(
      (vector) =>
        vector.name === "baseline",
    );

  if (baseline) {
    console.log({
      price:
        baseline.expected.price,

      delta:
        baseline.expected.delta,

      vega:
        baseline.expected.vega,

      M1:
        baseline.expected.firstMoment,

      M2:
        baseline.expected.secondMoment,
    });
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
