# Shop

From the main menu, **Shop** opens the fitting room: your golfer on a turntable, a tab per
slot, and a card per item with its price and whether you own or wear it. Hovering or selecting a
card shows it on your golfer at once; **Buy** spends coins, **Equip** wears it. What you wear shows
on your own golfer and ball in every game and to everyone else in your rooms. On the **Trail** tab a
demo ball flies an arc over and over beside the golfer, trailing what you preview.

Coins are earned per hole (see `game/data/economy.tres`). Online the server holds the coins and
checks every purchase; offline the local profile (`user://profile.json`) does the same checks.
Every tab also has a free **Standard** item: the look you start with (on the Trail tab, the plain
white ribbon).

All items are vertex colours, small mesh swaps and a couple of procedural shaders (the plaid, the
socks, the glow), with no textures. Sounds are synthesised (`PlaceholderSounds`). Prices live in
`game/data/shop_catalog.tres`; the goofy items' tunables (spin speeds, roll, blink and honk timing,
flop, sound ranges) in `game/data/novelty.tres`.

| Tab | Item | Price | What it is |
|---|---|---:|---|
| Hat | Bucket hat | 120 | **Shape:** a round crown with a drooping brim, moss green |
| Hat | Flat cap | 150 | **Shape:** a low flat crown with a short peak, tweed brown |
| Hat | Hat Green | 300 | **Reactive:** a putting-green disc worn flat with a mini flagstick and cup; its ball rolls round the disc with the golfer's movement (the head's acceleration and tilt) and drops into the cup on a birdie or better (it pops back after a while) |
| Hat | Course Goose | 400 | **Reactive:** a chubby goose sitting on the head; it blinks and turns its head now and then, and honks (beak wide, neck stretched) on a bogey or worse |
| Hat | Power Propeller | 250 | **Reactive:** a four-panel beanie whose propeller spins with the swing's power, sputtering to a stop on a whiff (and staying stopped until the next swing) |
| Shirt | Mint polo | 80 | Colour: mint green |
| Shirt | Navy polo | 80 | Colour: navy |
| Shirt | Flamingo Tourist | 150 | **Print:** teal, with pink flamingos (and a palm leaf each) down the front and on the sleeves |
| Pants | Khaki slacks | 70 | Colour: khaki |
| Pants | Tour whites | 110 | Colour: off-white |
| Pants | Clash Plaid | 150 | **Pattern:** red tartan, green bands and thin yellow lines |
| Pants | Knickerbockers | 200 | **Shape:** tweed plus-fours puffed at the knee with a band, over green-and-cream argyle socks |
| Shoes | White spikes | 60 | Colour: white |
| Shoes | Brogues | 90 | Colour: brown leather |
| Shoes | Clown Shoes | 250 | **Shape:** long round-toed red shoes with a yellow bow; a floppy slap on every step while walking |
| Shoes | Bunny Slippers | 150 | **Shape:** fluffy white slippers with ears, eyes, a pink nose and whiskers |
| Ball | Hi-vis ball | 40 | Colour: orange octants |
| Ball | Tour stripe | 100 | **Shape:** white with a blue stripe round the middle |
| Ball | Meatball | 150 | **Shape:** lumpy and brown, seared bits and herb specks (the collider is the same ball) |
| Ball | Disco Ball | 250 | **Shape:** small silver mirror tiles, shiny; sparkles while rolling |
| Ball | Eyeball | 300 | **Shape:** white with a blue iris and black pupil; at rest, the pupil turns to face whoever is swinging |
| Club set | Gold set | 200 | Colour: gold heads and shafts |
| Club set | Black chrome | 160 | Colour: black chrome |
| Club set | Fresh Catch | 350 | **Heads:** each a stiff low-poly fish, its flat flank the face, sized to the club; on impact the tail flops and a wet slap plays, louder and lower the harder the hit; the putter is a flat flounder (both eyes on top). Visual and audio only |
| Club set | Squeaky Set | 300 | **Heads:** rubber chickens (neck and head past the toe), the putter a rubber duck; impact squeaks, higher and louder the harder the hit, and a drive over 80 % power drops the chicken's beak open. Visual and audio only |
| Trail | Bubble Stream | 150 | **Trail:** a line of small iridescent bubbles that wobble, swell and pop |
| Trail | Duck Parade | 300 | **Trail:** tiny rubber ducks tossed out behind the ball, tumbling down; a little pile of them where it lands, staying until the next shot |
| Trail | Sad Smoke | 200 | **Trail:** puffy grey smoke that droops as it goes, thinner the shorter (weaker) the shot |

28 items: 10 colour variants, 18 shape, print or behaviour variants.

**Trails** emit only while the ball is in the air (not rolling), and every bit of them is gone within
2 s; the plain trail (Standard) is the basic ribbon. **The novelty club heads** keep the standard
head's face plane: the same heel-to-toe span, height and loft, flattened onto the face, so the
hitbox, swing maths and contact offsets are unchanged (`feel_regression_test`, `contact_alignment_test`
and `fp_jerk_test` pass with each set equipped: `GOLF_TEST_EQUIP=club_fish` or `club_squeaky`).

**Other players** see all of it: the roster carries what each wears, so their hats, shirts, trousers,
shoes, ball, club heads and trail are drawn as they equipped them. The reactive parts run on their
golfers too: their propeller follows their streamed swing, their result against par sets off their
goose or sinks their green's ball, a whiff they make reaches you (the server relays it) and sputters
their propeller, and their impacts flop their fish tails and play their slaps and squeaks.

Renders: `docs/art/shop-wear.png`, `shop-clubs.png`, `shop-balls.png`, `shop-trails.png`
(`game/art/novelty_capture.gd`).
