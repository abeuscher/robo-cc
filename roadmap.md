# Siege Prototype — Roadmap

Decisions locked in from the kickoff:

- **Aiming input:** mouse sets direction; mouse wheel adjusts force; `Q`/`E` adjusts catapult
  angle; a key toggles weapon; click fires. Minimal text readout on the HUD, no sliders.
- **Tooling:** you have the Rojo Studio plugin and have synced before, so this doc keeps
  setup notes short.
- **Cadence:** I implement a whole phase per pass, then hand off for a Studio playtest.

---

## 1. How this project maps into Studio

Rojo syncs `src/` into Studio services per `default.project.json`. Nothing is authored in
Studio itself — edit files here, Rojo pushes them in. Editing a script *inside* Studio while
Rojo is serving will get it overwritten; treat Studio as read-only for code.

| Folder        | Studio location                          | Runs as        | Holds                                            |
|---------------|------------------------------------------|----------------|-------------------------------------------------|
| `src/shared`  | `ReplicatedStorage.Shared`               | both contexts  | `Config`, `Remotes`, pure helpers, Luau types    |
| `src/server`  | `ServerScriptService.Server`             | server only    | game loop, arena, blocks, projectiles, scoring   |
| `src/client`  | `StarterPlayer.StarterPlayerScripts.Client` | each client | input, HUD, placement ghost, aim line            |

`init.server.luau` and `init.client.luau` are the only scripts that auto-run. Rojo turns a
folder with an `init.*` file into a single script instance; everything else is a
`ModuleScript` that does nothing until `require`d. So both bootstrappers are tiny — they
`require` their managers and start them. One module = one responsibility.

Rule: `src/shared` never requires anything from `src/server` or `src/client`.

---

## 2. Architecture

### Shared (`src/shared`)

