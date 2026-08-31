# Gnoshbot Product Decisions

## Why this exists

Gnoshbot is not a conversational restaurant concierge. It is a delegated logistics agent. The user states hunger, confirms the drop-off, and the system returns an arrival. Every product decision below exists to keep that contract intact: no menu recitation, no price readout, no checkout confirmation, no "I found three options." The **one** confirmation that always happens is the delivery address. Shipping food without that yes is the failure mode this product exists to avoid.

The visual app exists for onboarding and for managing **saved delivery locations**, Bio-Shield, flavor, and funding. After ENGAGE SYSTEM, ordering is Siri: confirm the address, then fire-and-forget. Everything else is a push notification or a local database the user can interrogate on demand.

---

## 1. Persona: zero-disclosure voice, location-confirmed launch

### 1.1 The user

A person who already decided they will eat, and who has already told the machine their hard constraints (allergies, diet, budget) and **where food is allowed to go**. They are not indecisive about hunger; they are indecisive about **which** kitchen and SKU. Food apps force that comparison. Gnoshbot does not. They confirm a **saved** drop-off and stop choosing. They are not a foodie exploring a city. Discovery-as-entertainment is out of scope. Hands-free Siri is convenience, not a driving or “don’t look at the phone” safety story.

They will hear the drop-off address and say yes or no. They will not compare burrito vs. bowl on the launch turn. They will not authenticate a payment they already authorized. They may read a **push** if the launch later fails.

### 1.2 The spoken contract

Primary intent phrases (registered via `AppShortcutsProvider`, application name substitution required by App Intents):

- "Tell Gnoshbot I'm hungry"
- "Ask Gnoshbot to order lunch"
- "Order lunch with Gnoshbot"

**Turn 1 — location, mandatory, even if only one address exists:**

> "Deliver to Home, 14 Pine Street, apartment 4?"

**Turn 2 — after an explicit yes, under 500 ms, no minutes, no merchant, no SKU, no USDC:**

> "On it."

No yes → no order. GPS is never the destination. The first time a number of minutes is spoken is a **follow-up** or a **push**, after the shop host has published `eta_minutes` on the fulfillment resource (`ARCHITECTURE.md` §8). Until then the truthful line is "Payment settled. They're organizing a courier" (Inquiry) or a silent wait.

### 1.3 Zero-disclosure rule

The primary intent **must not** interpolate:

- restaurant name
- item name
- modifiers
- price
- chain / network
- wallet address
- remaining allowance

Those fields exist in SwiftData so a **separate** Inquiry Intent can answer if, and only if, the user asks.

| User | Intent | Reads | Speaks |
| --- | --- | --- | --- |
| "Tell Gnoshbot I'm hungry" | `OrderLunchIntent` | saved addresses → confirm → CAG | address prompt, then "On it." |
| "Ask Gnoshbot where my food is" | `CheckOrderStatusIntent` | latest `ActiveOrderCache` | logistics sentence |
| "Ask Gnoshbot where it's going" | `WhereIsItGoingIntent` | `deliverySpokenLine` | confirmed address |
| "Ask Gnoshbot what it picked" | `WhatDidYouOrderIntent` | `itemName`, `merchantName` | SKU + shop |
| "Ask Gnoshbot what the damage was" | `WhatDidItCostIntent` | `costUsdc` | USDC amount |
| "Ask Gnoshbot to cancel" | `CancelLunchIntent` | tracking URL | "Cancelling." then worker POSTs cancel/refund path |

SKU, shop, and price are Inquiry answers, never the launch answer.

### 1.4 Confirmation policy: delivery location only

There is no "shall I order the burrito?" turn. There is no "that will be 14.50, confirm?" turn. There **is** always "Deliver to {label}, {address}?"

| Confirm | Policy |
| --- | --- |
| Menu item | Never |
| Restaurant | Never |
| Price | Never |
| Face ID per lunch | Never |
| **Delivery location** | **Always. Every launch. Even with one saved address. Even if GPS agrees.** |

Payment and taste were authorized at ENGAGE SYSTEM:

1. created the CDP Smart Account (if needed),
2. created a Spend Permission for the local spender (USDC, period 1 day, allowance = slider),
3. stored the spender key without a biometric ACL,
4. registered Siri shortcuts,
5. required ≥1 saved delivery location,
6. kicked region ingest for each saved address bbox.

A biometric prompt on every lunch would be a product bug. A spoken menu would be a product bug. Shipping food to an unconfirmed coordinate would be a product bug.

Other safety substitutes:

