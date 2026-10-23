class_name CharacterLook
extends Resource
## The recolorable slots of the golfer. A skin is just another one of these: the rig keeps one
## material per slot, so changing a look never needs new meshes.

@export var skin: Color
@export var shirt: Color
@export var outerwear: Color ## vest / coat: the shape that defines the silhouette
@export var pants: Color
@export var hat: Color ## the cap
@export var shoes := Color(0.17, 0.17, 0.18) ## the shoes (their soles stay light)
@export var club: Color ## club head, hosel and shaft: club skins recolor this
@export var hat_style := 0 ## 0 the cap, 1 a bucket hat, 2 a flat cap; reactive (HatToy): 3 Hat Green, 4 Course Goose, 5 Power Propeller (shop)
@export var shirt_style := 0 ## 0 plain, 1 flamingo print (shop)
@export var pants_style := 0 ## 0 slacks, 1 clash plaid, 2 knickerbockers (shop)
@export var shoe_style := 0 ## 0 golf shoes, 1 clown shoes, 2 bunny slippers (shop)
@export var club_style := 0 ## 0 the standard heads, 1 Fresh Catch (fish), 2 Squeaky Set (rubber chickens, a duck putter) (shop)
@export var trail_style := 0 ## BallTrail.style: 0 plain, 1 Bubble Stream, 2 Duck Parade, 3 Sad Smoke (shop)
@export var ball_color := Color(1, 1, 1, 0) ## the ball's main tone; alpha 0: the standard two-tone ball
@export var ball_accent := Color.WHITE ## its second tone (the stripe)
@export var ball_style := 0 ## 0 two-tone octants, 1 a stripe round the middle, 2 Meatball, 3 Disco Ball, 4 Eyeball
