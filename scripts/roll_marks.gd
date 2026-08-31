class_name RollMarks
extends Node3D

## The track the ball presses into the ground behind it, and the dent a heavy
## landing leaves in it.
##
## Hangs off the ball and reads it, so a level does not have to wire anything up
## -- dropping the player scene in is enough. The marks are left on the level
## rather than on the ball: see [method _bind_to_level].
##
## They are DRAWN GEOMETRY, not decals, and that is not the obvious choice. A
## decal is projected onto whatever is under it and would take the shape of the
## ground for free -- but the mobile renderer this game uses will only put EIGHT
## of them on any one surface, and drops the rest. A trail is a line of marks on
## a single floor, so the eight would be spent within a metre and the tail would
## flicker in and out as the ninth was pressed. Measured, not assumed: twenty
## decals laid in a row on one mesh drew eight.
##
## So the track is one ribbon of triangles laid along the ground and the craters
## are quads laid on it, all rebuilt each frame into a single mesh. There is no
## cap on it, it is one draw call however long the trail gets, and every point of
## it is placed where a ray found the floor, so it follows the ground it is
## pressed into.
##
## What it looks like belongs to `ground_mark.gdshader`; all this does is decide
## where the marks go, how big they are, and how long they last.

## How far the ball travels between one point of the track and the next, in
## metres. The ribbon is drawn through these, so this is how finely it follows
## the ground rather than how far apart the marks are.
@export var mark_spacing := 0.18

## How wide the track is, in metres. Under the ball's own width -- a marble
## presses a patch, not its whole face.
@export var track_width := 0.42

## How long a stretch of track lasts before the ground has closed over it.
@export var track_life := 2.5

## Below this speed nothing is pressed. A ball barely moving is resting on the
## ground rather than working it.
@export var quiet_speed := 0.6

## How far below the ball's underside the ground may be and still take a mark.
## Small: a ball this far off it is airborne, and presses nothing.
@export var floor_reach := 0.12

## Which layers can be marked. The stage, by default.
@export_flags_3d_physics var floor_layers := 1

## How far the marks are held off the surface, in metres. Enough to keep them out
## of the floor they are drawn over, little enough that they still look pressed
## into it rather than hovering over it.
@export var lift := 0.012

## The most points the track is kept to. At the spacing above this is several
## metres of trail; the oldest are dropped first when it runs over.
@export var track_points := 96

@export_group("Impacts")

## The blow the ball has to take before it dents the ground, in newton-seconds.
## The same measure, and the same numbers, as [member ImpactBurst.heavy_impulse]:
## the impulse the solver put through the contact, not how fast the ball happens
## to be going. Set alongside it so the crater and the shards go together.
@export var heavy_impulse := 55.0

## The blow that digs the full crater. Between the two it comes up smoothly.
@export var full_impulse := 130.0

## How long before another crater can be dug. One landing reports a flurry of
## contacts over several ticks, and without this each one digs its own.
@export var quiet_gap := 0.15

## How wide a crater is, for the lightest blow that counts and for the hardest.
@export var soft_crater := 0.7
@export var hard_crater := 1.5

## And how long one lasts. Longer than the track: it is a bigger hole.
@export var crater_life := 3.5

## The most craters that may be on the ground at once.
@export var crater_count := 6

@export_group("Look")

@export var mark_shader: Shader = preload("res://materials/shaders/ground_mark.gdshader")

## How much light the hollow of a mark keeps out.
@export_range(0.0, 1.0) var hollow_shade := 0.45

## And how much the lip thrown up round it catches.
@export_range(0.0, 1.0) var lip_light := 0.025

## How much the track varies in strength along its length. Ground is not even,
## and a mark of exactly one weight from end to end reads as a drawn line.
@export_range(0.0, 1.0) var grain := 0.3

@export_group("Skin")

## How big the picture of the marble is that the marks are drawn out of, in
## pixels. Small on purpose: it is smeared into a groove a few centimetres wide,
## and there is nothing in it worth resolving further.
@export var skin_resolution := 96

## How far along the track a full turn of that picture is laid, in metres. Short
## enough that the track is made of marble rather than of one stretched smear.
@export var skin_repeat := 0.9

