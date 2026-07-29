# Coin Clicker Simulator (Roblox)

A complete, ready-to-publish Roblox game built for one purpose: **earning you
Robux**. It's a clicker/simulator — the genre with the best effort-to-revenue
ratio for a first game — with all the monetization already wired in. You create
the Game Passes and Developer Products in Roblox, paste their IDs into one
config file, and publish.

> This folder is self-contained and unrelated to the Python toolkit in the
> rest of this repo.

---

## What the game does

- **Core loop:** tap **COLLECT** to earn coins.
- **Upgrades:** *Click Power* (more per tap) and *Auto Income* (passive coins/sec).
- **Rebirth:** reset your coins + upgrades for a permanent **+50% earnings** each
  time — the classic "prestige" hook that keeps players grinding.
- **Global Top 10** leaderboard (competition = retention = revenue).
- **Saves** progress with `DataStoreService`.

### How it makes money (already built in)

| Type | Item | What it does |
|---|---|---|
| Game Pass | **2x Coins** | Doubles all earnings, forever |
| Game Pass | **VIP (+25%)** | Stacks another +25% |
| Game Pass | **Auto Collector** | Auto-taps 5×/sec even while idle |
| Dev Product | **1k / 10k / 100k Coins** | Instant coin packs (repeatable buys) |

Game Passes are one-time buys (steady baseline income). Developer Products are
**repeatable**, so whales can spend again and again — that's where most
simulator revenue comes from.

---

## Setup

### 1. Install the tools
- [Roblox Studio](https://create.roblox.com/) (free)
- [Rojo](https://rojo.space/) — syncs these files into Studio. Easiest path:
  install the **Rojo** plugin from Studio's Plugin Marketplace, and install the
  Rojo CLI (`cargo install rojo`, or via [Rokit](https://github.com/rojo-rbx/rokit)
  with the pinned `rokit.toml` here: run `rokit install`).

### 2. Sync into Studio
```bash
cd roblox-game
rojo serve
```
In Studio: open a new **Baseplate**, open the Rojo plugin, click **Connect**.
The scripts and UI appear instantly. Press **Play** — the game already works
(minus purchases, which need real IDs).

### 3. Publish
`File → Publish to Roblox As…` → create a new experience. Set it to **Public**
when you're ready.

> **Enable API access for saving:** on the experience's page at
> create.roblox.com → **Settings → Security → Enable Studio Access to API
> Services**. Without this, DataStore saving is disabled in Studio testing.

---

## Turning on monetization (the important part)

Nothing sells until you create the items on Roblox and paste their IDs into
[`src/ReplicatedStorage/Shared/Config.lua`](src/ReplicatedStorage/Shared/Config.lua).
Any ID left as `0` is simply ignored — no errors.

### Game Passes
1. create.roblox.com → your experience → **Associated Items → Passes → Create a Pass**.
2. Name it, set a price (Robux), create it.
3. Open the pass → copy the **ID from its URL** (`.../game-pass/**1234567**/...`).
4. Paste into `Config.GamePasses`:
   ```lua
   Config.GamePasses = {
       DoubleCoins = { id = 1234567, name = "2x Coins",   multiplier = 2 },
       VIP         = { id = 2345678, name = "VIP (+25%)", multiplier = 1.25 },
       AutoCollect = { id = 3456789, name = "Auto Collector" },
   }
   ```

### Developer Products
1. Same experience → **Associated Items → Developer Products → Create**.
2. Name each, set a Robux price, create.
3. Copy each product's numeric ID and paste into `Config.Products`:
   ```lua
   Config.Products = {
       Coins1k   = { id = 111, name = "1,000 Coins",   coins = 1000 },
       Coins10k  = { id = 222, name = "10,000 Coins",  coins = 10000 },
       Coins100k = { id = 333, name = "100,000 Coins", coins = 100000 },
   }
   ```

Re-sync (`rojo serve` picks up saves automatically), re-test, and the Store
panel's buttons now prompt real purchases.

---

## Cashing out Robux → real money

To convert earned Robux to USD you need [Roblox Premium](https://www.roblox.com/premium/membership)
and to meet the **Developer Exchange (DevEx)** requirements (a minimum Robux
balance and an ID-verified account of eligible age). See Roblox's DevEx page for
current thresholds. Purchases you make yourself do **not** count toward DevEx.

---

## Realistic expectations (read this)

The code is done; **the game earning money is a marketing problem, not a coding
problem.** What actually moves revenue on Roblox:

1. **A great icon + thumbnails.** This is ~80% of whether anyone clicks your
   game. Study the front-page simulators and match that polish.
2. **Retention.** Add content over time (new upgrades, pets, zones) so players
   come back. The rebirth loop here is a start.
3. **Discovery.** Roblox's algorithm rewards games where players stay and play
   with friends. Early traffic often comes from paid **Sponsored Ads** and
   creators/friends playing.
4. **Iterate on the paywall.** Watch which passes/products sell and tune prices.

A first game rarely makes much. The point of this one is to be a **complete,
publishable, monetized foundation** you can launch today and build on.

### Play fair
Keep monetization honest — no misleading "free Robux" claims, no pay-to-grief,
follow the [Roblox Community Standards](https://en.help.roblox.com/hc/en-us/articles/203313410)
and monetization rules. Games get taken down (and accounts banned) for deceptive
purchases, which is the fastest way to lose everything you built.

---

## File map

```
roblox-game/
├── default.project.json          Rojo → Studio mapping
├── rokit.toml                    pins the Rojo version
└── src/
    ├── ReplicatedStorage/Shared/
    │   ├── Config.lua            ← paste your Pass / Product IDs here
    │   └── Format.lua            number abbreviation (1.5K, 2.3M…)
    ├── ServerScriptService/
    │   ├── Main.server.lua       entry point, remotes, tick loop
    │   ├── Data.lua              DataStore save/load
    │   ├── Economy.lua           earning / upgrade / rebirth math
    │   ├── Monetization.lua      pass ownership + product receipts
    │   └── Leaderboard.lua       global Top-10 (OrderedDataStore)
    └── StarterPlayerScripts/
        └── ClientMain.client.lua all UI + client game loop
```
