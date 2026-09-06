class_name SliceWorld
extends Node3D
## Three small authored locations built from original Blender modules.

const PRISM_POINTS: Array[Vector3] = [Vector3(-5, 0, 4), Vector3(-5, 0, -3), Vector3(5, 0, -3)]
const SOLUTION: Array[int] = [0, 1, 0]
const MINT := Color(0.22, 1.0, 0.76)
const AMBER := Color(1.0, 0.55, 0.2)
@export var scene_id := "forest"
var spawn_position := Vector3(0, 0.15, 16)
var interactables: Dictionary = {}
var prism_models: Array[Node3D] = []
var beams: Node3D
var gate: StaticBody3D
var gate_visual: Node3D
var robot_position := Vector3(0, 0.1, -21)
var navigation: NavigationRegion3D
var portal_surface: MeshInstance3D
var artifact_model: Node3D
var crystal_model: Node3D
var shard_model: Node3D
var elapsed := 0.0
var models: Dictionary = {}
var basalt_material: StandardMaterial3D

func _ready() -> void:
	if not has_meta("build_by_main"):
		build(scene_id,GameSession.new())

func build(id: String, session: GameSession) -> void:
	scene_id = id
	name = "World_" + id
	_environment()
	beams = Node3D.new()
	beams.name = "OpticalBeams"
	add_child(beams)
	match id:
		"forest": _forest()
		"ruins": _ruins()
		"hub": _hub()
	apply_state(session)
	_build_navigation()

func model(asset: String, at: Vector3, size := Vector3.ONE, angle := 0.0) -> Node3D:
	var path := "res://assets/models/" + asset + ".glb"
	if not models.has(asset):
		models[asset] = load(path)
	var obj: Node3D = models[asset].instantiate()
	obj.name = asset
	obj.position = at
	obj.scale = size
	obj.rotation.y = angle
	if scene_id=="forest" and asset=="tile":
		if basalt_material==null:
			basalt_material=StandardMaterial3D.new()
			basalt_material.albedo_color=Color("233b40")
			basalt_material.roughness=0.84
		for mesh in obj.find_children("*", "MeshInstance3D", true, false):
			if "Architectural" in mesh.name: mesh.material_override=basalt_material
	add_child(obj)
	return obj

func solid_box(at: Vector3, size: Vector3, parent: Node = self) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	return body

func _floor(at: Vector3, width: int, length: int) -> void:
	# Tile tops and the single matching collider both lie at y=0.
	solid_box(at + Vector3(0, -0.20, 0), Vector3(width * 2, 0.4, length * 2))
	for x in range(width):
		for z in range(length):
			model("tile", at + Vector3((x - (width - 1) * 0.5) * 2, 0.005, (z - (length - 1) * 0.5) * 2))

func _tree(at: Vector3, size: float) -> void:
	model("crystal_tree", at, Vector3.ONE * size, at.x)
	var body := StaticBody3D.new()
	body.position = at + Vector3(0, size * 1.9, 0)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.72 * size
	shape.height = size * 3.8
	col.shape = shape
	body.add_child(col)
	add_child(body)

func _label(text: String, at: Vector3, color := MINT, size := 34) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = size
	label.pixel_size = 0.009
	label.modulate = color
	label.outline_size = 5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	add_child(label)
	return label

func _interactive(id: String, obj: Node3D, offset := Vector3(0, 1, 0)) -> void:
	interactables[id] = {"node": obj, "offset": offset}

