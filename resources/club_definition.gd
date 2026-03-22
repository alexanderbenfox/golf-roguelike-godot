class_name ClubDefinition
extends Resource

enum ClubType { WOOD, IRON, HYBRID, WEDGE, PUTTER }

@export var id: String = ""
@export var display_name: String = ""
@export var club_type: ClubType = ClubType.IRON

# -- Shot shape --
## Multiplier on max shot power. Driver = 1.0 (full), Putter = 0.15.
@export_range(0.0, 2.0) var power_scale: float = 1.0

# -- Angle --
## Minimum launch angle in degrees.
@export_range(0.0, 90.0) var min_angle_deg: float = 20.0
## Maximum launch angle in degrees.
@export_range(0.0, 90.0) var max_angle_deg: float = 35.0
## Default launch angle when club is first selected.
@export_range(0.0, 90.0) var default_angle_deg: float = 28.0

# -- Swing timing --
## How fast the power indicator fills (percent per second). Higher = faster.
@export_range(1.0, 15.0) var swing_fill_speed: float = 5.0
## How fast the accuracy indicator returns (percent per second). Higher = harder.
@export_range(1.0, 15.0) var swing_return_speed: float = 7.0
## Multiplier on sweet spot width. Higher = more forgiving.
@export_range(0.3, 3.0) var sweet_spot_scale: float = 1.0

# -- Landing behavior --
## Multiplier on ball bounce at landing. Low = ball stops faster.
@export_range(0.0, 2.0) var landing_bounce: float = 1.0
## Extra friction applied while ball is rolling after this club's shot.
@export_range(0.0, 3.0) var landing_friction: float = 1.0

# -- Auto-selection hints --
## Minimum distance to pin (metres) where this club is suggested.
@export var suggest_min_distance: float = 0.0
## Maximum distance to pin where this club is suggested.
@export var suggest_max_distance: float = 999.0
## Zone types where this club is auto-suggested (e.g., putter on GREEN).
@export var suggest_zones: Array[int] = []
