class_name NetParams
extends Resource
## Networking tunables. Values live in data/net.tres.

@export var port: int ## UDP
@export var max_players: int
@export var default_address: String
@export var snapshot_hz: float ## server → client ball states
@export var prediction_window: float ## s the own ball runs locally before snapping to server state
@export var interp_delay: float ## s remote balls render behind the newest snapshot
@export var extrapolate_max: float ## s a ball may run on past its newest snapshot
@export var tee_slot_spacing: float ## m between players' balls across the tee, in join order
@export var scorecard_delay: float ## s after everyone finishes before the next hole
@export var bot_think_time: float ## s a test bot waits at rest before shooting
@export var bot_walk_time: float ## s a test bot walks before its second shot
@export var holes_per_round: int
@export var room_code_length: int
@export var tab_hold_time: float ## s Tab must be held to show the full scorecard (a tap cycles spectating)
@export var spectate_distance: float ## m behind the followed ball
@export var spectate_height: float ## m above it
@export var spectate_look_gain: float ## rad per look unit
@export var steam_app_id: int
@export var swing_send_hz: float ## own swing angle and pitch to the room while in Shooting
@export var walk_send_hz: float ## own position and facing to the room while walking
@export var walk_timeout: float ## s without a walk sample before a remote golfer goes back to address
@export var walk_max_range: float ## m from their own ball the server accepts a walk pose
@export var flyover_wait_max: float ## s the server waits for every player's hole flyover before shots count
@export var chat_max_length: int ## characters in one chat line (the server trims)
@export var chat_min_interval: float ## s between one player's chat lines (faster ones are dropped)
