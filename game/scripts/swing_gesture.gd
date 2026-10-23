class_name SwingGesture
extends Resource
## Device-agnostic swing input for one physics tick. A feeder (mouse now, touch later)
## writes it; the swing reads it and never sees the device.

## Swing angle change this tick, rad. Negative = backswing.
var angle_delta := 0.0
## Swing-plane tilt change this tick, rad. Positive = away from the golfer.
var pitch_delta := 0.0
## Hand motion this tick projected on the ground, world space. Only its direction matters.
var path_delta := Vector3.ZERO
## Look input this tick in device units (mouse: pixels), before any sensitivity. Aim and walk read it.
var look := Vector2.ZERO
## Aim (look down the line) is held.
var aim_held := false
var zoom := 0.0 ## mouse wheel notches this tick (+ = in): the walk camera's zoom
## A UI overlay (the club wheel) owns the mouse: the swing gets no angle or pitch while true;
## look still flows so the overlay can steer.
var blocked := false
