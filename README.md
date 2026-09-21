# n0paths

A research project exploring deterministic (non-Monte-Carlo) on-chain pricing for
arithmetic-average Asian options, computed from public oracle inputs.

**Live site:** [n0paths.xyz](https://n0paths.xyz)

| Page | What's there |
|---|---|
| [Paper](https://n0paths.xyz) | Motivation, the Monte Carlo baseline, why it's awkward on-chain, the deterministic alternative, limitations, use cases |
| [Method](https://n0paths.xyz/method) | The full derivation, a worked example, a live pricer, sensitivities, and a live accuracy comparison against Monte Carlo |
| [Code](https://n0paths.xyz/code) | EVM implementation notes and a proposed Solidity engine interface |

## The idea

Pricing an arithmetic-average Asian option has no closed-form solution. The usual
answer is Monte Carlo — but on-chain, Monte Carlo means paying gas for every
simulated path and getting a result that depends on path count and random seed,
not just on market state.

This project instead computes the first two moments of the arithmetic average in
closed form under geometric Brownian motion (Turnbull & Wakeman, 1991), matches
them to a lognormal proxy, and prices against that proxy in one deterministic
evaluation — no paths, no seed, no sampling step. The tradeoff is stated
explicitly on the site: no sampling error, but not exact.

## Pricing engine

The actual math lives in [`src/lib/pricing/`](src/lib/pricing/), independent of
the UI:

- [`asianDeterministic.ts`](src/lib/pricing/asianDeterministic.ts) — the
  Turnbull–Wakeman moment-matching pricer, plus numerical delta/vega via central
  finite differences.
- [`asianMonteCarlo.ts`](src/lib/pricing/asianMonteCarlo.ts) — a Monte Carlo
  reference pricer, used only as an off-chain comparison baseline for the live
  site, not part of the pricing method itself.
- [`normalDist.ts`](src/lib/pricing/normalDist.ts) — standard normal CDF/PDF.
- [`asianDeterministic.test.ts`](src/lib/pricing/asianDeterministic.test.ts) —
  unit tests: non-negativity, monotonicity in strike and volatility, near-expiry
  behavior, determinism.

Every live-computed number on the site (the worked example, the sensitivities
table, the accuracy comparison) is this code's actual output for the stated
inputs, run in the browser — not retyped from a separate run.

## Status

Experimental research, not audited, not deployed on-chain. The Solidity
interface on the [Code](https://n0paths.xyz/code) page is a proposal, not a
contract. See the site's Limitations and Validation sections for what's known
to be weak and what hasn't been measured yet.

## Development

```bash
npm install
npm run dev      # start the dev server at localhost:3000
npm test         # run the pricing engine's unit tests (vitest)
npm run lint     # eslint
npm run build    # production build
```

Stack: Next.js (App Router) + TypeScript + Tailwind. No large UI or chart
libraries — diagrams are hand-drawn-style SVG, deterministically seeded (see
[`src/lib/handDrawn/`](src/lib/handDrawn/)) rather than using `Math.random`, to
avoid SSR/hydration mismatches.

## License

MIT — see [LICENSE](LICENSE).