var _ball: RigidBody3D
var _radius := 0.5

## The track, oldest first: where each point is, which way the ground faces
## there, which way is across the track, and how long it has been down.
var _track: Array[Dictionary] = []

## The craters, oldest first.
var _craters: Array[Dictionary] = []

var _since_crater := 0.0

## Cleared until the marks have been taken off the ball. Anything pressed before
## then would be stored in the ball's own frame -- where the ground under it is
## always the same point, whatever the ball is doing -- and left stranded once
## the node moves off it.
var _bound := false

var _marks: MeshInstance3D
var _mesh: ImmediateMesh
var _track_material: ShaderMaterial
var _crater_material: ShaderMaterial

## How far the ball has rolled in total, in metres. The track is laid out along
## this, so the marble's own picture runs down the trail at a fixed size on the
## ground instead of being stretched between whatever points happen to be there.
var _rolled := 0.0

## The marble, drawn small and on its own, for the marks to be made out of.
var _skin_view: SubViewport
var _skin_ball: MeshInstance3D


func _ready() -> void:
	_ball = get_parent() as RigidBody3D
	if _ball == null:
		push_warning("%s: expected to hang off the ball; no marks will be left" % name)
		set_physics_process(false)
		set_process(false)
		return

	_radius = _measure_ball()
	_build_mesh()
	_wear_skin_trail()
	_bind_to_level()

	# The skin can be changed while a marble is on the ground -- the dev tools do
	# it -- and what it leaves behind should change with it.
	GameState.marble_skin_changed.connect(func(_id: String) -> void: _wear_skin_trail())


func _build_mesh() -> void:
	_track_material = ShaderMaterial.new()
	_track_material.shader = mark_shader
	_track_material.set_shader_parameter("radial", false)
	_track_material.set_shader_parameter("hollow_shade", hollow_shade)
	_track_material.set_shader_parameter("lip_light", lip_light)

	# The same shader read the other way round: out from the middle rather than
	# across a width.
	_crater_material = _track_material.duplicate()
	_crater_material.set_shader_parameter("radial", true)

	_mesh = ImmediateMesh.new()
	_marks = MeshInstance3D.new()
	_marks.mesh = _mesh
	_marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marks)

	_build_skin_view()


## Draws the marble a second time, small, off to one side of the world, so the
## marks have something to be made out of.
##
## The skins cannot simply be put on the marks instead. Every one of them is
## written for a BALL -- it reads the direction out from the middle of the marble,
## or walks a ray across the chord of it -- and a ribbon lying on the floor has
## neither. Drawing the real thing into a small picture and reading that picture
## back is what lets a mark be made of lava rather than of a colour someone chose
## to stand for lava, and it keeps working for every skin ever added without any
## of them knowing about the ground.
##
## It is its own little world, lit its own way, so a level's lighting cannot turn
## the trail black in a dark room.
func _build_skin_view() -> void:
	_skin_view = SubViewport.new()
	_skin_view.size = Vector2i(skin_resolution, skin_resolution)
	_skin_view.own_world_3d = true
	_skin_view.transparent_bg = true
	_skin_view.msaa_3d = Viewport.MSAA_DISABLED
	# Only drawn while there is something on the ground to draw with it.
	_skin_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_skin_view)

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.7, 0.72, 0.75)
	sky_material.sky_horizon_color = Color(0.7, 0.72, 0.75)
	sky_material.ground_horizon_color = Color(0.7, 0.72, 0.75)
	sky_material.ground_bottom_color = Color(0.7, 0.72, 0.75)

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	var world := WorldEnvironment.new()
	world.environment = environment
	_skin_view.add_child(world)

	var light := DirectionalLight3D.new()
	light.transform = Transform3D(Basis.from_euler(Vector3(-0.6, -0.5, 0.0)), Vector3.ZERO)
	_skin_view.add_child(light)

	# Straight on and square, so the middle of the picture is the middle of the
	# marble whatever is being worn.
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.05
	camera.position = Vector3(0.0, 0.0, 2.0)
	_skin_view.add_child(camera)

	_skin_ball = MeshInstance3D.new()
	_skin_ball.mesh = SphereMesh.new()
	_skin_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_skin_view.add_child(_skin_ball)


