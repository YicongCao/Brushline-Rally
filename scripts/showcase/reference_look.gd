class_name RallyReferenceLook
extends RefCounted

# All of these materials, meshes and lights belong to the film's isolated world.
static func apply(scene: Node3D,look: String) -> void:
	var presentation: RallyStagePresentation=scene.presentation
	var route: RallyStageRoute=scene.generator.route
	var environment := presentation.environment
	var sky: ShaderMaterial=environment.sky.sky_material
	var scenery := presentation.scenery
	var sun: DirectionalLight3D=scene.get_node("Sun")
	presentation.checkpoints.root.hide()
	for balloon: Dictionary in presentation.sky_life.balloons: balloon.node.hide()
	# The painted sky and short gates are built just for this cut.
	var sky_mode := 1 if look=="day" else (3 if look=="night" else 2)
	sky.set_shader_parameter("film_sky",sky_mode)
	var direction := Vector3(-.45,.64,-.62).normalized()
	var palette := ["e8f3e2","a6d3eb","73a8e0","fff9e9","bfcfdf"]
	var ground := ["647858","9d9c74"]
	var ambient := Color("c0d9f2")
	var ambient_energy := .55
	var fog := Color("c7d6df")
	var sun_color := Color("fff5df")
	var sun_energy := 1.48
	var disc := 0.0
	var station := 0.0
	var altitude := 0.0
	var azimuth := 0.0
	match look:
		"burned":
			palette=["ffd072","f38835","e95a20","ffe497","be4724"]
			ground=["4d4742","75645a"]
			ambient=Color("a7a1b1")
			ambient_energy=.36
			fog=Color("a07c70")
			sun_color=Color("ffbe78")
			sun_energy=1.16
			station=2890; altitude=5; azimuth=13; disc=.028
			_burn_trees(presentation.scenery)
		"sunset":
			palette=["ffe0a2","f1a282","e2766d","ffe0a8","cd7267"]
			ground=["536d52","868566"]
			ambient=Color("a2b7de")
			ambient_energy=.46
			fog=Color("d5a99e")
			sun_color=Color("ffdbab")
			sun_energy=1.38
			station=1000; altitude=5.5; azimuth=-8; disc=.033
		"night":
			palette=["202f5c","152144","070d25","718fc7","17264f"]
			ground=["28385c","455578"]
			ambient=Color("7182bc")
			ambient_energy=.27
			fog=Color("38477d")
			sun_color=Color("969bdf")
			sun_energy=.18
			station=2575; altitude=18; azimuth=-4; disc=.017
			sun.shadow_enabled=false
			sky.set_shader_parameter("film_moon",true)
			environment.fog_height_density=0
			environment.reflected_light_source=Environment.REFLECTION_SOURCE_DISABLED
			for lamp: Node in scene.vehicle.get_children():
				if lamp is SpotLight3D:
					lamp.light_energy=7.1
					lamp.spot_angle=25
					lamp.spot_range=87
	if station>0:
		var heading := route.position_at(station+30)-route.position_at(station-30)
		heading.y=0
		var a := deg_to_rad(altitude)
		direction=heading.normalized().rotated(Vector3.UP,deg_to_rad(azimuth))*cos(a)+Vector3.UP*sin(a)
	presentation.atmosphere.sun_direction=direction
	sun.basis=Basis.looking_at(-direction,Vector3.UP)
	sun.light_color=sun_color
	sun.light_energy=sun_energy
	environment.ambient_light_color=ambient
	environment.ambient_light_energy=ambient_energy
	environment.fog_light_color=fog
	environment.fog_light_energy=.44 if look=="night" else .70
	environment.fog_density=.00052 if look=="night" else .00038
	sky.set_shader_parameter("sun_direction",direction)
	sky.set_shader_parameter("film_disc",disc)
	var keys := ["horizon_sun","horizon_away","zenith_color","cloud_light","cloud_shadow"]
	for i: int in range(keys.size()): sky.set_shader_parameter(keys[i],Color(palette[i]))
	var terrain: ShaderMaterial=scenery.dressing.get_node("StageTerrain").material_override
	var road: ShaderMaterial=scene.generator.road_visuals[0].material_override
	for material: ShaderMaterial in [terrain,road]:
		material.set_shader_parameter("grass_dark",Color(ground[0]))
		material.set_shader_parameter("grass_light",Color(ground[1]))
	if look=="night": road.set_shader_parameter("film_wetness",.67)
	if look=="sunset": road.set_shader_parameter("film_asphalt",Color("646773"))
	_dress_land(scenery,look,direction)
	_add_roadside(scenery,look)

