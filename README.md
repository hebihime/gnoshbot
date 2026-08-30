# Gnoshbot

You already know you are hungry. Gnoshbot asks where the food should go, you say yes, and it answers **"On it."** Menu, price, and kitchen stay off that turn. USDC settles on Base in the background. Minutes are spoken only after the shop publishes a real ETA.

Food never ships to GPS. Every launch confirms a **saved delivery address**. No yes means no place, no payment, no food.

This repo is the iOS agent and the us-west-2 discovery plane. Production kitchens are origin-keyed wraps of a Menu Pull GET, paid over HTTP 402, on the sibling host `web3-restaurant-api`. Gnoshbot does not KYC a registry and does not rewrite that kitchen state machine.

Agents: `GROK.md` wins when documents disagree. Humans: start here, then `PRODUCT_DECISIONS.md` if you want the voice contract in full.

```
gnoshbot-ios/       SwiftData cache Siri inquiries read (no network)
gnoshbot-backend/   Bun control plane: DuckDB ingest, region tiles, skip log
database/           PostGIS index of Overture POIs and x402 capability
```
