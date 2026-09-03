# Siege Prototype — Build Brief

## What this is

A two-player Roblox prototype adapting the board game *Crossbows and Catapults*. This is a
learning prototype, not a product. The goal is a playable loop in Studio with two players,
reached in as few iterations as possible. Ignore polish, monetization, menus, persistence,
and matchmaking entirely.

Build it as a Rojo-compatible project structure with Luau source files in a `src/` tree, so
the whole thing lives in git and syncs into Studio.

## Core loop

A round has two asymmetric roles:

- **Builder** places 12 blocks to protect a target dummy.
- **Attacker** gets a fixed number of shots to destroy that dummy.

If the dummy survives all shots, the Builder wins the round. Then players **swap roles** and
play again. There is only ever **one** dummy on the board at a time — the current Builder's.

Phases: `BUILD → ATTACK → RESOLVE → SWAP`

The Attacker watches the wall go up in real time. There is no hidden information in this
version.

## The board

A single arena, not two mirrored ones. One side is the Builder's platform, the other is a
firing position for the Attacker.

- Builder's platform: flat, with a marked build zone.
- The dummy (named **Princess** — it's a crash-test dummy, not a character) stands at a fixed
  point behind the build zone.
- Attacker's firing position sits across a gap at roughly the same ground elevation.
- The Princess must be positioned so that a well-aimed catapult shot can clear a short wall
  and reach her, but a tall wall makes that arc difficult. **This distance is the single most
  important tuning value in the game.** Expose it as a constant and expect to adjust it by
  feel.

## Blocks

- 12 blocks, identical, per round.
- Dimensions: **1.25 studs tall × 2.5 studs wide**. Depth 2.5 (my default — tune freely).
  This makes a block a quarter of a character's height and half a character's height wide.
  Twelve stacked two-wide and six-high produces a wall about 1.5 characters tall.
- Blocks are **indestructible**. They never break, deform, or despawn. They only fall.
- Plain `Part` primitives. No meshes, no `CollisionFidelity.Precise`.

### Build interaction

Click-and-place onto a grid within the build zone. Blocks snap to grid positions. Player can
pick up and re-place before confirming. A confirm button ends the build phase.

Blocks are **anchored** during the build phase.

## Weapons

The Attacker chooses freely between the two weapons on every shot. No ammo limits per type,
only the total shot count.

**Ballista**
- Free aim, **flat trajectory**, high velocity, minimal gravity effect.
- Because it's flat and fired from ground level, it naturally strikes low on the wall —
  the base. That is its identity: it removes foundations.
- Blocked by any standing wall. Cannot arc over.
- Once a wall is flattened, a ballista **can** hit the Princess directly.

**Catapult**
- Player sets **both force and angle**. Two-axis input.
- Arcs. Ignores wall height if aimed well.
- Less precise than the ballista by design.
- Can kill the Princess by direct hit, or by knocking blocks onto her.

## Win and loss

- Attacker gets **6 shots** per turn (my default — tune this first, it sets the difficulty).
- Princess dies from: a direct projectile hit, **or** contact with any moving block.
- **A block from the Builder's own wall counts as a kill.** This is intentional. An over-tall
  wall is a hazard to its own dummy.
- Dummy survives all 6 shots → Builder wins the round.
- Dummy dies → Attacker wins the round.
- Match is best of 4 rounds (2 per player as Attacker). Tie is acceptable.

## The design tension to preserve

12 blocks cannot buy both height and a thick base.

- **Tall and thin** blocks catapult arcs, but topples to one good ballista shot at the base —
  and the falling blocks may kill your own dummy.
- **Short and thick** resists the ballista, but leaves the Princess exposed to any decent arc.

If playtesting shows one build strategy dominating, the fix is in the tuning constants, not
in adding mechanics.

## Physics requirements — read carefully

This is the part most likely to be done wrong.

1. **All blocks must be server-owned.** Call `SetNetworkOwner(nil)` on every block. Never let
   a client own a structural part. This prevents split-assembly simulation disagreement and
   removes client authority over shot outcomes.
2. **Anchored during BUILD, unanchored at the start of ATTACK.** Anchored parts don't
   simulate and cost nothing.
3. Projectiles are also server-simulated and server-authoritative.
4. Blocks are separate assemblies — no welds between them. They rest on each other under
   gravity and friction only.
5. **Block mass and friction are the primary balance knobs.** They determine whether a base
   hit slides one block out and drops the stack straight down, or blasts through and
   scatters everything. Expose both as tunable constants. Expect to tune by feel.
6. Clear all debris and reset the arena at the start of each round.

## Tunable constants module

Put every one of these in a single `Config` ModuleScript so they can be adjusted without
hunting through code:

- Block dimensions, mass, friction, restitution
- Block count (12)
- Princess distance from build zone
- Gap width between platforms
- Ballista muzzle velocity, gravity scale
- Catapult min/max force, angle range
- Shots per turn (6)
- Rounds per match (4)

## Explicitly out of scope

Do not build: menus, lobbies, matchmaking, DataStore persistence, currency, cosmetics,
sound design, particle effects, leaderboards, mobile controls, or a tutorial. Two players in
a Studio playtest is the whole target.

## Definition of done

Two players can join a Studio playtest and, without instruction from outside the game:

1. See who is Builder and who is Attacker.
2. Builder places 12 blocks and confirms.
3. Attacker fires 6 shots, choosing weapon and aim on each.
4. The game correctly detects the Princess dying, including by falling block.
5. The round resolves, roles swap, and a second round begins.
6. After 4 rounds, a winner is declared.

Nothing beyond this. Get here first, then we tune.