- Bio-Shield is a hard pre-filter, not a suggestion.
- Daily Spend Permission is an on-chain ceiling ([CDP Spend Permissions](https://docs.cdp.coinbase.com/wallets/using-wallets/spend-permissions)).
- Shop-side payer-keyed daily cap still applies (`GET /guardrails`).
- `payTo` must match the place-time snapshot.
- Fatal local aborts **before** a yes (no address, declined address, funds, allowance) **do** speak, because launch did not start.
- Empty payable pool and Bio-Shield wiping the box happen **after** “On it.” as pushes (P16).

### 1.5 Fatal interruption copy (only when launch cannot start)

Keep the voice short. These return **before** `requestConfirmation` yes, except declined confirm which is the no on that prompt.

| Condition | Line |
| --- | --- |
| Zero saved delivery locations | "Add a delivery address in Gnoshbot first." |
| User says no / cancels confirmation | "No order placed." |
| User names a label that is not saved | "I don't have that address. Open Gnoshbot to add it." |
| Allowance remaining = 0 | "Order denied. Daily allowance exceeded." |
| Cached funded flag false | "Launch aborted. Insufficient funds. Top up in Gnoshbot." |

Empty payable box and Bio-Shield emptying the cached box are **not** spoken. After a yes they are §1.6 pushes (P16).

### 1.6 Push copy (after the voice channel is closed)

| Event | Push |
| --- | --- |
| Settled, eta still null | "Paid. Kitchen is on it." |
| First non-null eta | "Arriving in {n} minutes." |
| Dispatched with updated eta | "On the way. {n} minutes." |
| Failed payment | "Launch aborted. {reason}. Tap to retry." |
| Kitchen reject / refund | "Kitchen declined. Refund started." |
| No payable kitchen in the 5-mile box (after yes) | "No payable kitchen in range of that address." |
| Bio-Shield excludes every cached item (after yes) | "Every nearby menu collides with your Bio-Shield. I won't guess." |

Empty-box and Bio-Shield pushes must not name a merchant or item. Other pushes may name the merchant. The **launch** utterance still must not. The user has opted into a notification; that is a different channel.

---

## 2. Phase 1 — Bio-Shield

### 2.1 Purpose

Capture hard medical and ethical constraints once, encrypt them on-device, and use them as a **zero-tolerance pre-filter** before any model sees a menu. The model is not the last line of defense for peanuts. A boolean mask computed locally is.

### 2.2 Layout

Full-bleed, high-contrast grid. One card per constraint. Unselected: 2 pt hairline, label, SF Symbol. Selected: 4 pt border in the semantic "shield" color, filled shield glyph, `isOn = true`. Cards are at least 44×44 pt hit targets ([HIG — Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)). Dynamic Type: the label wraps; the card grows. Reduce Motion: no bounce, instant border.

Default grid (shipping v1; user can add custom strings in a footer field):

**Allergens**

- Peanut
- Tree nut
- Shellfish
- Dairy
- Egg
- Wheat / gluten
- Soy
- Sesame
- Fish

**Frameworks** (same visual language, separate section header)

- Vegan
- Vegetarian
- Halal
- Kosher

Footer, always visible (v1 truth — do not over-claim):

> Encrypted on this iPhone. If you select an allergen, Gnoshbot will skip any item whose name or description looks like a match, and skip items with no ingredient text at all.

No cloud backup toggle on this screen. iCloud sync of allergy ciphertext is **off** until a later decision explicitly accepts the threat model (iCloud Keychain + SE wrapped keys is possible; it is not v1).

### 2.3 Data shape (on device)

```json
{
  "allergens": ["peanut", "shellfish"],
  "frameworks": ["halal"],
  "customExclusions": []
}
```

Canonical slugs, lowercase, stable. Custom exclusions are free-text, NFC-normalized, stored as given.

### 2.4 Encryption

SwiftData writes SQLite. SQLite is covered by Data Protection (`NSFileProtectionCompleteUntilFirstUserAuthentication` at best for an app group the intent can read). That is not medical-grade wrapping. The Secure Enclave is a coprocessor that holds **keys**, not rows ([Apple Platform Security](https://support.apple.com/guide/security/secure-enclave-sec59b0b31ff/web), CryptoKit `SecureEnclave`).

Correct construction:

1. Generate `SecureEnclave.P256.KeyAgreement.PrivateKey` (access: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, **no** `.userPresence` — the voice loop must decrypt without Face ID).
2. Derive a symmetric AES-GCM key via HKDF from an ECDH with an ephemeral key, or wrap a random 256-bit AES key using SE-backed key agreement.
3. Store `{ ciphertext, nonce, wrappedKey }` as `Data` columns in SwiftData. Store **no** plaintext allergen list.
4. Decrypt in-process for CAG assembly. Wipe the plaintext buffer.

Inquiry Intents and the launch intent both run after first unlock in normal Siri use. If the device is locked and has never been unlocked since boot, the intent must fail closed: "Unlock your iPhone and ask again." That is acceptable. Prompting Face ID to read allergies during a lunch order is not.

### 2.5 How the filter runs

Before CAG:

1. Decrypt Bio-Shield.
2. For each candidate menu item (name + description + extra names), run a local matcher: slug list + a small synonym table (e.g. "groundnut" → peanut, "prawn" → shellfish).
3. Drop the item if any allergen or framework collision hits.
4. Drop the restaurant if, after item drop, nothing remains that also passes Flavor Fingerprint soft constraints at a minimum score.
5. If the restaurant was a culinary match and died **only** because it is `UNSUPPORTED` (no x402), that is a skip-log event, not a Bio-Shield event.
6. If every remaining payable item collides with Bio-Shield, abort with the spoken line in §1.5. Do not "best effort" a peanut kitchen.

Menus that do not declare ingredients cannot be proven safe. Policy: **fail closed**. A proxy-wrapped node whose JSON has no allergen flags is treated as unknown, not safe. Native Menu Pull items similarly carry no allergen schema today (`ingest.schema.json` has name, price, extras — no `contains[]`). Until the shop schema grows an allergen field, Gnoshbot's matcher is **name/description substring only**. Do not ship a "complete absence" footer until kitchens fill a real allergen field.

---

## 3. Phase 2 — Flavor Fingerprint

### 3.1 Purpose

Soft scoring. Never a hard disqualify except for the "Never order this" ingredient list, which is treated as Bio-Shield-adjacent (hard exclude, but not medical, and allowed to live as plaintext-adjacent ciphertext in the same blob).

### 3.2 Layout

Two tag clouds on one vertically scrolling canvas.

- **What you crave** — chips, semantic "go" color on select. Multi-select.
- **Never order this** — chips, semantic "stop" color. Multi-select. Includes a one-line text field that commits on return.

Spice index: a 3-stop discrete slider, not a continuous UISlider pretending to be meaningful.

```
Mild ── Medium ── High
```

Default: Medium.

Cuisine chips (v1, not exhaustive; extras via the text field):

Thai, Mexican, Italian, Mediterranean, Japanese, Indian, Korean, Chinese, American, Healthy bowls, Pizza, Burgers, Noodles, BBQ, Seafood.

### 3.3 Data shape

```json
{
  "spice": "medium",
  "preferredCuisines": ["mexican", "thai"],
  "neverIngredients": ["cilantro", "olives", "mayonnaise"],
  "preferredMealTypes": ["burritos", "noodles"]
}
```

Stored in the same SE-wrapped blob as Bio-Shield (one user profile envelope). Flavor data is not medical but there is no product reason to split keys.

### 3.4 Scoring (deterministic, local)

For each surviving item after Bio-Shield:

```
score = 0
+ 3 if restaurant cuisine ∩ preferredCuisines
+ 1 if item text ∩ preferredMealTypes
+ 1 if spice tag matches (when present)
- 100 if neverIngredients hit  → drop
- 2 if cuisine is absent from preferred (not a drop)
```

The LLM / CAG step **re-ranks** the top N (≤ 10 restaurants, ≤ 5 items each) but cannot revive a dropped item. If the structured tool call names a dropped `item_id`, the runtime rejects the call and re-prompts once with the dropped id listed as illegal. Second violation → skip to next restaurant or abort.

---

## 4. Phase 3 — Launch Parameters

### 4.1 Purpose

Save at least one delivery location, fund the Smart Account, bind the daily on-chain allowance, grant Siri, and fire region ingest for each saved address. This is the only wizard screen that shows an address, a wallet, a QR code, or a dollar figure.

### 4.2 Layout

Three bands, top to bottom. Scroll if needed. Dynamic Type.

**Band A — Delivery locations (required)**

- List of saved rows: label, one-line address, Default badge.
- **Add address**: MapKit search + dropped pin + Contacts. User must see the map and the postal string before Save. Fields: label (required, unique), line1, line2 / apt / buzzer (optional but prompted), city, region, postal, country. Geocode at save; refuse Save if geocode fails.
- "Use current location" is allowed **here**, on a map the user looks at, then Save. That creates a labeled row. It does not authorize Siri to invent destinations later.
- Empty state: "Gnoshbot will always ask before sending food. Add Home to start."
- Caption: "Siri will read this address back every time you order. GPS will not be used as the drop-off."

**Band B — Embedded wallet**

- Status: "Creating…" / address (truncated, copy) / "Funded" (USDC balance).
- Primary button: **Fund with Coinbase** (CDP onramp / Apple Pay onramp as CDP ships it).
- Secondary: QR of the Base address for USDC send.
- Network caption: "Base · USDC". Test builds show "Base Sepolia" in unmissable type.

**Band C — Daily autonomous allowance**

- Slider: **$10 – $50 USDC**, step $1, default **$25**.
- Caption: "Resets every 24 hours from the moment you tap Engage. Gnoshbot can sign lunches up to this remaining amount without Face ID."
- Remaining today, once live: a numeric readout, not a second slider.

**CTA** — full width, last element:

**ENGAGE SYSTEM**

Disabled until: ≥1 saved delivery location AND Smart Account address exists AND Spend Permission user-op has been submitted AND Siri authorization has been requested (result may be "later"; we still allow engage but the spoken path will no-op until granted).

Funding may be $0 at engage. The first lunch then hits the insufficient-funds abort, which is a valid state — we do not block onboarding on a faucet. Zero addresses **does** block engage.

### 4.3 What ENGAGE SYSTEM does, in order

1. Persist the slider value locally (inside the wrapped envelope).
2. `createSpendPermission` on the Smart Account: token `usdc`, `allowance` = slider × 10^6, `periodInDays: 1`, spender = newly generated EOA, `useCdpPaymaster: true` ([Spend Permissions](https://docs.cdp.coinbase.com/wallets/using-wallets/spend-permissions)). This **does** prompt the user (passkey / CDP auth). That is the one biometric of the relationship.
3. Store spender key in Keychain, after-first-unlock, no biometry.
4. Request App Intents Siri authorization and notification authorization.
5. Request location Always, with a purpose string that names travel ingest — not "we will send food to wherever you are."
6. `startMonitoringSignificantLocationChanges()`.
7. `POST /regions/ensure` for the 5-mile bbox of **each saved delivery location**.
8. Flip `engaged = true`. Subsequent app launches skip the wizard.

### 4.4 Allowance period

CDP Spend Permissions reset on an **elapsed `period` in seconds**, not a tz-aware civil midnight ([anatomy of a spend permission](https://docs.cdp.coinbase.com/wallets/using-wallets/spend-permissions)). Shipping copy must not say "midnight." It says "every 24 hours." A local remaining-allowance display can **also** show a civil-day number for comfort, but the chain will not agree on DST days. The chain wins.

Shop-host `DailySpendCapMinorUnits` is a separate UTC-day cap. The user's slider should be ≤ that cap or lunches 422. Default shop cap in the inspected host is $500, so the $50 slider always fits.

### 4.5 Single-order cap

Optional second ceiling `maxSingleOrderUsdc`, default = slider. v1: omit the extra control; the slider is the only number. A $25 daily cap is already a per-order cap if they order once. Two $14 lunches is a supported pattern.

### 4.6 Spoken address format

When Siri confirms, the dialog is exactly:

`Deliver to {label}, {line1}{, line2}?, {city}?`

Examples:

- "Deliver to Home, 14 Pine Street, apartment 4, Brooklyn?"
- "Deliver to Work, 200 Market Street, San Francisco?"

If the user says "no" and has other rows, Siri lists labels: "Home, Work, or Gym?" (`requestDisambiguation`). If they say a new street, Siri does **not** geocode it: "Open Gnoshbot to add that address."

---

## 5. Visual product after onboarding

The app's foreground UI, post-wizard:

- Current order card (status, eta when known, confirmed drop-off, "what did you pick" disclosure **behind an explicit tap** — the visual analogue of Inquiry, not of launch).
- **Addresses** editor (same component as Band A). Add / edit / delete / set default. Deleting the last address disables Siri ordering until another is saved.
- Remaining daily allowance.
- Fund / revoke Spend Permission.
- Bio-Shield and Flavor Fingerprint editors (same components as the wizard).
- A kill switch: **Revoke autonomous ordering** (revokes the Spend Permission on-chain, deletes the spender key, leaves the Smart Account).

There is no feed of nearby restaurants. There is no cart. There is no tip picker in v1 (tip is not in the shop schema). There is no star rating. There is no "send to wherever I am" toggle.

---

## 6. Shipping stages

Do not call the iOS-only slice a "demo." Names below are the product language (2026-08-31). Repo paths like `infra/demo/` and `GNOSHBOT_DEMO` are leftovers until a rename; they map to **prototype** fixtures or flags, not a fourth stage.

| Stage | What ships | What does not |
| --- | --- | --- |
| **Prototype** | TestFlight (or Debug) iOS. Pre-filled Home (Brooklyn pin). Bundled neighborhood JSON. Bio-Shield + flavor onboarding (plaintext in prototype; I10 SE-wrap is MVP). Siri: confirm address, then "On it." Deterministic scorer on the voice clock. On-device Foundation Models may **re-rank legal ids only**, after Bio-Shield, in the background. Funding flags stubbed. | Gnoshbot HTTP control plane, Postgres/Neon, Overture ingest, Vercel, pay, live kitchens, a conversational LLM, sending allergen lists to a cloud model. |
| **MVP** | Prototype voice contract **plus** a real control plane: `POST /regions/ensure` and region GET against PostGIS. Cheap host is P14 (Neon `aws-us-west-2` + Function URL) or local compose for proof. Seeded tile is allowed; ingest may stay off. | Full production ops, ALB/NAT/RDS as a requirement, shipping food without shop overlay + settlement. |
| **After MVP** | If this becomes a real project: live ingest in us-west-2, real Spend Permission + x402 to a shop this host actually serves, fulfillment `eta_minutes`, more than one canned city. | Not specified here. Open a new dated row; do not sneak it into prototype. |

**Agent in prototype:** Gnoshbot is a **delegated launch agent**, not a chat model. Prototype still shows that: App Intent → address confirmation → local pick from cache → spoken "On it." Apple Foundation Models (on-device, Apple Intelligence hardware) may re-rank the **already-filtered** working set using flavor; they do not see raw Bio-Shield slugs as the safety layer and must not invent menu ids. The scorer stays on the Siri clock because "On it." is budgeted in hundreds of milliseconds and the model is not.

P13 (2026-08-31 supersession): public TestFlight **prototype** is iOS-only (bundled JSON, no Gnoshbot backend). A seeded ingest-off control plane is an **MVP** hosting option, not the prototype definition. Demo wrap rows stay out of any production live pool (P9). Live Overture ingest stays us-west-2 only and is **after MVP** unless an MVP explicitly turns a one-city bbox on.

---

## 7. Decisions that are closed

| ID | Decision |
| --- | --- |
| P1 | After a yes on the address, launch utterance is "On it." Minutes appear only after fulfillment `eta_minutes` is non-null. |
| P2 | The only launch confirmation is delivery location. Menu, kitchen, price, and Face ID are not confirmed per order. |
| P3 | Every launch calls `requestConfirmation` on a **saved** address. Zero saved addresses abort. GPS is never the destination. |
| P4 | Inquiry Intents are the only disclosure path for SKU, shop, and price. Drop-off is also Inquiry (`WhereIsItGoingIntent`) after the launch yes. |
| P5 | Bio-Shield is SE-wrapped ciphertext in SwiftData, fail-closed on unknown ingredients when any allergen is set. |
| P6 | Flavor Fingerprint is soft except `neverIngredients`. |
| P7 | Daily cap is CDP Spend Permission, 24 h period, $10–$50, default $25. Copy says "24 hours," not "midnight." |
| P8 | Spender key has no biometric ACL. Owner/passkey does. |
| P9 | Sandbox shops are not in the live pool. |
| P10 | Predictive ETAs are not user-visible. |
| P11 | Shipping voice copy is plain. |
| P12 | ENGAGE SYSTEM requires ≥1 saved delivery location. Kitchen search is the 5-mile box around the **confirmed** address. |
| P13 | **Superseded 2026-08-31** by §6. Prototype = iOS-only TestFlight (bundled JSON, no Gnoshbot backend). Seeded ingest-off control plane = MVP option, not prototype. Wrap rows are not the production live pool (P9). Live Overture ingest stays us-west-2 only. |
| P14 | **MVP** control plane (cheap shape): **Neon PostGIS in `aws-us-west-2` + two Lambdas** (Function URL API, container ingest, async Invoke, SSM, EventBridge purge). RDS Multi-AZ, ALB, Fargate, NAT, and SQS are an expensive later path, not a prerequisite. (`plans/infrastructure.md`; 2026-08-31.) |
| P16 | After a yes on the saved address, insert `launching` and speak "On it." immediately. Empty payable box and Bio-Shield-empty box are post-launch **pushes**, not spoken aborts. Scorer / Foundation Models / pay run after the intent returns. (2026-08-31.) |

Reopen only with a written supersession in this file.