- **`Config.luau`** — one table, every tunable from the spec (block dims / mass / friction /
  restitution, block count, Princess distance, gap width, ballista muzzle velocity + gravity
  scale, catapult min/max force + angle range, shots per turn, rounds per match). Plus a few
  the spec implies: `MovingBlockKillSpeed` (velocity threshold so table jitter isn't a kill),
  `GridSize`, `BuildZoneSize`, `ProjectileLifetime`.
- **`Remotes.luau`** — server creates the `RemoteEvent`s under a folder in
  `ReplicatedStorage`; client side `WaitForChild`s them. Returns a typed table so call sites
  read `Remotes.FireWeapon` not string lookups.
- **`Types.luau`** — `Phase = "BUILD" | "ATTACK" | "RESOLVE" | "SWAP"`, `Role`, shot payload
  shape. Keeps the network contract honest.
- **`GridUtil.luau`** — world position ⇄ grid cell snapping. Client uses it for the ghost,
  server uses it to validate placements (never trust the client's snapped value).

### Server (`src/server`)

- **`init.server.luau`** — `require(MatchController).start()`.
- **`MatchController.luau`** — the state machine. Waits for 2 players, assigns roles by join
  order, runs the round loop, owns the score, broadcasts state. Everything else is a service
  it calls.
- **`Arena.luau`** — builds arena geometry from `Config` (Builder platform + marked build
  zone, Attacker firing position across the gap, at matched elevation). Spawns the Princess
  at `Config.PrincessDistance` behind the build zone. `reset()` destroys everything under a
  `Workspace.ActiveRound` folder so each round starts clean.
- **`BlockManager.luau`** — spawns the 12 blocks as plain anchored `Part`s with
  `PhysicalProperties` from `Config`, tracks them, and at ATTACK start unanchors each one and
  calls `SetNetworkOwner(nil)`. No welds — separate assemblies resting under gravity.
- **`BuildManager.luau`** — handles `PlaceBlock` / `PickupBlock` / `ConfirmBuild`. Validates:
  cell is inside the build zone, cell is free, block budget not exceeded. Authoritative on
  where blocks actually are.
- **`WeaponManager.luau`** — handles `FireWeapon`. Spawns a server-owned projectile and steps
  it on `Heartbeat` with a raycast from last position to new position (no `Touched` reliance —
  the ballista is fast enough to tunnel). Ballista: near-flat, `gravityScale` tiny, stopped
  by any standing block. Catapult: initial velocity from force + angle, full gravity, applies
  an impulse to blocks it strikes.
- **`PrincessMonitor.luau`** — declares the Princess dead on (a) a projectile raycast hit or
  (b) `Touched` by a part tagged as a block whose `AssemblyLinearVelocity.Magnitude >
  Config.MovingBlockKillSpeed`. A block from the Builder's own wall counts — no owner check.

### Client (`src/client`)

- **`init.client.luau`** — wires remotes, starts `Hud`, and starts `BuildInput` or
  `AttackInput` depending on the role in the broadcast state.
- **`Hud.luau`** — role banner, current phase, blocks remaining (build), shots remaining +
  active weapon + force/angle readout (attack), round score, match result.
- **`BuildInput.luau`** — mouse hover → snapped translucent ghost block; click on empty cell
  places (sends `PlaceBlock`); click on your block picks it up; on-screen Confirm button
  sends `ConfirmBuild`.
- **`AttackInput.luau`** — mouse aim ray for direction, wheel for force, `Q`/`E` for catapult
  angle, `F` to toggle weapon, click sends `FireWeapon`. Optional thin beam previewing aim.

Client sends **intent only**. Server simulates and is the single source of truth for block
positions, projectile paths, and kills.

---

## 3. Network contract

Client → server:

| Remote        | Payload                                   |
|---------------|-------------------------------------------|
| `PlaceBlock`  | `gridCell: Vector2`                       |
| `PickupBlock` | `blockId: number`                        |
| `ConfirmBuild`| —                                        |
| `FireWeapon`  | `{ weapon, direction: Vector3, force: number, angle: number }` |

Server → client (all clients):

| Remote        | Payload                                                       |
|---------------|--------------------------------------------------------------|
| `StateChanged`| `{ phase, roles = {builder=UserId, attacker=UserId}, score, shotsRemaining, blocksRemaining, round }` |
| `RoundResult` | `{ winner: Role, reason: "survived" | "direct" | "crushed" }` |
| `MatchResult` | `{ winner: UserId? , score }`                                |

---

## 4. Server game loop (MatchController)

```
wait until #players == 2
roles = { builder = players[1], attacker = players[2] }

for round = 1, Config.RoundsPerMatch do
    -- BUILD
    Arena.reset(); Arena.spawnPrincess()
    BlockManager.spawnAnchored(Config.BlockCount)
    broadcast(StateChanged{ phase="BUILD", ... })
    wait for ConfirmBuild from roles.builder

    -- ATTACK
    BlockManager.releaseAll()          -- unanchor + SetNetworkOwner(nil)
    shots = Config.ShotsPerTurn
    broadcast(StateChanged{ phase="ATTACK", shotsRemaining=shots })
    repeat
        payload = wait for FireWeapon from roles.attacker
        WeaponManager.fire(payload); shots -= 1
        broadcast(StateChanged{ shotsRemaining=shots })
    until shots == 0 or PrincessMonitor.isDead()
    wait a beat for physics to settle

    -- RESOLVE
    local winner = PrincessMonitor.isDead() and "attacker" or "builder"
    score[roles[winner]] += 1
    broadcast(RoundResult{ winner=winner, reason=PrincessMonitor.reason() })

    -- SWAP
    roles.builder, roles.attacker = roles.attacker, roles.builder
end

broadcast(MatchResult{ winner = argmax(score), score = score })
```

---

## 5. Physics notes (the part the spec says gets done wrong)

1. **Network ownership.** `SetNetworkOwner(nil)` errors on an *anchored* part. Set it in
   `releaseAll()` immediately after `part.Anchored = false`, per block. Same for every
   projectile right after it's created.
2. **Anchored during BUILD.** Anchored parts don't simulate — the wall costs nothing until
   ATTACK begins.
3. **No welds.** Blocks are independent assemblies. Stacking behavior comes entirely from
   mass, friction, restitution, and contact — which is why those are the balance knobs.
4. **Projectiles are server-simulated.** Create part → unanchor → `SetNetworkOwner(nil)` →
   set initial `AssemblyLinearVelocity` → on `Heartbeat`, apply gravity (`gravityScale *
   workspace.Gravity * dt` for the ballista, full for the catapult), raycast old→new
   position, act on the first hit, despawn after `Config.ProjectileLifetime`.
5. **Ballista vs wall.** Because the raycast travels straight from a low muzzle, a standing
   block in the path is hit first — it naturally "cannot arc over." Once blocks are cleared
   from the lane, the ray reaches the Princess.
6. **Catapult knockback.** On block hit, `block:ApplyImpulse(direction * Config.CatapultImpact)`
   (add `CatapultImpact` to Config). Projectile then despawns.
7. **Reset.** Everything spawned goes under `Workspace.ActiveRound`; `Arena.reset()` destroys
   its children. No debris carries between rounds.

---

## 6. Build passes

Each pass ends with something you sync and playtest (Test tab → 2 players → Start).

### Pass 0 — Skeleton (small, folded into Pass 1 if quick)
`Config`, `Remotes`, `Types`, folder layout, bootstrappers replacing the Hello-world
scripts. `Arena.build()` draws the static geometry. Playtest check: geometry appears, no
errors in Output.

### Pass 1 — BUILD phase, end to end
Arena + Princess, role assignment + banner, grid ghost, place / pickup / re-place, Confirm
button, blocks-remaining HUD. Blocks stay anchored. State machine advances to ATTACK and
holds.
**Done when:** the Builder places 12 blocks, re-arranges some, confirms, and the HUD shows
the phase change.

### Pass 2 — ATTACK phase + physics
`releaseAll()`, both weapons, projectile stepping + raycast hits, mouse/wheel/`Q`/`E`/`F`
input, force+angle readout, shot counter, catapult block knockback. Princess not yet
killable — just watch blocks fall.
**Done when:** the Attacker fires 6 shots, both weapons behave distinctly, a base hit can
topple a tall stack.

### Pass 3 — Win/loss + full match
`PrincessMonitor` (both kill paths), RESOLVE scoring, SWAP, the round loop, best-of-4,
`MatchResult`, arena reset between rounds.
**Done when:** the spec's Definition of Done passes start to finish with two players and no
outside instruction.

### Pass 4 — Tune, then launch
Playtest and adjust `Config` by feel (order below). Then publish and play in the real
client.

---

## 7. Tuning order (spec's priority)

1. **Princess distance from build zone** — the one value everything keys off. Get a
   well-aimed catapult shot clearing a short wall but struggling over a tall one.
2. **Shots per turn (6)** — sets difficulty.
3. **Block mass + friction** — whether a base hit slides one block and drops the stack
   straight down, or scatters it.
4. **Ballista muzzle velocity / gravity scale**, then **catapult force + angle range**.
5. `MovingBlockKillSpeed` and `CatapultImpact` last, to taste.

If one build strategy dominates, change numbers here — not mechanics.

---

## 8. Launch

1. In Studio (synced): **File → Publish to Roblox As…**, name the place, create it.
2. **Home → Game Settings → Permissions → Public** to let others join, or keep it private and
   use **Friends**.
3. Stop the Rojo session before publishing the final build so no half-synced state ships.
4. Open the game from the Roblox client with a second account (or a friend) — physics network
   ownership and remotes behave differently outside Studio's single-machine test, so this is
   a real check, not a formality.

Optional: `rojo build -o RobloxMM.rbxlx` produces a place file you can open directly; it's
gitignored.

---

## 9. Troubleshooting quick-reference

- **Output window** (View → Output) is the log. `print`, `warn` (yellow), `error` (red +
  stack). Server and client lines are tagged.
- **Two-player test:** Test tab → dropdown next to Play → set 2 players → Start. Opens a
  local server + two client windows. The server window is where server `print`s land.
- **Which context am I in?** `RunService:IsServer()` / `:IsClient()`. `game.Players.LocalPlayer`
  is `nil` on the server.
- **Replicated instance not there yet:** use `:WaitForChild("X")` on the client for anything
  Rojo/`Remotes` creates, not `.X`.
- **RemoteEvent trust:** every `OnServerEvent` handler re-validates — role, phase, budget,
  grid cell. The client number is a request, not a fact.
- **`SetNetworkOwner` error:** the part is still anchored. Unanchor first.
- **Script "reverted" in Studio:** you edited it in Studio while Rojo was serving. Edit in
  `src/`.
- **Breakpoints:** click the gutter in the Studio script editor; the Script Analysis and
  Debugger tabs work during a playtest.
