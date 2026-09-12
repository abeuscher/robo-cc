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

### Pass 7 — Fixed Shot Sequence — **done (session 007)**
Replaced the Attacker's free choice of weapon on every shot with a scripted sequence —
Catapult, Catapult, Ballista, three shots total instead of six freely-chosen ones
(`Config.ShotSequence`, with `ShotsPerTurn` now derived from its length). The server derives
and broadcasts which weapon is mandated for the current shot (`MatchController.currentWeapon`,
read from `Config.ShotSequence` and `shotsRemaining`); `WeaponManager` trusts that instead of
the client's claim, reading it before `consumeShot()` advances the index. `AttackInput` dropped
its `F` toggle entirely — `state.weapon` mirrors the broadcast `currentWeapon` on every
`StateChanged`, not just on the ATTACK-phase transition, since the sequence switches weapon
mid-turn (Catapult to Ballista, between shot 2 and shot 3) with no phase or role change to hang
the update off of. Deliberately overrides spec's "the Attacker chooses freely between the two
weapons on every shot."
**Done:** the Attacker gets exactly 3 shots in the fixed order with no way to switch weapons out
of turn, and the HUD/firing-prop model track the mandated weapon correctly throughout, including
the mid-turn switch. Playtested green with two players; user's assessment was "Okay looking
good." Randomized Piece Generation (Pass 8) was drafted as this session's own close-time
precondition once the playtest looked good, per the cadence session 006 established.

