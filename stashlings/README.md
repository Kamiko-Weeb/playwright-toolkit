# Stashlings (Roblox)

A complete, publish-ready collect‑and‑raid game with its **own identity and
mechanics**. You hoard little critters called **Stashlings** on your **Vault**;
they print **Loot**; you **Snatch** rivals' Stashlings, **Bonk** raiders with
your mallet, **Fuse** duplicates into Golden ones, and **Ascend** for permanent
power. All monetization is wired in — you just paste your IDs.

> Self-contained under `stashlings/`. Unrelated to the Python toolkit or the
> simpler `roblox-game/` clicker elsewhere in this repo.

---

## The loop

1. Spawn at **your Vault** (8 vaults per server, 9 pedestals each).
2. Tap **ROLL** to spend Loot on a random Stashling — a **slot‑machine reveal**
   spins and lands on your critter, which auto‑places and earns **Loot/sec**.
3. Rarer Stashlings earn *way* more: Common → Rare → Epic → Legendary → Mythic →
   **SECRET**. Each one you own makes your next roll pricier…
4. …so **SNATCH**: walk onto a rival's Vault, hold the prompt on a Stashling,
   and it jumps to yours.
5. **Defend:** step on your **LOCK pad** (60s timer, re‑apply to keep it up) or
   **Bonk** raiders with your mallet to knock them off and cancel their snatch.
6. **Manage** your Vault: **Sell** junk for Loot, or **Fuse** duplicates.
7. **Ascend** when rich for a permanent income multiplier.

### Our own mechanics (what makes Stashlings *Stashlings*)

- **Fusion → Golden.** Merge `Config.Fusion.count` (3) identical Stashlings into
  one **Golden** version that earns **5×** and glows. Duplicates become a choice:
  sell them, or hoard three and upgrade.
- **Snatch Streak.** Each snatch stacks a temporary income bonus (+10% per stack).
  Get **Bonked** and the whole streak is wiped — raiding is rewarded, sloppiness
  punished. This ties combat and stealing together into one risk/reward engine.
- **Sell.** Per‑item sell buttons plus a bulk **Sell All Commons**, so a full
  Vault is a decision, not a dead end.
- **Roll reveal.** A slot‑machine spin on every roll — the dopamine that makes
  the Lucky Roll product tempting.

### Monetization (already built)

| Type | Item | Effect |
|---|---|---|
| Game Pass | **2x Loot** | Double all income |
| Game Pass | **Auto Collect** | Income banks itself |
| Game Pass | **Vault Lock** | Permanent lock — nobody can snatch from you |
| Game Pass | **Zoomies** | Move faster to raid / flee |
| Game Pass | **VIP** | +25% income |
| Dev Product | **10k / 100k / 1M Loot** | Instant Loot (repeatable) |
| Dev Product | **Lucky Roll** | Guaranteed Legendary+ Stashling |

Passes = steady baseline. The repeatable **Lucky Roll** and Loot packs are where
most of the revenue comes from — the fusion/streak systems give whales more to
chase.

---

## Setup

