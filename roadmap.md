# Siege Prototype — Roadmap

Decisions locked in from the kickoff:

- **Aiming input:** mouse sets direction; a two-click launch meter (press to start a fill bar
  swinging up and back down, press again to freeze it and fire) sets force/power for **both**
  weapons; `Q`/`E` adjusts catapult angle; a key toggles weapon. Minimal text readout on the
  HUD, no sliders. (Supersedes the original wheel-driven force dial — see Pass 2 in §6.)
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
- **`Arena.luau`** — builds arena geometry from `Config`: one flat ground spanning the whole
  play area (session 003; a single elevation, per spec's "roughly the same ground
  elevation"), ringed by perimeter boundary walls, a marked build zone, and two fixed
  weapon-emplacement markers across the gap. Spawns the Princess at `Config.PrincessDistance`
  behind the build zone. `reset()` destroys everything under a `Workspace.ActiveRound` folder
  so each round starts clean -- **not yet round-safe as of session 003**: `build()` still does
  the static geometry and the Princess in one pass, called once at server start; session 004
  needs to split what actually resets each round from what's built once.
- **`BlockManager.luau`** — spawns the 12 blocks as plain anchored `Part`s with
  `PhysicalProperties` from `Config`, tracks them, and at ATTACK start unanchors each one and
  calls `SetNetworkOwner(nil)`. No welds — separate assemblies resting under gravity.
- **`BuildManager.luau`** — handles `PlaceBlock` / `PickupBlock` / `ConfirmBuild`. Validates:
  cell is inside the build zone, cell is free, block budget not exceeded. Authoritative on
  where blocks actually are.
- **`WeaponManager.luau`** — handles `FireWeapon`. Spawns a server-owned projectile and steps
  it on `Heartbeat` with a raycast from last position to new position (no `Touched` reliance —
  the ballista is fast enough to tunnel), filtered to blocks, the Princess, and (session 003)
  the arena boundary, so a miss stops instead of flying until `ProjectileLifetime`. Ballista:
  near-flat, `gravityScale` tiny, stopped by any standing block. Catapult: initial velocity
  from force + angle, full gravity, applies an impulse to blocks it strikes. Each weapon fires
  from its own fixed emplacement (`Config.muzzleOrigin(weapon)`, session 003) rather than a
  single shared point.
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

### Pass 0 — Skeleton — **done (session 001)**
`Config`, `Remotes`, `Types`, `GridUtil`, folder layout, bootstrappers replacing the
Hello-world scripts. `Arena.build()` draws the static geometry. Folded into session 001.

### Pass 1 — BUILD phase, end to end — **done (session 001)**
Arena + Princess, role assignment + banner, Confirm button, HUD. State machine advances to
ATTACK and holds. Blocks stay anchored.
Scope shifted during the session: instead of 12 identical blocks spawned on click, the
grid became a **vertical build plane** and blocks became a **typed, pre-spawned inventory**
— 6 Standard (`2.5×1.25×2.5`) and 6 Wide (`7.5×1.25×2.5`, rotatable, 3× mass at equal
density) sitting in two piles on the builder's right. The Builder lifts a block from its
pile (it hides locally while held), places it on the plane with multi-cell footprint and
`R`-rotation, and clicks a placed block to send it home. `PlaceBlock` now carries
`{ blockId, cell, rotated }`; `StateChanged.blocksRemaining` is `{ Standard, Wide }`. A
short camera intro (overhead → tween to play cam on Start) was added. Structural
placement rules were explicitly deferred (see below).
**Done:** Builder builds a wall from both block types, rotates and rearranges, confirms;
HUD shows the phase change. Playtested green with two players.

### Pass 2 — ATTACK phase + physics — **done (session 002)**
`releaseAll()`, both weapons, projectile stepping + raycast hits, mouse/wheel/`Q`/`E`/`F`
input, force+angle readout, shot counter, catapult block knockback. Princess not yet
killable — just watch blocks fall.
Scope shifted during the session, mostly from playtest feedback: the wheel-driven force dial
was replaced with a two-click **launch meter** (golf-swing style — press to start a linear
fill bar swinging up and back down once, press again to freeze it and fire) for **both**
weapons, not just the catapult; the ballista's fixed muzzle velocity became a
`BallistaMinVelocity..BallistaMuzzleVelocity` range set the same way, since "more power hits
harder" still gave the meter a purpose even without a variable landing distance. `Q`/`E` angle
now only applies to the catapult. The ballista's aim was flattened to horizontal-only (free
vertical aim contradicted its "flat trajectory" identity and caused it to strike high rows
instead of the base). Projectiles are anchored and manually integrated on `Heartbeat` rather
than unanchored/network-owned as first sketched (same server-authoritative raycast hits, no
physics integrator to fight). Catapult/ballista knockback is mass-scaled
(`impulse * block.AssemblyMass`) rather than the literal roadmap formula, which was too weak
to topple anything at Standard block mass. Added beyond the original plan: a world-space
crosshair (green on a wall hit) with a light dashed trajectory preview, a locked-zoom
over-the-shoulder attack camera for the Attacker, and crude part-built weapon props
(`WeaponView`) at the firing position. The catapult's own aim ray was fixed to ignore the wall
(spec: "ignores wall height if aimed well"), so standing close to a tall wall no longer caps
how far over it the player can aim — only the real simulated arc decides whether a shot
actually clears it.
**Done:** the Attacker fires 6 shots with either weapon through the launch meter, both weapons
behave distinctly (flat and low vs. arcing), and a base hit topples a tall stack. Playtested
green with two players; user's assessment at close was "in good shape for the first pass."
Trench arena sizing, fixed weapon emplacements with turn-start selection, and a three-mode
camera were scoped out to a new inserted pass (session 003) rather than folded in here.

