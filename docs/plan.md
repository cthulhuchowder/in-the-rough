# In The Rough — build plan

Oct 17, 2026

**Status:** Phase 3 (swing locked; next: materials, coins, shop).

## Goal & principles

Build a first-person golf game with a mouse-motion swing that feels great, runs smooth for two friends online, and grows into a cozy golf-shop game that ships on desktop and mobile.

Three milestones, in order, each one playable before the next starts:

1. **Core (desktop).** The swing, procedural holes, 2-player online, no lag. Placeholder art.
2. **Ours.** New scenery, coins per hole, golf shop, skins for ball/clubs/outfit, real art direction.
3. **App.** Touch swipe input, mobile build, Steam + mobile lobbies.

Rules we don't break:

- All code, art, audio, and names are our own.
- One codebase from day one. The core build is the foundation of the final game, so engine, netcode, and input abstraction are chosen for mobile and multiplayer even though milestone 1 is desktop-only.
- Swing first. Nothing else gets built until the swing feels right over a network, judged by two people playing it.
- Claude Code does the typing; we do the judging. Every phase has a definition of done that a human checks by playing.

## Phase 0: Setup

**Engine: Godot 4.7, Mobile renderer.** Reasons: free, exports to Windows/Linux/Mac/iOS/Android from one project, built-in high-level multiplayer with a dedicated-server mode, small binaries, and Claude Code writes clean GDScript fast.

**Repo layout** (one git repo):

| Folder | What lives there |
| --- | --- |
| `game/` | The Godot project |
| `server/` | Headless dedicated-server export + Docker file |
| `docs/` | Design notes Claude Code writes as it goes (swing, physics, procgen, netcode, shop) |
| `CLAUDE.md` | Goal, current phase, and rules |

**Tools to have installed before the first session:** Godot 4 editor + export templates, git, Python 3, Steam SDK test app (AppID 480) for lobby invites later.

**The home server (a Proxmox mini PC):** an always-on box that helps in three places.

- **Dedicated game server.** One small LXC/VM running the headless Godot server build. Both players connect to it, so nobody hosts, NAT is a non-issue, and physics runs in one place.
- **Build box.** A second container with Godot headless + export templates runs exports for Windows/Linux (and later Android) on every push, so testers always download the latest build from a link.
- **Git host + Claude Code runner.** Gitea or plain bare repos for the code, and a container where long Claude Code sessions run without tying up a desktop.

No GPU passthrough needed. A headless Godot server and the export pipeline are CPU-only.

**Definition of done:** repo exists with `CLAUDE.md`, an empty Godot project opens and exports a Windows build, and a "hello" headless server runs in a Proxmox container that a friend can reach from outside the home network (port-forward or a private VPN).

## Phase 1: Design

Design notes for each system, written before any game code, each with the numbers and formulas the implementation will use:

- **Swing:** mouse delta → shot vector. Sample rate, speed-to-distance curve, curve-to-sidespin mapping, backswing/downswing detection, how loft comes from the club.
- **Ball physics:** ball mass, drag, Magnus lift, bounce restitution and friction per surface (fairway, rough, green, sand, cart path), roll-out, wind, what counts as out of bounds and water.
- **Clubs:** carry, loft, dispersion, min/max power, which lies each is allowed from.
- **Procgen:** seed handling, hole length and par rules, terrain noise, hazard placement, green shape, tee and pin placement, how all players get the same hole.
- **Netcode:** who is authoritative, what is replicated per tick, lobby flow, and how we avoid lag (physics in one place on a dedicated server, clients send input only).
- **Rules & UI:** scoring, turn order, spectate mode, settings.

**Definition of done:** each note is small enough to read in five minutes, and someone can read the swing note and understand how a shot is computed without opening any code.

## Phase 2: Core game

A clean Godot build that plays well and runs on our own server. Built in this order, each step playable before the next.

| Step | Build | Done when |
| --- | --- | --- |
| 2.1 Swing + ball | Flat green, one club, mouse-motion swing, ball flight with drag, lift and bounce | Two people agree a shot goes where the mouse motion says it should |
| 2.2 Surfaces + clubs | Fairway, rough, green, sand, water, OB; full club table; lie rules | Full hole from tee to cup, scored correctly |
| 2.3 Procgen | Seeded hole generator | Same seed = same hole on two machines; 50 random seeds all playable |
| 2.4 Dedicated server | Headless server on Proxmox, server-authoritative ball sim, clients send swing input only | Two players play a full 9 from different networks with no stutter |
| 2.5 Lobby + rounds | Join by code or Steam invite (AppID 480), turn order, spectate in third person, scorecard | Two people complete a round without touching the console |
| 2.6 Feel pass | Tune anything that feels off; feel tests (`game/tests/feel_regression_test.gd`) guard the swing math | Both players agree it feels right (done: swing locked) |

**Architecture decisions locked here so Phase 3 and 4 need no rewrite:**

- **Input is a gesture, not a mouse.** One `SwingGesture` resource holds sampled points, velocity, and curvature. Mouse feeds it on desktop; touch feeds it on mobile. The swing math never sees a device.
- **Server-authoritative physics.** The server simulates the ball; clients render it and predict locally for the first 100 ms so it feels instant. This is what makes 8-player lobbies lag-free and what stops cheating later.
- **Deterministic procgen.** Holes come from a seed only, so the server sends 8 bytes, not a mesh.
- **Data-driven everything.** Clubs, surfaces, and later skins are `.tres` resource files, not code. Changing a number never means recompiling.
- **Placeholder art is deliberately ugly.** Flat colors, no textures. Anything prettier tempts an art pass before the feel is right.

**Server on Proxmox:** one LXC with the headless export, a systemd service that restarts it, and a port forwarded (or a private VPN for a small group). The client connects to the server address in `data/net.tres`. Later this same container runs multiple rooms.