func _forest() -> void:
	spawn_position = Vector3(0, 0.12, 15)
	model("island", Vector3(0, -0.23, -13), Vector3(20, 4, 40))
	_floor(Vector3(0, 0, -13), 11, 31)
	# A spacious landing, a readable optical court, a sealed encounter, a quiet reward.
	model("ship", Vector3(-5.6, 0, 14), Vector3.ONE * 1.25, -0.35)
	solid_box(Vector3(-5.6, 1, 14), Vector3(6.0, 2, 6.0))
	for spec in [Vector3(-10,0,8), Vector3(10,0,12), Vector3(9,0,2), Vector3(-10,0,-8), Vector3(10,0,-12), Vector3(-9,0,-26), Vector3(9,0,-31), Vector3(-8,0,-39)]:
		_tree(spec, 1.0 + absf(spec.z) * 0.022)
	for i in range(22):
		var side := -1.0 if i % 2 else 1.0
		model("crystal_tree", Vector3(side * (13.0 + (i%3)), -0.2, 19.0 - i*2.9), Vector3.ONE * (1.3 + (i%4)*0.4), i)
	for i in range(3):
		var prism := model("prism", PRISM_POINTS[i])
		prism_models.append(prism)
		_interactive("prism_" + str(i), prism)
		_label(["I", "II", "III"][i], PRISM_POINTS[i] + Vector3(0,2.45,0))
	var source := model("receiver", Vector3(-9, 0, 4), Vector3.ONE, PI/2)
	_label("◎", source.position + Vector3(0,2.1,0))
	model("receiver", Vector3(5, 0, -10))
	var reset_console := model("pedestal", Vector3(0, 0, 7))
	_interactive("reset", reset_console)
	_label("↺", reset_console.position + Vector3(0,1.4,0), AMBER)
	# Walls span the entire floor: walking around the encounter gate cannot bypass it.
	gate = solid_box(Vector3(0, 2, -14), Vector3(5.2,4,0.7))
	gate.name = "ArenaGate"
	gate_visual = Node3D.new()
	gate_visual.position = gate.position
	add_child(gate_visual)
	for x in range(-2,3):
		var column := model("column", Vector3(x,0,-14))
		reparent_keep(column, gate_visual)
	for side in [-1,1]:
		solid_box(Vector3(side*7.85,2,-14),Vector3(10.5,4,0.8))
		for x in range(3,12):
			model("column",Vector3(x*side,0,-14),Vector3(1,1.0,1))
	# An obstacle forces the guardian to use navigation instead of direct translation.
	model("column", Vector3(2.7,0,-21),Vector3(1.5,0.7,1.5))
	solid_box(Vector3(2.7,1.4,-21),Vector3(1.5,2.8,1.5))
	model("pedestal", Vector3(0,0,-29))
	artifact_model = model("artifact",Vector3(0,1.2,-29),Vector3.ONE*1.25)
	_interactive("artifact",artifact_model,Vector3.ZERO)
	var lock := model("receiver",Vector3(0,0,-34))
	_interactive("lock",lock,Vector3(0,1.35,0))
	_label("◎",Vector3(0,2.0,-34))
	model("pedestal",Vector3(0,0,-38))
	crystal_model = model("crystal",Vector3(0,1.15,-38))
	_interactive("crystal",crystal_model,Vector3.ZERO)
	var portal := model("portal",Vector3(0,0,-42))
	_interactive("portal",portal,Vector3(0,1.4,0))
	portal_surface = _portal_disk(Vector3(0,2.05,-42),1.58)
	shard_model = model("crystal",Vector3(8,0.8,17),Vector3.ONE*0.38)
	_interactive("shard",shard_model,Vector3.ZERO)
	# A subtle continuous route guide, interrupted at each activity.
	for z in range(14,-42,-3):
		if z > 8 or z < -15:
			beam(Vector3(0,0.025,z),Vector3(0,0.025,z-0.7),0.017,MINT*0.5,self)

func reparent_keep(obj: Node3D, parent: Node3D) -> void:
	var original := obj.transform
	remove_child(obj)
	parent.add_child(obj)
	obj.transform = parent.transform.affine_inverse() * original

func _ruins() -> void:
	spawn_position = Vector3(0,0.12,8)
	model("island",Vector3(0,-0.3,-5),Vector3(13,5,19))
	_floor(Vector3(0,0,-4),9,14)
	for x in [-6,6]:
		for z in range(4,-15,-6):
			model("column",Vector3(x,0,z),Vector3(1.2,1.5,1.2))
	model("armillary",Vector3(0,0,-10),Vector3.ONE*1.3)
	solid_box(Vector3(0,1.5,-10),Vector3(3,3,3))
	for i in range(8):
		model("island",Vector3(-20+i*6,-6-i*1.8,-30-i*7),Vector3(3,3,5))
	var portal := model("portal",Vector3(0,0,12),Vector3.ONE,PI)
	_interactive("return_hub",portal,Vector3(0,1.4,0))
	_portal_disk(Vector3(0,2.05,12),1.58)
	_label("II",Vector3(0,4,-10),AMBER,64)

func _hub() -> void:
	spawn_position = Vector3(0,0.12,7)
	model("island",Vector3(0,-0.3,0),Vector3(12,2,12))
	_floor(Vector3.ZERO,9,9)
	model("armillary",Vector3(0,0,-2))
	solid_box(Vector3(0,1.5,-2),Vector3(3,3,3))
	for x in [-6,6]:
		var portal := model("portal",Vector3(x,0,-5))
		_interactive("hub_forest" if x<0 else "hub_ruins",portal,Vector3(0,1.4,0))
		_portal_disk(Vector3(x,2.05,-5),1.58)
		_label("I" if x<0 else "II",Vector3(x,4.6,-5),MINT,56)
	for i in range(12):
		var a := float(i) / 12.0 * TAU
		model("column",Vector3(sin(a)*10,0,cos(a)*10),Vector3(.55,.35,.55))

func _portal_disk(at: Vector3, radius: float) -> MeshInstance3D:
	# Camera-only collision keeps the spring arm in front of the portal plane.
	# Interaction rays and the explorer do not collide with this surface.
	var camera_blocker:=solid_box(at,Vector3(radius*2,radius*2,0.25))
	camera_blocker.collision_layer=8
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(radius*2,radius*2)
	mesh.mesh = quad
	mesh.position = at
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/portal.gdshader")
	mesh.material_override = mat
	add_child(mesh)
	return mesh