## Puts whatever the player's marble leaves behind it into the marks.
##
## Asked of the catalogue rather than read off the marble's own material: the
## skins are drawn by two dozen shaders that name their colours nothing alike,
## and a mark on the floor has no business knowing which one it is following.
## See [method MarbleSkins.trail_for].
func _wear_skin_trail() -> void:
	var trail := MarbleSkins.trail_for(GameState.marble_skin)
	var colour: Color = trail["colour"]
	var glow: float = trail["glow"]

	# Only the skins that leave something behind are worth drawing twice.
	var skin_material := MarbleSkins.material_for(GameState.marble_skin)
	var leaves_something := glow > 0.0 and skin_material != null
	_skin_ball.material_override = skin_material if leaves_something else null

	for material: ShaderMaterial in [_track_material, _crater_material]:
		material.set_shader_parameter("trail_colour", colour)
		material.set_shader_parameter("use_skin", leaves_something)
		material.set_shader_parameter("skin_texture", _skin_view.get_texture())

	_track_material.set_shader_parameter("trail_glow", glow)
	# A crater is where the marble hit hardest, so more of it is left there.
	_crater_material.set_shader_parameter("trail_glow", minf(glow * 1.25, 1.0))


## Moves the marks onto the level, so they are left on the ground rather than
## carried around by the ball that pressed them.
##
## The wait is for the level: it puts itself in its group from its own `_ready`,
## and it sits below the ball in the scene, so it has not run yet when this does.
## Nothing has been pressed by then, so nothing is dragged along in the meantime.
## With no level to bind to -- a test scene, say -- the marks are left in the
## world, which comes to the same thing as long as nothing moves the floor.
func _bind_to_level() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return

	var level := get_tree().get_first_node_in_group("level_body") as Node3D
	var home := level if level != null else get_tree().current_scene
	if home == null or home == self:
		return

	# Whatever it is bound to, this node has to stop moving with the ball, or
	# every mark on the ground rides along with it.
	reparent(home, false)
	transform = Transform3D.IDENTITY
	_bound = true


func _physics_process(delta: float) -> void:
	_since_crater += delta

	# The marks are left on the level, so they outlive the ball that pressed
	# them -- a level restarted takes the ball with it and leaves this behind.
	# Nothing more is pressed after that; what is already down fades out, and
	# then this goes too.
	if not is_instance_valid(_ball):
		set_physics_process(false)
		return

	if _ball.freeze or not _bound:
		return

	_dig_crater()
	_lay_track()


## The track: a point laid every [member mark_spacing] of travel, wherever the
## ground is under the ball at the time.
##
## The ground is found with a short ray straight down rather than from the
## contacts the ball reports, for the same reason the sparks are: a ball pressed
## against a wall is touching something, but a track belongs on the floor.
func _lay_track() -> void:
	var travel := _ball.linear_velocity
	if travel.length() < quiet_speed:
		return

	var ground := _ground_under()
	if ground.is_empty():
		return

	var at: Vector3 = to_local(ground["position"])
	var stepped := 0.0
	if not _track.is_empty():
		stepped = at.distance_to(_track[-1]["at"])
		if stepped < mark_spacing:
			return

	var up: Vector3 = (global_transform.basis.inverse() * ground["normal"]).normalized()

	# Across the track, along the ground: the ribbon has to be laid out flat on
	# the floor whatever the floor is doing.
	var along := (global_transform.basis.inverse() * travel).normalized()
	var side := along.cross(up)
	if side.length_squared() < 0.0001:
		return

	# Each point is worth a little more or less than its neighbours, decided
	# once and kept, so the unevenness holds still on the ground instead of
	# crawling along the track.
	var weight := 1.0 - randf() * grain

	_rolled += stepped

	_track.append({
		"at": at, "up": up, "side": side.normalized(), "age": 0.0, "weight": weight,
		"rolled": _rolled})

	if _track.size() > track_points:
		_track.remove_at(0)


