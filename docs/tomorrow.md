# Tomorrow

Base: 3.1l-c (first-person framing) plus the uniform first-person view (d0b8f0a). Do NOT touch swing math, hitbox, or the rendered camera's yaw.

1. ~~Club switch camera bug: after switching clubs the rendered camera is left at the old club's pullback/stance. Re-run camera placement after the new club's camera pull and stance distance are set. Test: switch club, assert camera transform == fresh Shooting-entry transform.~~ **Done (d0b8f0a, "uniform first-person view"):** with `view_use_driver_framing` the rendered camera uses the driver's camera pull and stance for every club, so it is the same view whichever club is in hand; swing_test asserts that after switching to each club the camera equals a fresh Shooting-entry transform and that the view is identical across clubs.
2. Club lean: lean the first-person club about the camera→ball axis so the grip swings toward lower-right and the shaft reads as a diagonal. Keep the club centered where it is in 3.1l-c. Visual only.
3. 3.1m: contact alignment (face plane at hitbox leading edge; slow-push test) + first-person club scale.
4. Cup 1.5× bigger.
5. Rolling readability: stronger ground vertex noise, bold two-tone spinning ball.
6. Server redeploy (3.1e visible swings + 3.1k cup physics are pending) and verify with friend.
7. Then: wind, 3.2 biomes with real trees.
