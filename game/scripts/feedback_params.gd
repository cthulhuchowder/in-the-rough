class_name FeedbackParams
extends Resource
## Impact feedback, power meter and club wheel tunables. Values live in data/feedback.tres.
## Screen sizes are in pixels at 1080p and scale with the window height.

@export_group("Sound")
@export var hit_volume_db: Vector2 ## at power 0 and 1
@export var hit_pitch: Vector2 ## at power 0 and 1
@export var driver_hit_pitch: Vector2
@export var swish_volume_db: float
@export var remote_hit_volume_db: Vector2 ## another player's hit, at power 0 and 1
@export var remote_hit_pitch: Vector2 ## and its pitch, every club alike

@export_group("Ball trail")
@export var trail_time: float ## s a trail point lasts, fading out
@export var trail_width: float ## m
@export var trail_color: Color


@export_group("Ball")
@export var impact_nudge_margin: float ## m: on the hit tick a ball the drawn face has reached is drawn this far ahead of it (Ball.nudge_view)
@export var impact_nudge_time: float ## s it eases back onto the real ball
@export var ball_spin_max: float ## rad/s, drawn spin cap: the octants never step a half-pattern per frame

@export_group("Wind streaks")
@export var wind_streak_amount: int ## streaks alive at once, drifting past the ball at address
@export var wind_streak_lifetime: float ## s
@export var wind_streak_length: float ## m
@export var wind_streak_speed: float ## × the wind speed
@export var wind_streak_upwind: float ## m upwind of the ball they start
@export var wind_streak_height: float ## m above the ball
@export var wind_streak_min_speed: float ## m/s: calmer than this, none
@export var wind_streak_color: Color ## alpha is the peak, they fade in and out

@export_group("Power meter")
@export var meter_min_power: float ## below this the bar ignores the swing
@export var meter_hold: float ## hold value set by a new maximum
@export var meter_hold_decay: float ## 1/s: 1.0 at 2/s is a 0.5 s hold
@export var meter_fall_time: float ## s, sine ease-out to zero
@export var meter_size: Vector2
@export var meter_margin: float
@export var meter_back: Color
@export var meter_frame: Color
@export var meter_power: Color
@export var meter_spin: Color
@export var meter_peak: Color

@export_group("Compass")
@export var compass_size: Vector2 ## px at 1080p: the dial, top centre
@export var compass_margin: float ## px from the top
@export var compass_span_deg: float ## degrees of bearing across the dial, centred on the aim
@export var compass_font: int
@export var compass_tick: Color
@export var compass_pin: Color
@export var compass_tee: Color
@export var compass_wind: Color

@export_group("Club wheel")
@export var wheel_outer: float
@export var wheel_inner: float
@export var wheel_gap: float
@export var wheel_bevel: float ## px of the darker rim on each slice
@export var wheel_pop: float ## px the highlighted slice moves out
@export var wheel_deadzone: float ## px of mouse travel before a slice is picked
@export var wheel_slice: Color
@export var wheel_rim: Color
@export var wheel_highlight: Color
@export var wheel_text: Color
@export var wheel_icon: Color
@export_group("Scorecard")
@export var card_panel: Color ## the card's background (dark, see-through, like the HUD)
@export var card_line: Color ## thin row separators
@export var card_text: Color ## names, and a par
@export var card_muted: Color ## hole numbers and the PAR row
@export var card_good: Color ## birdie or better
@export var card_bad: Color ## bogey or worse
@export var card_cell: Vector2 ## px: a hole column's width, a row's height
@export var card_name_width: float ## px: the player column
@export var card_total_width: float ## px: the TOTAL column
@export var card_avatar: float ## px: the avatar disc
@export var rules_font: int ## the rules line (top right, Tab held)
@export var rules_margin: float ## px from the corner
@export_group("HUD")
@export var hud_margin: float ## px from the top-left corner
@export var hud_height: float ## px: the top-left pill
@export var hud_padding: float ## px, left and right inside the top-left pill
@export var hud_line_font: int ## "Shot N · Par P · D m"
@export var hud_dim_alpha: float ## the HUD while swinging and the ball is out (back to full once it settles)
@export var hud_dim_rate: float ## 1/s: how fast it dims and returns
@export var chip_gap: float ## px between the shot pill and the club pill under it
@export var coin_color: Color ## the coin icon and the "+N" pop
@export var coin_clink_db: float
@export var chip_size: float ## the club pill's font, padding and height, as a share of the shot pill's
@export var chip_pulse_scale: float ## the caddy pulse's peak size
@export var chip_pulse_time: float ## s per pulse
@export var chip_pulse_count: int
@export_group("Chat")
@export var chat_lines: int ## log lines kept
@export var chat_life: float ## s a line stays before fading
@export var chat_fade: float ## s it fades over
@export var chat_font: int
@export var chat_width: float ## px: the box and the log
@export var chat_margin: float ## px from the bottom-left corner (at 1080p)
@export var chat_blip_db: float