## The crater: one dug wherever the ball was struck hardest, as wide as the blow
## was heavy.
func _dig_crater() -> void:
	if _since_crater < quiet_gap:
		return

	var blow := _hardest_contact()
	if blow.is_empty() or blow["impulse"] < heavy_impulse:
		return

	_since_crater = 0.0

	var force := clampf(
			(blow["impulse"] - heavy_impulse) / maxf(full_impulse - heavy_impulse, 0.01),
			0.0, 1.0)

	var up := _away_from_surface(blow["point"], blow["normal"])

	# Not dug where the contact was reported. A hard landing drives the ball
	# into the floor before the solver pushes it back out, and the contact it
	# reports is the point on the BALL -- which by then is under the surface, so
	# a crater put there is buried in the floor and never seen. Measured: a ball
	# dropped four metres reported its contact 13cm under the ground.
	#
	# So the surface itself is looked up, from just outside it, and the crater is
	# laid on what the ray finds -- which hands back a true surface normal into
	# the bargain.
	var surface := _surface_at(blow["point"], up)
	if surface.is_empty():
		return

	up = surface["normal"]
	var side := up.cross(Vector3.FORWARD)
	if side.length_squared() < 0.0001:
		side = up.cross(Vector3.RIGHT)

	_craters.append({
		"at": to_local(surface["position"]),
		"up": (global_transform.basis.inverse() * up).normalized(),
		"side": (global_transform.basis.inverse() * side).normalized(),
		"radius": lerpf(soft_crater, hard_crater, force) * 0.5,
		"age": 0.0,
	})

	if _craters.size() > crater_count:
		_craters.remove_at(0)


func _process(delta: float) -> void:
	_age_marks(delta)
	_draw_marks()

	# The marble is only worth drawing a second time while there is something on
	# the ground made out of it.
	var marked := not _track.is_empty() or not _craters.is_empty()
	_skin_view.render_target_update_mode = (SubViewport.UPDATE_ALWAYS if marked
			else SubViewport.UPDATE_DISABLED)

	if not is_instance_valid(_ball) and _track.is_empty() and _craters.is_empty():
		queue_free()


func _age_marks(delta: float) -> void:
	# Oldest first in both, so the ones that are done are always at the front.
	while not _track.is_empty() and _track[0]["age"] >= track_life:
		_track.remove_at(0)
	while not _craters.is_empty() and _craters[0]["age"] >= crater_life:
		_craters.remove_at(0)

	for point in _track:
		point["age"] += delta
	for crater in _craters:
		crater["age"] += delta


## How much of a mark is left after it has been down for [param age] seconds.
## Held for a moment and then let go, rather than fading from the instant it was
## pressed: ground closes over a dent slowly at first.
func _left_of(age: float, life: float) -> float:
	return 1.0 - smoothstep(0.45, 1.0, age / maxf(life, 0.001))


func _draw_marks() -> void:
	_mesh.clear_surfaces()
	_draw_track()
	_draw_craters()


## The track laid down behind the ball.
##
## A new ribbon is started wherever the ball left the ground: the points either
## side of a jump are neighbours in the list but not on the floor, and running
## one ribbon straight through would stretch a single quad across the whole gap.
func _draw_track() -> void:
	if _track.size() < 2:
		return

	# Split into stretches first, and only then draw. A strip needs at least two
	# points to be anything at all, and a single point left on its own the far
	# side of a jump would otherwise open a surface that cannot be drawn.
	var start := 0
	for i in range(1, _track.size() + 1):
		var broken := i == _track.size()
		if not broken:
			broken = _track[i]["at"].distance_to(_track[i - 1]["at"]) > mark_spacing * 3.0

		if not broken:
			continue

		if i - start >= 2:
			_draw_stretch(start, i)
		start = i


