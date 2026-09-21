# zcode-pet 🐱

[中文文档](README.zh-CN.md)

A desktop pet for ZCode: a hand-drawn vector orange cat floats in the corner of your screen and mirrors what your agent is doing — head-scratching when thinking, trotting when running Bash, waving when a permission request needs you, crying on errors, and celebrating with confetti when a task lands. Comes with feeding & affinity, and a built-in pet marketplace to adopt **4,800+ community pets** from [petdex.dev](https://petdex.dev).

```
ZCode hooks (7 events, bystander mode — zero interference)
   └─▶ state.json ──300ms poll──▶ floating window (SVG cat + sprite-sheet dual engine)
```

## Install

**Option 1: from marketplace** (two commands, tested against ZCode 3.14):

```bash
zcode plugins marketplace add https://github.com/wsdone/zcode-pet
zcode plugins install zcode-pet
```

**Option 2: local marketplace** — Plugin Market → Add marketplace → paste this repo (contains `marketplace.json`) → install zcode-pet.

**Option 3: dev mode** — `~/.zcode/cli/config.json`:

```json
{ "plugins": { "dirs": ["/path/to/zcode-pet/zcode-pet"], "enabledPlugins": { "zcode-pet@inline": true } } }
```

Requirements: macOS + swiftc (bundled with Xcode CLT). The floating window compiles itself on first event (~5s, one-time).

## Features

| | |
|---|---|
| 🐱 Vector cat | Hand-drawn SVG + CSS animations (breathing, blinking, tail sway, squash-jump), 13 states |
| 🪟 Agent mirror | thinking / working (Bash trots, Read reads, Search magnifier) / needs-you / error / celebrate / asleep |
| 🔔 Notifications | system notification when the cat needs your confirmation |
| 🍚 Gamification | feed, pet, affinity unlocks accessories (bow → bell → crown), food drops on task completion |
| 🛒 Pet marketplace | `/pet market`: browse & search all of petdex.dev, animated previews, one-click adopt |
| 🎨 Sprite engine | official petdex spec (8 cols × 192×208), per-row frame rates, `/pet import` for manual imports |
| 🐈 TUI sidebar | optional patch: an ASCII cat in the ZCode terminal sidebar, synced with the desktop one (below) |

## TUI sidebar patch (optional easter egg)

Keeps a second, ASCII cat in the ZCode terminal sidebar, consuming the same `state.json` as the floating one:

```
 ▼ pet 🐾
    /\_/\
   ( o.o )
   / ˙˙ \_
    U   U
  mood:     working:Bash
  hunger:   62
```

The ZCode upstream repo is currently a read-only mirror (no PRs), so the patch lives on the [`feat/pet-sidebar` branch of wsdone/ZCode](https://github.com/wsdone/ZCode/tree/feat/pet-sidebar) (self-contained `app-sidebar-pet.tsx`, collapsed by default). To apply to your own ZCode build:

```bash
cd /path/to/zcode   # zai-org/ZCode source
git remote add pet https://github.com/wsdone/ZCode.git
git fetch pet feat/pet-sidebar
git cherry-pick pet/feat/pet-sidebar   # one commit: component + wiring
```

## Interactions

Drag it anywhere (position remembered) · click = pet it · double-click = feed · right-click menu (feed / dress / marketplace / notifications / hide). Commands: `/pet feed · status · market · dress <name> · import <slug> · show · hide`.

## License

MIT