### Pass 3 — Trench Arena & Targeting — **done (session 003)**
Reworked the ATTACK-phase arena into a trench sized off the block totals (build-zone opening
30 studs wide × 15 studs tall — total cumulative block width ÷ 2, and every block stacked in
one column), two fixed weapon emplacements with a shared `Config.muzzleOrigin(weapon)` formula,
and a three-mode attack camera (top-down default, first-person, 45°-down side, cycled with `C`).
The brief's "weapon choice locks for the turn" recommendation was overridden at the Open Gate —
`F` still freely toggles mid-turn, unchanged from session 002, just now aimed at two fixed spots
instead of one; no turn-start selection UI was built as a result.
Scope shifted during the session, from playtest feedback: the two platforms floated over
nothing but Studio's default Baseplate with an open gap between them, reading as a flat floor
rather than a trench, and — a related physics gap, not just visual — a missed shot's raycast
never included anything but blocks and the Princess, so it flew until `ProjectileLifetime`
instead of hitting something. Fixed with one continuous flat green ground spanning the whole
play area (kept flat, not a sunken pit, per spec's "roughly the same ground elevation") ringed
by perimeter boundary walls, both added to `WeaponManager`'s raycast filter. A second playtest
pass then caught the 45°-side camera clipping into that new wall (its framing predated it);
repositioned clear of it.
**Done:** all three camera modes read correctly, both weapons aim and fire correctly from their
own emplacement across every camera mode, and a missed shot now stops at the ground or a wall.
Playtested green after two rounds of fixes; user's final assessment was "everything is working
about right."

### Pass 4 — Win/loss + full match — **done (session 004)**
Added `PrincessMonitor` (direct projectile hit + moving-block contact, no owner check), the
RESOLVE/SWAP round loop in `MatchController`, per-user score tracking across best-of-4, and
`RoundResult`/`MatchResult` broadcasts. Split `Arena.build()` (static geometry, once) from a
new `Arena.resetRound()` (Princess reposition only, per round) as the session 003 carry-forward
required. Added `MatchController.onRoundReset(callback)` so `WeaponManager` (in-flight
projectiles) and `BuildManager` (grid occupancy — a bug found mid-session: it was never reset
between rounds and would have misjudged round 2's placements) can each clean up their own live
state per round without `MatchController` requiring them back. `Hud` gained round/score
readouts; a new `ResultBanner` shows the round and match outcome.
**Done:** the spec's full Definition of Done runs start to finish with two players and no
outside instruction. Playtested green across several full matches. User's assessment was
correctness-positive but feel-negative: "it is working and it is not fun at all yet" — the
uniform rectangular block roster makes BUILD rote. That fed directly into Pass 5, inserted
below.

### Pass 5 — Irregular Blocks (L-Piece Pilot) — **done (session 005)**
Replaced the 6 Standard + 6 Wide rectangular roster with 12 identical L-shaped four-cell
pieces (three in a row, one hanging below the row's left end), each a single `UnionOperation`
so it moves as one rigid assembly. Generalized the grid/placement pipeline from a rectangular
footprint + 2-state flip to an arbitrary multi-cell shape + full 4-state rotation (`GridUtil`,
`BuildManager`, `BlockManager`, `BuildInput`). No new placement-time support rule — the
challenge is purely physical: an unsupported overhang has to survive
`BlockManager.releaseAll()` unanchoring it at ATTACK start. Each `UnionOperation`'s actual pivot
offset is measured once at build time and reused on every reposition, since Roblox doesn't
document where a fresh union's `.CFrame` lands relative to its own geometry.
Scope extended during the session, from playtest feedback: the blocks were shorter than they
were wide (`1.25×2.5×2.5`, the original spec-locked brick ratio); switched to cubes
(`1.25×1.25×1.25`, settling on the smaller dimension rather than growing the larger one), with
`GridSize` changed to derive from `BlockSize` instead of being separately hardcoded.
**Done:** two players build a wall from only L-pieces at any of the 4 rotations, confirm, and
gravity judges the result exactly as it did for rectangular blocks. Playtested green with two
players. User's assessment went beyond correctness: the pilot "succeeds in making the game
more interesting," but specifically credited "gravity turning on after placement" — not the
L-shape itself — as the source. That distinction fed directly into Pass 6 and what was then
Pass 7 (since renumbered to Pass 8 — see Pass 6's own entry below for how).

### Pass 6 — Piece Queue (Sequential Hand-off) — **done (session 006)**
Removed the physical pile (12 pieces pre-spawned into a stack, freely liftable and re-placeable
in any order) in favor of a sequential hand-off: the Builder holds exactly one piece at a time
and must place it before the next is issued. Shape stayed the fixed L-piece from Pass 5 and
count stayed 12 — this pass was purely the interaction-model change (`BlockManager`,
`BuildManager`, `Arena`, `BuildInput`, `Hud`), kept separate from the shape-generation work
(Pass 8) so each half can be playtested in isolation. Both open questions from the brief were
settled at the Open Gate: undo/rearrange was removed entirely (the user's call, made for its
own sake — "I think that makes it more interesting" — not a fallback), and Confirm Wall can be
pressed at any time (already true beforehand; needed no code change).
Scope extended during the session, from a follow-up request: added a mirror/flip (`Z` key),
since the existing 4-state rotation already covers every turn about the Z axis and couldn't
reach a shape's chirality-flipped twin (an L-piece's mirror is a J-piece). The mirror has to
happen at the geometry level, not via `CFrame` — a rigid rotation can never produce a mirror
image on its own — so `BlockManager.placeCurrent` builds the union from the mirrored cell list
directly when flipped.
**Done:** no pile geometry is visible, the Builder always holds exactly one piece, placing it
issues the next, all 4 rotations and the mirror flip work, and the round reaches `ConfirmBuild`
/ ATTACK correctly. Playtested green with two players; user's assessment was "Much better."
A second, unrelated request mid-session (restrict the Attacker to a fixed weapon sequence) was
scoped out to a new inserted pass (session 007) rather than folded in here, since it's an
ATTACK-phase change and this pass hadn't been playtested yet.

### Pass 7 — Fixed Shot Sequence
Replaces the Attacker's free choice of weapon on every shot with a scripted sequence —
Catapult, Catapult, Ballista, three shots total instead of six freely-chosen ones
(`Config.ShotSequence`). The server derives and broadcasts which weapon is mandated for the
current shot (`MatchController`); `WeaponManager` trusts that instead of the client's claim;
`AttackInput` drops its `F` toggle and mirrors whichever weapon is current, including the
switch mid-turn from Catapult to Ballista. Deliberately overrides spec's "the Attacker chooses
freely between the two weapons on every shot."
**Done when:** the Attacker gets exactly 3 shots in the fixed order with no way to switch
weapons out of turn, and the HUD/firing-prop model track the mandated weapon correctly
throughout.

### Pass 8 — Randomized Piece Generation
Replaces the fixed L-piece with a per-placement randomly generated shape: 3-6 of the 9 cells in
a 3×3 area filled at random (count and which cells both randomized). Cells that end up mutually
adjacent fuse into one rigid `UnionOperation`; cells that end up isolated stay independently
physical. Breaks the invariant every prior pass relied on — one placed piece has always been
exactly one rigid body — so a single placement now needs to resolve into however many separate
falling bodies its random connectivity produces at ATTACK start. Requires a network-contract
change (the server generates the shape and has to hand it to the client — it can no longer live
as a static named entry in `Config`). `GridUtil`'s shape/rotation math (including Pass 6's
mirrorShape) and `BuildInput`'s per-cell ghost pool are expected to take an arbitrary
runtime-generated shape unchanged.
**Done when:** each of the Builder's 9 pieces is a freshly randomized shape, places, rotates,
and flips correctly, and at ATTACK start its connected clusters fall independently of its
isolated cells.

### Pass 9 — Tune, then launch
Playtest and adjust `Config` by feel (order below). Then publish and play in the real
client.

### Deferred — structural placement rules (not yet scheduled)
BUILD currently lets the Builder drop a block into any free, in-bounds cell, including
mid-air. A later pass should add structural constraints: a block must rest on the platform
or on a block directly below it (no floating), and likely a support/balance check so a
block can't sit with nothing under its footprint. Open question whether this is enforced at
placement time (`BuildManager` rejects the `PlaceBlock`) or left to physics at ATTACK start
(let it float, then fall when `releaseAll()` runs). Stays inside the grid model — it's a
validation layer on `BuildManager`, not a new mechanic.

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