## Phase 3: Make it ours (current)

The core build becomes a distinct game. Start only after 10+ rounds of Phase 2 and still wanting more.

**Scenery and biomes.** Procgen gets a `biome` parameter (the game now has 7 biomes). Each biome is a palette, a set of scenery props, tweaks to terrain noise, and its own ambience. The hole rules stay the same, so nothing about the swing changes.

**Economy, kept deliberately small at first:**

- Coins per hole: a base amount, plus bonuses for under-par, longest drive, closest to pin. Served and stored server-side so it can't be edited. Coins belong to the player's key, not their display name, so renaming keeps your coins.
- The shop is a small lot your character walks around between rounds. Spend coins on stalls, a sign, a putting mat. Friends see your shop when they visit your lobby, which is what makes cosmetics worth owning.
- Skins: ball, club set, outfit, swing trail. Each is a resource file; adding one means adding a file, not code.
- Cap it. Phase 3 ships with one shop, four stall types, about 12 skins. A second currency, crafting, or crops is not Phase 3. If the shop loop is fun small, it will be fun bigger later.
- A practice range for trying clubs and skins without a round.

**Art direction.** Pick one look that is cheap to produce consistently and reads as distinct in a thumbnail. Good fits for a solo pipeline: flat-shaded low-poly with a strong palette, or a paper-cutout style. Decide the look with three mock screenshots before touching any asset.

**Persistence.** Player profile, coins, and unlocks move to a small SQLite or Postgres on the Proxmox box, behind the game server. This is also what makes a mobile account possible in Phase 4.

**Definition of done:** a new player can play a round, earn coins, buy a skin, see it in the next round, and a friend visiting sees their shop. Ten rounds in, both players still want to keep playing.

## Phase 4: Mobile app

Because input was a gesture from day one, mobile is mostly a new input feeder, a UI layout pass, and a build pipeline.

- **Touch swing.** `SwingGesture` gets a touch feeder: finger speed → power, finger curve → shape, release direction → start line. Tune on a real phone; a swipe is shorter and faster than a mouse stroke, so the speed-to-distance curve gets a mobile scale factor, not a rewrite.
- **UI.** Scorecard, club picker, and shop re-laid for portrait and thumbs. Scouting walk uses a virtual stick or tap-to-move.
- **Cross-play.** Same dedicated server, same protocol. Desktop and mobile players share lobbies by code; Steam invites stay desktop-only.
- **Builds.** Android first (Godot export + a keystore, sideload to a phone, then internal testing on Play). iOS needs a Mac and an Apple developer account ($99/yr), so it comes last.
- **Accounts.** The Phase 3 profile database gets a simple login (email code or Steam/Google sign-in) so a player's coins and skins follow them between desktop and phone.

**Scope guard:** a 9-hole round on a phone should take under 10 minutes. If it doesn't, the mobile mode offers 3- and 6-hole rounds rather than cutting the mechanic.

**Definition of done:** a round on a phone against a friend on desktop, from the same server, and the swing feels right to both.

## Claude Code prompts

Copy these as-is when each phase starts. The `CLAUDE.md` goes in the repo root before anything else.

**CLAUDE.md (write once, update the phase line as you go):**

```markdown
# In The Rough (golf project)
Goal: a first-person golf game with a mouse-motion swing, our own art, a golf shop economy, dedicated server, desktop + mobile.
Current phase: 3 (swing locked; next: materials, coins, shop). See docs/plan.md.

Rules:
- Engine is Godot 4.7, Mobile renderer, project lives in game/. Input is a SwingGesture resource, never raw mouse events in game logic. Physics is server-authoritative. Procgen is seed-deterministic.
- Every number that tunes feel lives in a .tres resource, not in code.
- Each step ends with a playable build and a one-line entry in docs/changelog.md.
- game/tests/feel_regression_test.gd guards swing math. Never change the camera distance, the hitbox, or swing constants without it passing.
```

**Phase 2 prompt (step 2.1; later steps reference the table in the plan):**

> Read the swing and ball-physics design notes in `docs/`. Create the Godot 4 project in `game/`. Implement `SwingGesture` (sampled points, velocity, curvature; a mouse feeder now, touch later), the swing-to-shot function, and ball flight with drag, Magnus lift, and bounce on a flat green. All tunables in `game/data/*.tres`. Add a debug overlay showing shot vector and landing point. Export a Windows build and tell me how to test the feel.

**Phase 2 prompt (step 2.4, server):**

> Add a headless server export in `server/`. Move ball simulation to the server; clients send `SwingGesture` and render replicated ball state with 100 ms local prediction. Write a Dockerfile and a systemd unit for a Debian LXC. Use ENet via Godot's high-level multiplayer. Document the ports and how a second player connects.

**Phase 3 and 4 prompts** follow the same shape: name the design note or plan section, name the data files, demand a playable build, and forbid touching the swing math.

## Risks

| Risk | Why it matters | What we do |
| --- | --- | --- |
| The swing doesn't feel right | Everything downstream depends on the swing | Debug overlay and feel tests; don't leave 2.1 until two people agree |
| Scope creep into the farm | A second game inside the first | Phase 3 caps: one shop, four stalls, \~12 skins. Anything else goes in a `docs/later.md` list |
| Server exposed to the internet | The home network is behind it | Private VPN for a small group; only move to a port-forward when strangers need to join, and then with the server in its own LXC and no other services on it |
| iOS cost and friction | $99/yr plus a Mac | Android first; iOS only if the Android version has players |
| "Big game" expectations | Casual golf is crowded | Treat Phase 3's art direction as the test: if three mock screenshots don't look distinct in a thumbnail, the look isn't ready |