func _environment() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("030b16")
	sky_mat.sky_horizon_color = Color("174442") if scene_id=="forest" else Color("252f48")
	sky_mat.ground_bottom_color = Color("030911")
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.sky_curve = 0.22
	sky_mat.sun_angle_max = 1.2
	sky.sky_material = sky_mat
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8cb7bd") if scene_id=="forest" else Color("d6c5a3")
	environment.ambient_light_energy = 0.38
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.65
	environment.glow_bloom = 0.08
	environment.fog_enabled = true
	environment.fog_light_color = Color("163635") if scene_id=="forest" else Color("242d44")
	environment.fog_density = 0.004
	env.environment = environment
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-32,0)
	sun.light_color = Color("d3fff1") if scene_id=="forest" else Color("ffe2a2")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90
	sun.light_angular_distance = 1.0
	add_child(sun)
	# Distant stars are inexpensive emissive quads with no collision or lights.
	var rng := RandomNumberGenerator.new()
	rng.seed = 729
	var star_material := StandardMaterial3D.new()
	star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_material.albedo_color = Color(0.48,0.69,0.78)
	star_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	for i in range(110):
		var star := MeshInstance3D.new()
		var point := QuadMesh.new()
		point.size = Vector2.ONE * rng.randf_range(0.05,0.23)
		star.mesh = point
		star.position = Vector3(rng.randf_range(-130,130),rng.randf_range(12,95),rng.randf_range(-150,70))
		star.material_override = star_material
		add_child(star)

func _build_navigation() -> void:
	if scene_id != "forest": return
	navigation = NavigationRegion3D.new()
	navigation.name = "ArenaNavigation"
	var navmesh := NavigationMesh.new()
	# Explicit walkable polygon around the pillar; no render-mesh bake stalls.
	# Area is behind the gate, and only the robot navigates here.
	navmesh.vertices = PackedVector3Array([
		Vector3(-10,0,-15),Vector3(10,0,-15),Vector3(10,0,-28),Vector3(-10,0,-28),
		Vector3(1.3,0,-19.6),Vector3(4.1,0,-19.6),Vector3(4.1,0,-22.4),Vector3(1.3,0,-22.4)])
	for polygon in [PackedInt32Array([0,1,5,4]),PackedInt32Array([1,2,6,5]),PackedInt32Array([2,3,7,6]),PackedInt32Array([3,0,4,7])]:
		navmesh.add_polygon(polygon)
	navigation.navigation_mesh = navmesh
	add_child(navigation)

func beam(from: Vector3, to: Vector3, radius: float, color: Color, parent: Node) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = from.distance_to(to)
	cylinder.radial_segments = 8
	mesh.mesh = cylinder
	mesh.position = (from+to)*0.5
	var up := (to-from).normalized()
	var right := up.cross(Vector3.FORWARD)
	if right.length_squared()<0.01: right=up.cross(Vector3.RIGHT)
	right=right.normalized()
	mesh.basis = Basis(right,up,right.cross(up).normalized())
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	return mesh

func apply_state(session: GameSession) -> void:
	if scene_id != "forest": return
	gate.collision_layer = 0 if session.puzzle_solved else 1
	gate_visual.visible = not session.puzzle_solved
	artifact_model.visible = session.robot_defeated and not session.artifact_collected
	crystal_model.visible = session.lock_open and not session.crystal_collected
	shard_model.visible = not session.memory_shards.has(GameSession.MEMORY_SHARD_ID)
	portal_surface.visible = session.crystal_collected
	for child in beams.get_children():
		beams.remove_child(child)
		child.queue_free()
	var start := Vector3(-9,1.25,4)
	beam(start,PRISM_POINTS[0]+Vector3.UP*1.25,0.034,MINT,beams)
	var active := true
	for i in range(3):
		var orientation: int = session.prism_orientations[i]
		prism_models[i].rotation.y = -orientation*PI/2
		if not active: continue
		var point := PRISM_POINTS[i]+Vector3.UP*1.25
		var correct: bool = orientation==SOLUTION[i]
		var target: Vector3
		if correct:
			target = (PRISM_POINTS[i+1] if i<2 else Vector3(5,0,-10))+Vector3.UP*1.25
		else:
			var dirs: Array[Vector3] = [Vector3.FORWARD,Vector3.RIGHT,Vector3.BACK,Vector3.LEFT]
			target=point+dirs[orientation]*3.5
		beam(point,target,0.034,MINT if correct else AMBER,beams)
		active=correct

func _process(delta: float) -> void:
	elapsed += delta
	if is_instance_valid(artifact_model):
		artifact_model.position.y = 1.2+sin(elapsed*1.6)*.12
		artifact_model.rotation.y = elapsed*.45
	if is_instance_valid(crystal_model):
		crystal_model.position.y = 1.15+sin(elapsed*1.8)*.15
		crystal_model.rotation.y = elapsed*.35

func interaction_position(id: String) -> Vector3:
	var entry: Dictionary=interactables[id]
	return entry.node.global_position+entry.offset