### 1. Tools
- [Roblox Studio](https://create.roblox.com/) (free)
- [Rojo](https://rojo.space/): install the **Rojo plugin** in Studio + the CLI
  (`cargo install rojo`, or `rokit install` using the pinned `rokit.toml`).

### 2. Sync into Studio
```bash
cd stashlings
rojo serve
```
Studio → open a **Baseplate** → Rojo plugin → **Connect**. The whole world is
generated in code at runtime. Press **Play**: you can roll, reveal, collect,
sell, fuse, ascend, and (with a 2nd test player) snatch and bonk.

> **Set Max Players to 8** (Studio → Game Settings) to match `Config.PlotCount`
> so everyone gets a Vault. Grow both together for bigger servers.

### 3. Enable saving
create.roblox.com → your experience → **Settings → Security → Enable Studio
Access to API Services** (DataStores: saving + leaderboard).

### 4. Publish
`File → Publish to Roblox As…` → new experience → **Public** when ready.

---

## Turning on monetization

Create the items on Roblox, then paste their numeric IDs into
[`src/ReplicatedStorage/Shared/Config.lua`](src/ReplicatedStorage/Shared/Config.lua).
Any id left `0` is ignored (no errors) — that item just won't sell yet. The
`name`/`desc` shown to players are safe to rename; the internal keys are what the
code uses.

- **Game Passes:** experience → *Associated Items → Passes → Create a Pass*,
  copy the ID from its URL into `Config.GamePasses`.
- **Developer Products:** *Associated Items → Developer Products → Create*, copy
  each ID into `Config.Products`.

Cashing Robux out to USD needs Roblox Premium + meeting **DevEx** requirements.
Your own purchases don't count toward it.

---

## Swapping in real character models

Stashlings ship as **original placeholder critters** (a colored block + eyes +
name tag) so you can launch without legal risk. To use real models, edit
`makeUnit` in [`src/ServerScriptService/Plots.lua`](src/ServerScriptService/Plots.lua):
clone your model onto the pedestal instead of building the block, keep the
`Highlight`, `BillboardGui`, and `ProximityPrompt`, set `PrimaryPart`, and honor
the `golden` flag (tint/glow). Everything else keys off each critter's
`id` / `rarity` / `income` in `Stashlings.lua`.

> Don't copy other games' meme characters — many are AI‑generated with unclear
> ownership, and Roblox moderates stolen assets. Original art is safest.

---

## Balancing knobs (`Config.lua`)

| Field | Does |
|---|---|
| `PlotCount` / `SlotsPerPlot` | vaults per server / pedestals per vault |
| `BaseRollCost`, `RollCostGrowth` | roll price and how fast it climbs |
| `SellMultiplier` | sell value = a Stashling's income/sec × this |
| `Fusion.count / multiplier` | how many to fuse, and the Golden income boost |
| `Streak.duration / bonusPerSnatch / max` | snatch‑streak length, per‑stack bonus, cap |
| `StealHoldSeconds`, `StealRange` | how risky/slow snatching is |
| `LockDuration` | seconds a timed Vault lock lasts before you must re‑lock |
| `Rebirth.*` | ascension threshold, scaling, permanent bonus |
| `Combat.*` | mallet damage / range / cooldown / knockback |
| `Stashlings.List` income + rarity `weight` | the entire earn curve & rarity odds |

---

## Realistic expectations

The code is finished; whether it **earns** is a marketing problem:

1. **Icon + thumbnails** decide ~80% of clicks — bright, readable, in‑your‑face.
2. **Retention:** add Stashlings/rarities/events over time; the fuse + streak +
   snatch loops already drive sessions.
3. **Discovery:** early traffic usually needs **Sponsored Ads** + friends/creators.
4. **Tune the paywall:** watch what sells and adjust prices.

### Play fair
No misleading "free Robux" claims, no deceptive purchases — follow the
[Roblox Community Standards](https://en.help.roblox.com/hc/en-us/articles/203313410)
and monetization rules. Deceptive monetization gets games deleted.

---

## File map

```
stashlings/
├── default.project.json          Rojo → Studio mapping
├── rokit.toml                    pins the Rojo version
└── src/
    ├── ReplicatedStorage/Shared/
    │   ├── Config.lua            ← paste IDs; all balance knobs
    │   ├── Stashlings.lua        critter defs, rarities, roll odds
    │   └── Format.lua            number abbreviation
    ├── ServerScriptService/
    │   ├── Main.server.lua       entry: world, remotes, join/leave, tick
    │   ├── WorldBuilder.lua      builds all vaults in code (pedestals, pads, signs)
    │   ├── Plots.lua             vaults, place/roll/sell/FUSE, income, SNATCH, lock, ascend, STREAK
    │   ├── Combat.lua            mallets + bonk hitreg + knockback (breaks streaks)
    │   ├── Data.lua              DataStore save/load
    │   ├── Monetization.lua      pass ownership + product receipts
    │   └── Leaderboard.lua       global Top-10
    └── StarterPlayerScripts/
        ├── ClientMain.client.lua  all UI, roll reveal, Vault (sell/fuse) panel, toasts
        └── CombatClient.client.lua click/tap to bonk + mobile button
```