### Pass 8 — Randomized Piece Generation — **done (session 008)**
Replaced the fixed L-piece with a per-placement randomly generated shape: 3-6 of the 9 cells in
a 3×3 area filled at random (count and which cells both randomized). Cells that end up mutually
adjacent fuse into one rigid `UnionOperation`; cells that end up isolated stay independently
physical. Broke the invariant every prior pass relied on — one placed piece has always been
exactly one rigid body — so a single placement now resolves into however many separate falling
bodies its random connectivity produces at ATTACK start. Connectivity is computed once per
shape at generation time (rotation and mirroring both preserve adjacency, so it never needs
recomputing per placement). Required the network-contract change anticipated at session 007's
close (the server generates the shape and hands it to the client via `StateChanged.currentShape`
— the same "broadcast it every update, not just on activation" pattern session 007 established
for the mandated weapon, since a fresh piece now arrives after every single placement). Also
corrected this pass's own brief mid-session: the fixed trench (`BuildZoneSize`) is sized off
`PieceCount x PieceGridSize`, not `PieceCount x PieceMaxCells` — a piece's bounding box can never
exceed its 3x3 generation area regardless of how many cells within it are filled, so cell count
affects mass and variety, not footprint extent.
**Done:** each of the Builder's 9 pieces is a freshly randomized shape, places, rotates, and
flips correctly, and at ATTACK start its connected clusters fall independently of its isolated
cells. Playtested green with two players; user confirmed the core mechanic directly ("the blocks
do drop when they are single inside the grid as separate entities") and assessed it as improving
the BUILD phase "quite a bit."

### Pass 9 — Physical Projectiles — **done (session 009)**
Replaced the raycast-stepped, anchored "hit probe" projectile (deliberately not a physics body,
per `WeaponManager`'s own prior design) with a real, persistent physical ball per weapon —
unanchored, `SetNetworkOwner(nil)`'d, launched with one initial `AssemblyLinearVelocity` and left
entirely to Roblox's own physics from there (no more manual per-frame integration or raycast hit
probe). The catapult's ball is heavier with real bounce (`CatapultProjectileRestitution` above the
block's own); the ballista's is light and fast — mass and speed differentiate the two, not shape,
since a puck risks tumbling unpredictably under real physics and a ball doesn't. Manual
`ApplyImpulse` knockback is gone; a struck block now takes real mass/velocity collision response.
Separately but in the same pass, the Princess's win condition changed from a touch/velocity check
to a purely physical one: she's a real unanchored body for the first time (`PrincessMonitor.arm()`
unanchors her, mirroring `BlockManager.releaseAll()`'s ordering), and dies only when a continuous
`Heartbeat` tilt check against `Config.PrincessTopplingAngle` passes — replacing both prior kill
paths (a raycast-reported direct hit, and `Touched` by a fast `BlockId` part) outright, not
generalizing them. `Types.RoundResult.reason` narrowed to `"survived" | "toppled"`.
Scope grew substantially past the original brief across several playtest rounds: (1) a real ball
rolls forever on a frictionless surface once it's rolling without slipping, so `Ground` got its own
`CustomPhysicalProperties` (`GroundFriction`/`GroundRestitution`) to settle it in reasonable time.
(2) The Attacker's camera used to snap away and the round outcome banner appear the instant the
last shot *fired*, cutting away before it landed — `AttackCamera` now stays engaged through
RESOLVE (roles don't swap until the round-end hold finishes), `MatchController` holds the outcome
on screen for `Config.RoundEndHoldTime` (a new `ContinueRequested` remote lets either player skip
early via a "Continue" button on `ResultBanner`), and `ResolveSettleTime` grew 1.5s→3s so a slow
bouncing shot has time to actually land before the round is decided. (3) A `BuildCamera` module was
added to snap the Builder's camera to a consistent view at the start of every BUILD phase, since a
round that started as Attacker left the camera wherever `AttackCamera` last pointed it. (4) Several
balance passes, each a pure `Config`/`Arena` change: `PrincessDistance` doubled (14→28, with the
builder platform's own depth now deriving from it so she stays clear of the back wall regardless of
how far back she sits); the build zone widened to span the *entire* platform width edge-to-edge
(previously a `PLATFORM_MARGIN`-wide side lane let a ballista shot bounce off the boundary walls
and reach the Princess without ever passing through the wall — the Builder had no way to block
that); `PieceCount` dropped 9→6 then back up to 8, and `BlockSize` tripled (1.25→3.75 per side), as
a deliberate experiment in the opposite balance direction; the Princess recolored pink; and
`PrincessTopplingAngle` raised 60°→78° once playtesting showed a single clean catapult hit was
enough to finish her the instant the wall was down.
The session closed with a design conversation (informed by quick web research into the source
board game's own rules — warriors as a defense layer, one-action-per-turn alternation, plural win
conditions, attrition-with-recovery) that produced a 4-session follow-on plan: a physical guard
piece shielding the Princess (Pass 10), a Builder-triggered timed shield ability (Pass 11), a
points-based scoring system replacing binary win/loss (Pass 12), and spin/trajectory rework for the
weapons (Pass 13) — displacing "Tune, then launch" to Pass 14.
**Done:** the catapult ball visibly bounces and settles, the ballista ball reads as distinctly
lighter/faster, both persist after landing, a wall takes more hits to bring down than before, and
the Princess only goes down when actually toppled. Playtested green across many rounds of
iteration; user's final assessment was that the core physical-projectile mechanic and the wall
scaling experiment were "pretty challenging on both sides," with the remaining balance problem
(a two-shot catapult combo — break the wall, then snipe the exposed Princess) identified precisely
enough to scope the next four sessions around it.

### Pass 10 — Guard Piece — **done (session 010)**
Added a second, fixed physical obstacle (`Guard`, a plain slate-grey box) between the wall and the
Princess, sitting a fixed 6 studs in front of her (`Config.GuardDistance`, derived from
`PrincessDistance`) — directly answers session 009's closing finding that one clean catapult hit
through a gap in a collapsed wall was enough to end the round. Inspired by the source board game's
warriors: a second layer of defense, separate from (and behind) the wall itself. Server-spawned,
not Builder-placed; both Open Gate questions were settled toward the simpler option: it behaves
exactly like a wall block (no special-cased "destroyed" state, reuses `BlockFriction`/
`BlockRestitution` and the wall's own density formula) and uses a plain box shape, parented outside
the `Blocks` folder so `WeaponManager` and `AttackInput`'s raycasts pick it up with zero code
changes, same as any other solid part in the arena. Unanchored into real physics at ATTACK start
(`Arena.releaseGuard()`, called from `MatchController.beginAttack()` alongside
`BlockManager.releaseAll()` and `PrincessMonitor.arm()`) and re-anchored/repositioned each round in
`Arena.resetRound()`, mirroring the Princess's own handling throughout.
**Done:** the guard spawns between the wall and the Princess every round, becomes a real physical
body at ATTACK start, and participates in ordinary collision and raycasts with no changes needed
outside `Config`/`Arena`/`MatchController`. Playtested with two players; user's assessment was
"Better."

### Pass 11 — Builder's Timed Shield
A Builder-triggered ability, once per round: a small protective dome over the Princess for about
half a second, timed by the Builder to an incoming shot rather than left up passively. Requires a
new remote, server-side one-use/cooldown enforcement, and client input/UI — the first piece of
Builder agency during ATTACK, which today is pure spectation once the wall is confirmed.

### Pass 12 — Scoring & Points
Replaces the binary round win/loss with a points comparison: the Builder is scored on how many wall
pieces remain (not toppled off the platform) at round end, plus whether the Princess fell — tuned
so a Princess kill is worth roughly a quarter of the maximum possible wall-piece score, so an
Attacker has a genuine reason to grind down the wall for points rather than only ever hunting the
Princess. Changes `Types.RoundResult`'s data shape, `MatchController`'s scoring, and `ResultBanner`
— open design questions (what counts as a surviving "piece" once one piece can split into several
independent bodies; whether "not toppled off the base" means still on the platform at all versus
still standing) get resolved at this session's own Open Gate.

### Pass 13 — Weapon Spin & Trajectory/Bounce
Adds spin to firing (harder to aim accurately) and reworks trajectory/bounce feel for one or both
weapons — likely real angular velocity at launch plus a per-frame Magnus-style force to actually
curve the arc, not a cosmetic-only effect. Scoped separately from Pass 10-12 since it's real
physics feature work with its own tuning cycle, harder to get feeling right than anything built so
far.

### Pass 14 — Tune, then launch
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
2. **Shot sequence** — sets difficulty.
3. **Block mass + friction**, and **`BlockSize`/`PieceCount`** (session 009 experiment: fewer,
   larger blocks) — whether a base hit slides one block and drops the stack straight down, or
   scatters it, and how much of the wall a single hit can plausibly take out.
4. **Ballista muzzle velocity**, then **catapult force + angle range**, then each weapon's
   **projectile mass/friction/restitution** (session 009: real physics bodies, not an abstract
   impact constant).
5. **`PrincessTopplingAngle`** and **`GroundFriction`/`GroundRestitution`** last, to taste.

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
