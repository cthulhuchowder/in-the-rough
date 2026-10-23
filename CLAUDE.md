# In The Rough (golf project)
Goal: a first-person golf game with a physical mouse swing, our own art, a golf shop economy, dedicated server, desktop + mobile.
Current phase: 3 (swing locked; next: materials, coins, shop). Full plan in docs/plan.md.

Rules:
- All code, art, audio and names in game/ are our own; third-party assets are listed in THIRD_PARTY.md with their licences.
- Engine is Godot 4.7, Mobile renderer, project lives in game/. Input is a SwingGesture resource, never raw mouse events in game logic. Physics is server-authoritative. Procgen is seed-deterministic.
- Every number that tunes feel lives in a .tres resource, not in code.
- Each step ends with a playable build and a one-line entry in docs/changelog.md.
- The swing is locked: game/tests/feel_regression_test.gd guards swing math. Never change camera_back, the hitbox, or swing constants without it passing.