## One unbroken stretch of track, as a ribbon threaded through its points.
func _draw_stretch(from: int, to: int) -> void:
	var half := track_width * 0.5

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _track_material)

	for i in range(from, to):
		var point := _track[i]
		var at: Vector3 = point["at"] + point["up"] * lift
		var side: Vector3 = point["side"] * half
		var faded := _left_of(point["age"], track_life) * float(point["weight"])

		# Drawn to nothing at either end of a stretch, so the track has no cut
		# ends -- the newest one is under the ball, and the oldest is on its way
		# out anyway.
		if i == from or i == to - 1:
			faded *= 0.25

		# The strip runs up one edge and down the other; the shader reads how far
		# across the track it is from the V of these.
		# How far down the track this is, so the marble's picture is laid along
		# the ground at a fixed size rather than stretched over whatever points
		# happen to be there.
		var along := float(point["rolled"]) / maxf(skin_repeat, 0.01)

		_mesh.surface_set_color(Color(1.0, 1.0, 1.0, faded))
		_mesh.surface_set_uv(Vector2(along, 0.0))
		_mesh.surface_add_vertex(at - side)

		_mesh.surface_set_color(Color(1.0, 1.0, 1.0, faded))
		_mesh.surface_set_uv(Vector2(along, 1.0))
		_mesh.surface_add_vertex(at + side)

	_mesh.surface_end()


## The craters, as one quad each, lying flat on the ground they were dug into.
func _draw_craters() -> void:
	if _craters.is_empty():
		return

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _crater_material)

	for crater in _craters:
		var at: Vector3 = crater["at"] + crater["up"] * lift
		var radius: float = crater["radius"]
		var side: Vector3 = crater["side"] * radius
		var ahead: Vector3 = crater["side"].cross(crater["up"]).normalized() * radius
		var faded := _left_of(crater["age"], crater_life)
		var tint := Color(1.0, 1.0, 1.0, faded)

		var corners := [
			at - side - ahead, at + side - ahead, at + side + ahead, at - side + ahead]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]

		for triangle in [[0, 1, 2], [0, 2, 3]]:
			for corner: int in triangle:
				_mesh.surface_set_color(tint)
				_mesh.surface_set_uv(uvs[corner])
				_mesh.surface_add_vertex(corners[corner])

	_mesh.surface_end()


## The surface a blow landed on, looked for from a little outside it and aimed
## back into it. Comes back empty where there is nothing to dig into -- a blow
## taken from something that is not the stage.
func _surface_at(point: Vector3, up: Vector3) -> Dictionary:
	var reach := _radius * 0.8
	var query := PhysicsRayQueryParameters3D.create(point + up * reach, point - up * reach)
	query.collision_mask = floor_layers
	query.exclude = [_ball.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


## Where the floor is under the ball, or nothing if it is off the ground.
func _ground_under() -> Dictionary:
	var from := _ball.global_position
	var query := PhysicsRayQueryParameters3D.create(
			from, from + Vector3.DOWN * (_radius + floor_reach))
	query.collision_mask = floor_layers
	query.exclude = [_ball.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


## The hardest of the contacts the ball is currently in, or nothing when it is
## touching nothing. Read off the physics server rather than through a signal,
## because this needs to know how hard and where, not merely that something was
## touched. Only the hardest counts: a ball landing in a corner reports two or
## three at once and they are all the same landing.
func _hardest_contact() -> Dictionary:
	var state := PhysicsServer3D.body_get_direct_state(_ball.get_rid())
	if state == null:
		return {}

	var hardest := {}
	var worst := 0.0
	for i in state.get_contact_count():
		var impulse := state.get_contact_impulse(i).length()
		if impulse <= worst:
			continue
		worst = impulse
		hardest = {
			"impulse": impulse,
			"point": state.get_contact_local_position(i),
			"normal": state.get_contact_local_normal(i),
		}
	return hardest


## The contact normal, turned to point out of the surface towards the ball.
## Which side of a contact the reported normal faces depends on which body the
## state belongs to, and a crater dug into the back of the floor is one nobody
## sees.
func _away_from_surface(point: Vector3, normal: Vector3) -> Vector3:
	var out := normal.normalized()
	if out.length_squared() < 0.0001:
		return Vector3.UP
	return out if out.dot(_ball.global_position - point) >= 0.0 else -out


## How far the ball reaches, read off its own collider so a marble built at
## another size still marks the floor and not the air.
func _measure_ball() -> float:
	for child in _ball.get_children():
		var collider := child as CollisionShape3D
		if collider == null:
			continue
		var sphere := collider.shape as SphereShape3D
		if sphere != null:
			return sphere.radius * collider.global_transform.basis.get_scale().y
	return 0.5