static func paint_actor(body: Node,look: String) -> void:
	var color: Color={"day":Color("375970"),"burned":Color("2d4051"),"sunset":Color("c1372b"),"night":Color("242b3a")}[look]
	var colored := {}
	for item: MeshInstance3D in body.find_children("*","MeshInstance3D",true,false):
		if item.mesh==null or str(item.name).begins_with("BrakeLamp"): continue
		for index: int in range(item.mesh.get_surface_count()):
			var original := item.mesh.surface_get_material(index)
			var shader := item.get_surface_override_material(index) as ShaderMaterial
			if original==null or shader==null or original.resource_name.to_lower() not in ["white","sun","blue","cyan","scarlet","teal","red"]: continue
			var key := shader.get_instance_id()
			if not colored.has(key):
				colored[key]=shader.duplicate()
				colored[key].set_shader_parameter("paint",color)
			item.set_surface_override_material(index,colored[key])

static func _dress_land(scenery: RallyStageScenery,look: String,direction: Vector3) -> void:
	var tint := {
		"grass": Color("8d9875") if look=="day" else (Color("696151") if look=="burned" else Color("647955")),
		"pine": Color("416e58"),"umbrella": Color("5b7757"),"shrub": Color("708162")}
	var materials := {}
	for kind: String in tint:
		var shader := RallySampleMeshes.foliage_material(kind=="grass" or kind=="shrub")
		shader.set_shader_parameter("film_tint",tint[kind])
		materials[kind]=shader
	for node: Node in scenery.dressing.get_children():
		var label := str(node.name)
		if look=="sunset" and (label=="PineStoneArch" or label.begins_with("RidgeOutcrop")):
			node.hide()
		elif node is MultiMeshInstance3D and not label.begins_with("shadow_") and look!="night":
			for kind: String in materials:
				if label.trim_prefix("far_").begins_with(kind) and (look!="burned" or kind=="grass"):
					node.material_override=materials[kind]
		elif node is MeshInstance3D and label.begins_with("MountainLayer"):
			var y: float=node.scale.y
			node.scale.y*=.40 if look!="night" else .55
			node.position.y+=scenery.center.y*(y-node.scale.y)
			var material: ShaderMaterial=node.material_override
			material.set_shader_parameter("sun_direction",direction)
			material.set_shader_parameter("shade_color",Color("22335b") if look=="night" else Color("657577"))
			material.set_shader_parameter("lit_color",Color("354368") if look=="night" else Color("a7ac91"))

static func _burn_trees(scenery: RallyStageScenery) -> void:
	var meshes: Array[Mesh]=[]
	for i: int in range(3):
		var tree := RallySampleMeshes.new()
		var tip := Vector3(.3+i*.14,7.2+i*.5,.25)
		var wood := Color("342821").lightened(i*.032)
		tree.beam(Vector3.ZERO,Vector3(.12,4.6,0),.29,wood)
		tree.beam(Vector3(.12,4.6,0),tip,.17,wood)
		for j: int in range(4):
			var a := Vector3(.12,2.0+j*1.23,.06)
			var away := Vector3(cos(i*2+j*2.4),0,sin(i*2+j*2.4))
			var elbow := a+away*(1.17-j*.13)+Vector3.UP*.71
			tree.beam(a,elbow,.125-j*.018,wood)
			tree.beam(elbow,elbow+away*.46+Vector3.UP*(1.1-j*.10),.066,wood)
		meshes.append(tree.finish())
	for node: Node in scenery.dressing.get_children():
		if node is not MultiMeshInstance3D: continue
		var label := str(node.name)
		var type := label.trim_prefix("far_").trim_prefix("shadow_")
		if type.begins_with("pine") or type.begins_with("umbrella"):
			node.multimesh.mesh=meshes[int(type.get_slice("_",0).right(1))]
		elif label.begins_with("shrub"):
			node.hide()
	# Stock scenery leaves the finish approach clear for spectators. The edit
	# uses that road geometry as a forest, so fill the gap with batched snags.
	var rng := RandomNumberGenerator.new()
	rng.seed=942813
	for section: int in range(2740,3050,62):
		for model: int in range(meshes.size()):
			var transforms: Array[Transform3D]=[]
			var origin := scenery.route.position_at(section+31)
			for i: int in range(44):
				var s := minf(section+rng.randf_range(0,62),scenery.route.length-1)
				var side := -1.0 if i%2==0 else 1.0
				var lateral := side*(5.6+pow(rng.randf(),1.6)*115)
				var at := scenery.ground_at(s,lateral)
				if scenery.nearest(at).distance<5.5: continue
				var scale_factor := rng.randf_range(.65,1.34)
				transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale_factor),at-origin))
			var batch := MultiMesh.new()
			batch.transform_format=MultiMesh.TRANSFORM_3D
			batch.mesh=meshes[model]
			batch.instance_count=transforms.size()
			for i: int in range(transforms.size()): batch.set_instance_transform(i,transforms[i])
			var tree_line := MultiMeshInstance3D.new()
			tree_line.name="ReferenceSnags"
			tree_line.position=origin
			tree_line.multimesh=batch
			tree_line.visibility_range_end=245.0
			tree_line.visibility_range_end_margin=18.0
			tree_line.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			scenery.dressing.add_child(tree_line)

static func _add_roadside(scenery: RallyStageScenery,look: String) -> void:
	var route := scenery.route
	var dress := RallySampleMeshes.new()
	var start := 350 if look=="day" else (2720 if look=="burned" else (2370 if look=="night" else 600))
	var end := 670 if look=="day" else (3010 if look=="burned" else (2760 if look=="night" else 1660))
	if look=="sunset":
		for s: int in range(start,end,12):
			for offset: int in [0,2]:
				var a := scenery.ground_at(s+offset,-.075)+Vector3.UP*.024
				var b := scenery.ground_at(s+offset,.075)+Vector3.UP*.024
				var c := scenery.ground_at(s+offset+2,-.075)+Vector3.UP*.024
				var d := scenery.ground_at(s+offset+2,.075)+Vector3.UP*.024
				dress.triangle(a,b,c,Color("e2dac6"))
				dress.triangle(b,d,c,Color("e2dac6"))
	if look!="night":
		var step := 3 if look=="burned" else 6
		for s: int in range(start,end,step):
			for side: float in [-1,1]:
				var a := scenery.ground_at(s,side*(route.width_at(s)*.5+1.05))
				var b := scenery.ground_at(s+step,side*(route.width_at(s+step)*.5+1.05))
				var rotation := Basis.looking_at((b-a).normalized()).get_euler()
				if look=="burned":
					var stone := Color("64584d").lightened(.11*absf(sin(s*3.37)))
					dress.box(Vector3(.52,.62,a.distance_to(b)-.045),(a+b)*.5+Vector3.UP*.24,stone,rotation)
					dress.box(Vector3(.58,.11,a.distance_to(b)-.02),(a+b)*.5+Vector3.UP*.59,stone.lightened(.12),rotation)
				else:
					var wood := Color("a17852")
					dress.box(Vector3(.19,.91,.19),a+Vector3.UP*.40,wood.darkened(.14))
					for height: float in [.31,.66]:
						dress.box(Vector3(.12,.13,a.distance_to(b)),(a+b)*.5+Vector3.UP*height,wood,rotation)
	var signs := [420,500] if look=="day" else ([2790,2860,2920] if look=="burned" else ([2515,2592,2675] if look=="night" else []))
	for s: int in signs: _chevron(dress,scenery,s)
	var gates := [2790,2920] if look=="burned" else ([780,1220] if look=="sunset" else ([2630] if look=="night" else []))
	for s: int in gates:
		var a := scenery.ground_at(s,-route.width_at(s)*.5-.70)
		var b := scenery.ground_at(s,route.width_at(s)*.5+.70)
		var rotation := Basis.looking_at((b-a).normalized()).get_euler()
		for p: Vector3 in [a,b]: dress.box(Vector3(.13,3.7,.13),p+Vector3.UP*1.80,Color("d5ceba"))
		dress.box(Vector3(.18,.34,a.distance_to(b)),(a+b)*.5+Vector3.UP*3.58,Color("e2d5ae"),rotation)
	var road_props := MeshInstance3D.new()
	road_props.name="ReferenceRoadside"
	road_props.mesh=dress.finish()
	scenery.dressing.add_child(road_props)

static func _chevron(mesh: RallySampleMeshes,scenery: RallyStageScenery,s: float) -> void:
	var route := scenery.route
	var pose := route.pose_at(s,0)
	var bend := route.tangent_at(s-14).signed_angle_to(route.tangent_at(s+25),Vector3.UP)
	var arrow := -1.0 if bend>0 else 1.0
	var at := scenery.ground_at(s,-arrow*(route.width_at(s)*.5+1.35))
	var basis := pose.basis
	mesh.box(Vector3(.07,1.45,.07),at+Vector3.UP*.62,Color("bdb9a6"))
	mesh.box(Vector3(.98,.63,.07),at+Vector3.UP*1.36,Color("f4c047"),basis.get_euler())
	var face := Transform3D(basis,at+Vector3.UP*1.36+basis.z*.038)
	var path := [Vector2(-.29,.22),Vector2(-.04,.22),Vector2(.31,0),Vector2(-.04,-.22),Vector2(-.29,-.22),Vector2(.05,0)]
	for tri: Array in [[0,1,5],[1,2,5],[5,2,3],[5,3,4]]:
		var points: Array[Vector3]=[]
		for i: int in tri: points.append(face*Vector3(path[i].x*arrow,path[i].y,0))
		mesh.triangle(points[0],points[1],points[2],Color("2b251d"))
