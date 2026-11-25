class_name RallyStageScenery
extends Node3D

var route: RallyStageRoute
var generator: RallyStageGenerator
var center := Vector3.ZERO
var dressing := Node3D.new()
var foliage := RallySampleDressing.new()
var terrain_noise := FastNoiseLite.new()
var lookup: Dictionary = {}
var obstacles: Array[StaticBody3D] = []
var spectator_zones: Array[Vector3] = []
var spectator_regions: Array[Dictionary] = []
var grass_batches: Array[MultiMeshInstance3D] = []
var all_batches: Array[MultiMeshInstance3D] = []
var gravel_batches: int = 0
var bounds := AABB()
var sailboats: Array[Dictionary] = []
var river_frames: Array[Dictionary] = []
var utility_line := RallyUtilityLine.new()
var terrain_start := Vector2.ZERO
var terrain_count := Vector2i.ZERO
var terrain_vertices := PackedVector3Array()
var terrain_cell_size := 8.0
var log_piles: Array[Node3D] = []
var dust_devils: Array[MeshInstance3D] = []


func build(stage: RallyStageGenerator) -> void:
	generator = stage
	route = stage.route
	center = route.position_at(route.length*0.5)
	dressing.name = "StageDressing"
	add_child(dressing)
	terrain_noise.seed = 593
	terrain_noise.frequency = 0.006
	terrain_noise.fractal_octaves = 4
	bounds = AABB(route.points[0],Vector3.ZERO)
	for i: int in range(0,route.points.size()-1,8):
		bounds = bounds.expand(route.points[i])
	for river: Vector3 in generator.definition.river_crossings:
		var pose := route.pose_at(river.x,0)
		river_frames.append({"origin":pose.origin,"right":pose.basis.x,"forward":-pose.basis.z,"span":river.y})
	_apply_materials()
	_build_terrain()
	var desert := generator.definition.environment_id=="desert"
	if desert and route.length<1000:
		# Short desert samples (garage test track, R200 sample) keep their light dressing.
		RallyRedrockScenery.build(self)
		_build_guardrails()
		return
	if not desert:
		_build_mountains()
		_build_highland_edges()
		utility_line.plan(self)
	foliage.biome = generator.definition.environment_id
	foliage.spectator_stations.assign(generator.definition.spectators)
	foliage.build_range(self,12,route.length-35,0.58)
	for station: float in foliage.spectator_stations:
		spectator_zones.append(ground_at(station+5,8))
		spectator_regions.append({"a":ground_at(station-1,8),"b":ground_at(station+13,8)})
	if desert: RallyRedrockScenery.build(self)
	_build_landmarks()
	RallyStageLandmarks.build(self)
	RallyRiverBridges.build(self)
	if not desert: utility_line.build(self)
	RallyLogPiles.build(self)
	_build_obstacles()
	_build_guardrails()
	_build_gravel()
	for node: Node in dressing.get_children():
		if node is MultiMeshInstance3D:
			all_batches.append(node)
			if str(node.name).begins_with("grass"): grass_batches.append(node)
	for child: Node in generator.get_children():
		if child.get_meta("prototype_marker", false): child.visible = false


func _candidates_for_cell(cell: Vector2i) -> Array:
	if lookup.has(cell): return lookup[cell]
	var corner := Vector2(cell)*64.0
	var cell_center := corner+Vector2(32,32)
	var center_distance := INF
	for i: int in range(0,route.points.size()-1,8):
		var a := Vector2(route.points[i].x,route.points[i].z)
		var end := mini(i+8,route.points.size()-1)
		var b := Vector2(route.points[end].x,route.points[end].z)
		var t := clampf((cell_center-a).dot(b-a)/maxf(a.distance_squared_to(b),.001),0,1)
		center_distance=minf(center_distance,cell_center.distance_to(a.lerp(b,t)))
	# A segment nearest the cell centre is at most another half-diagonal away
	# from any point in the cell. Include every segment whose bounds could beat
	# that bound, plus the 24 m neighbor blend. Cache this conservative superset.
	# The old fixed 3x3 bucket query could drop the true closest segment as the
	# query crossed a cell boundary, creating >100 m terrain height jumps.
	var limit := pow(center_distance+sqrt(2.0)*32+24,2)
	var candidates: Array=[]
	for i: int in range(0,route.points.size()-1,8):
		var a := Vector2(route.points[i].x,route.points[i].z)
		var end := mini(i+8,route.points.size()-1)
		var b := Vector2(route.points[end].x,route.points[end].z)
		var gap := Vector2(maxf(maxf(corner.x-maxf(a.x,b.x),minf(a.x,b.x)-corner.x-64),0),maxf(maxf(corner.y-maxf(a.y,b.y),minf(a.y,b.y)-corner.y-64),0))
		if gap.length_squared()<=limit: candidates.append(i)
	lookup[cell]=candidates
	return candidates


func nearest(point: Vector3,include_neighbor: bool = false) -> Dictionary:
	var cell := Vector2i(floori(point.x/64),floori(point.z/64))
	var candidates := _candidates_for_cell(cell)
	var best := INF
	var result := {"s":0.0,"distance":INF,"lateral":0.0,"point":Vector3.ZERO}
	var samples: Array[Dictionary] = []
	var best_i := 0
	var best_t := 0.0
	var best_at := Vector3.ZERO
	for raw: Variant in candidates:
		var i := int(raw)
		var end := mini(i+8,route.points.size()-1)
		var a := route.points[i]
		var b := route.points[end]
		var delta := Vector2(b.x-a.x,b.z-a.z)
		var t := clampf(Vector2(point.x-a.x,point.z-a.z).dot(delta)/maxf(delta.length_squared(),0.001),0,1)
		var at := a.lerp(b,t)
		var distance := Vector2(point.x-at.x,point.z-at.z).length_squared()
		if include_neighbor:
			samples.append({"s":lerpf(route.distances[i],route.distances[end],t),"distance":sqrt(distance),"lateral":(point-at).dot(route.rights[i]),"point":at})
		if distance < best:
			best = distance
			best_i=i; best_t=t; best_at=at
	if best<INF:
		result={"s":lerpf(route.distances[best_i],route.distances[mini(best_i+8,route.points.size()-1)],best_t),"distance":sqrt(best),"lateral":(point-best_at).dot(route.rights[best_i]),"point":best_at}
	if include_neighbor:
		var neighbor: Dictionary = {}
		for sample: Dictionary in samples:
			if absf(float(sample.s)-float(result.s))<60: continue
			if neighbor.is_empty() or float(sample.distance)<float(neighbor.distance): neighbor=sample
		if not neighbor.is_empty(): result["neighbor"]=neighbor
	return result


func height_at(x: float,z: float) -> float:
	var alpine := generator.definition.environment_id=="highland" and not generator.definition.mountain_cliff_sections.is_empty()
	var p := nearest(Vector3(x,0,z),alpine)
	var height := _height_for_frame(p,x,z)
	if p.has("neighbor"):
		var neighbor: Dictionary=p.neighbor
		var half := route.width_at(p.s)*.5
		var blend := .5*(1-smoothstep(0,24,float(neighbor.distance)-float(p.distance)))*smoothstep(half+1.2,half+3.5,float(p.distance))
		# Neighboring switchbacks can demand opposite relief at the same point.
		# Blend their influence instead of creating a vertical Voronoi wall when
		# the nearest road branch changes. Keep the driving corridor protected.
		if blend>0: height=lerpf(height,_height_for_frame(neighbor,x,z),blend)
	return height


func _height_for_frame(p: Dictionary,x: float,z: float) -> float:
	var d: float = p.distance
	var half := route.width_at(p.s)*0.5
	var close: float = p.point.y-minf(maxf(d-half,0)*0.18,2.3)
	if generator.definition.environment_id=="desert":
		var dunes: float = p.point.y-4+sin(x*.018+sin(z*.008)*2)*10+sin(z*.027+x*.006)*6
		var hill := smoothstep(2900,3500,float(p.s))*-36.0*smoothstep(30,110,d)
		return lerpf(close, dunes+hill, smoothstep(22,90,d))

	close += smoothstep(1.5,10,d-half)*0.5*sin(float(p.s)*0.03+float(p.lateral)*0.2)
	var far: float = p.point.y-6+terrain_noise.get_noise_2d(x,z)*58+signf(p.lateral)*minf(d*0.14,27)
	if generator.definition.environment_id=="coast" and float(p.lateral)<0:
		far = lerpf(p.point.y-12,-40,smoothstep(25,180,d))
	var clearance := lerpf(2.5,.35,smoothstep(6,18,d))
	var height := lerpf(close-clearance,far,smoothstep(21,110,d))
	if generator.definition.environment_id=="highland":
		var mountain_side := generator.definition.mountain_side_at(float(p.s))
		var beyond_shoulder := maxf(0,d-half-3.5)
		var alpine_weight := absf(mountain_side)*smoothstep(half+1.5,half+3.5,d)*(1-smoothstep(58,118,d))
		if alpine_weight>0:
			# Apply alpine relief after the generic distant-terrain blend. Applying
			# it to `far` first attenuated it twice and left a broad flat roadside.
			var relief := 45*smoothstep(0,24,beyond_shoulder) if float(p.lateral)*mountain_side>0 else -96*smoothstep(0,28,beyond_shoulder)
			var rock_noise := terrain_noise.get_noise_2d(x*1.7,z*1.7)*4*smoothstep(0,10,beyond_shoulder)
			height = lerpf(height,close-.35+relief+rock_noise,alpine_weight)
	# Carve an actual sandy bay beneath the final overlook, so the beach props
	# cannot be buried by the generic cliff/noise terrain.
	if generator.definition.environment_id=="coast" and float(p.s)>route.length-160 and float(p.lateral)<-25:
		var bay := smoothstep(route.length-160,route.length-90,float(p.s))*smoothstep(25,38,-float(p.lateral))
		var beach_height := lerpf(-24.4,-40,smoothstep(85,130,-float(p.lateral)))
		height = lerpf(height,beach_height,bay)
	var end := route.points[-1]
	var forward := route.tangents[-1]
	forward.y = 0
	forward = forward.normalized()
	var beyond := Vector3(x-end.x,0,z-end.z).dot(forward)
	if generator.definition.environment_id=="coast" and beyond>110:
		height = lerpf(height,-40,smoothstep(110,230,beyond))
	if generator.definition.environment_id=="highland" and float(p.s)>route.length-200:
		var drop := smoothstep(route.length-200,route.length-80,float(p.s))*smoothstep(32,180,d)
		height = lerpf(height,p.point.y-130+terrain_noise.get_noise_2d(x,z)*35,drop)
	for river: Dictionary in river_frames:
		var origin: Vector3 = river.origin
		var delta := Vector3(x,origin.y,z)-origin
		var across := delta.dot(river.right)
		var along := delta.dot(river.forward)
		if absf(across)>125: continue
		var meander := sin(across*.04)*2+sin(across*.11)*.6
		var half_channel: float = river.span*.45+sin(across*.07)*1.2
		var channel := (1-smoothstep(half_channel,half_channel+7,absf(along-meander)))*(1-smoothstep(100,125,absf(across)))
		var bed := origin.y-4.1-across*.006
		height = lerpf(height,minf(height,bed),channel)
	return height


func ground_at(s: float,lateral: float) -> Vector3:
	var at := route.position_at(s)+route.rights[route.index_at(s)]*lateral
	var alpine := generator.definition.environment_id=="highland" and absf(generator.definition.mountain_side_at(s))>0.01
	var road_apron := route.width_at(s)*.5+3.5 if alpine else 21.0
	if absf(lateral) < road_apron: return generator.surface_position_at(s,lateral)
	at.y = rendered_height_at(at.x,at.z)
	return at


func allows_decoration(point: Vector3, kind: String, scale_factor: float) -> bool:
	if kind in ["pine","umbrella","rock"] and not utility_line.allows_tree(point): return false
	var p := nearest(point)
	# Vertical trunks on nearly vertical mesh faces still read as floating.
	# Keep forest on plantable slopes; leave cliff faces bare.
	var alpine := generator.definition.environment_id=="highland" and absf(generator.definition.mountain_side_at(float(p.s)))>0.01
	if kind in ["pine","umbrella"] and absf(float(p.lateral))>=(route.width_at(p.s)*.5+3.5 if alpine else 21.0) and terrain_slope_at(point)>(.78 if alpine else 1.15): return false
	if alpine and kind in ["grass","shrub"] and absf(float(p.lateral))>route.width_at(p.s)*.5+3.5 and terrain_slope_at(point)>.65: return false
	for station: float in generator.definition.log_pile_stations:
		if absf(float(p.s)-station)<10 and float(p.distance)<11: return false
	for river: Vector3 in generator.definition.river_crossings:
		if absf(float(p.s)-river.x)<river.y*.5+10 and absf(float(p.lateral))<125: return false
	if absf(float(p.s)-route.length*.51)<22 and float(p.lateral)>5 and float(p.lateral)<19: return false
	if float(p.s)>route.length-140 and kind in ["pine","umbrella","rock"]: return false
	if float(p.s)>route.length-75 and float(p.lateral)<-7 and float(p.lateral)>-100: return false
	if generator.definition.environment_id=="coast" and (point.y < -18 or (float(p.lateral)<-18 and kind in ["pine","umbrella"])): return false
	for note: Dictionary in generator.definition.hazard_notes:
		if note.code=="CUT" and absf(float(p.s)-float(note.s))<40 and float(p.distance)<route.width_at(p.s)*.5+1.2: return false
	for landmark: Dictionary in generator.definition.landmarks:
		if point.distance_to(ground_at(landmark.s,landmark.side*18))<12: return false
	var radius := 2.8*scale_factor if kind in ["pine","umbrella"] else (1.4*scale_factor if kind == "rock" else 0.25)
	if kind in ["pine","umbrella","rock"]:
		for station: float in foliage.spectator_stations:
			if point.distance_to(ground_at(station+5,8)) < 8+radius: return false
	return float(p.distance) > route.width_at(p.s)*0.5+radius+0.15


func _apply_materials() -> void:
	var ground := ShaderMaterial.new()
	ground.shader = preload("res://assets/shaders/stage_ground.gdshader")
	ground.set_shader_parameter("road_mesh",true)
	ground.set_shader_parameter("desert",generator.definition.environment_id=="desert")
	ground.set_shader_parameter("wear_strength",.48)
	ground.set_shader_parameter("wear_atlas",preload("res://assets/brushline/road-wear.png"))
	if not generator.definition.mountain_cliff_sections.is_empty():
		ground.set_shader_parameter("mountain_section_count",generator.definition.mountain_cliff_sections.size())
		ground.set_shader_parameter("mountain_sections",generator.definition.mountain_cliff_sections)
	_theme_ground(ground)
	for mesh: MeshInstance3D in generator.road_visuals: mesh.material_override = ground
	var water := ShaderMaterial.new()
	water.shader = preload("res://assets/shaders/stage_water.gdshader")
	for mesh: MeshInstance3D in generator.water_visuals: mesh.material_override = water


func _build_terrain() -> void:
	# The near-road alpine slopes need a finer grid to avoid interpolating a
	# tall mountainside through the road or floating foliage above a cliff.
	terrain_cell_size = 4.0 if generator.definition.environment_id=="highland" else 8.0
	var start := Vector2(bounds.position.x-400,bounds.position.z-400)
	var extent := Vector2(bounds.size.x+800,bounds.size.z+800)
	var count := Vector2i(ceili(extent.x/terrain_cell_size),ceili(extent.y/terrain_cell_size))
	var cache_key := RallyTerrainGeometryCache.key_for(generator.definition,route.points)
	var cached := RallyTerrainGeometryCache.fetch(cache_key)
	var vertices := PackedVector3Array()
	var chunks: Array[ArrayMesh]=[]
	if not cached.is_empty():
		vertices=cached.vertices
		chunks.assign(cached.meshes)
	else:
		vertices.resize((count.x+1)*(count.y+1))
		for z: int in range(count.y+1):
			for x: int in range(count.x+1):
				var px := start.x+x*terrain_cell_size
				var pz := start.y+z*terrain_cell_size
				vertices[z*(count.x+1)+x]=Vector3(px,height_at(px,pz),pz)
		# Preserve every original triangle and its flat normal. Splitting only
		# changes render bounds, letting the renderer reject off-screen terrain.
		for cz: int in range(0,count.y,48):
			for cx: int in range(0,count.x,48):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				for z: int in range(cz,mini(cz+48,count.y)):
					for x: int in range(cx,mini(cx+48,count.x)):
						var a := z*(count.x+1)+x
						var b := a+count.x+1
						for index: int in [a,a+1,b+1,a,b+1,b]: tool.add_vertex(vertices[index])
				tool.generate_normals()
				chunks.append(tool.commit())
		RallyTerrainGeometryCache.remember(cache_key,{"vertices":vertices,"meshes":chunks})
	terrain_start = start
	terrain_count = count
	terrain_vertices = vertices
	var mesh := MeshInstance3D.new()
	mesh.name = "StageTerrain"
	mesh.mesh = chunks[0]
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/stage_ground.gdshader")
	material.set_shader_parameter("alpine_terrain",generator.definition.environment_id=="highland")
	material.set_shader_parameter("desert",generator.definition.environment_id=="desert")
	_theme_ground(material)
	mesh.material_override = material
	dressing.add_child(mesh)
	for i: int in range(1,chunks.size()):
		var chunk := MeshInstance3D.new()
		chunk.name="TerrainChunk%d"%i
		chunk.mesh=chunks[i]
		chunk.material_override=material
		chunk.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.add_child(chunk)

	if generator.definition.environment_id=="highland":
		# Use the very same visible terrain triangles, never a hidden flat apron.
		var faces := PackedVector3Array()
		for z: int in range(count.y):
			for x: int in range(count.x):
				var a := z*(count.x+1)+x
				var b := a+count.x+1
				var center_at: Vector3=(vertices[a]+vertices[b+1])*.5
				var near := nearest(center_at)
				if float(near.distance)>85: continue
				# Keep complete visible triangles below the road too. Dropping a triangle
				# because ONE corner touched the shoulder left 4 m holes beside the road.
				for index: int in [a,a+1,b+1,a,b+1,b]: faces.append(vertices[index])
		var body := StaticBody3D.new()
		body.name="AlpineTerrainCollision"
		body.collision_layer=1
		body.collision_mask=2
		body.set_meta("surface_id",3)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var collider := CollisionShape3D.new()
		collider.shape=shape
		body.add_child(collider)
		dressing.add_child(body)
		_build_mountain_shoulders()
	else:
		_build_runoff_collision(vertices,count)


func _build_runoff_collision(vertices: PackedVector3Array,count: Vector2i) -> void:
	# The road mesh only collides out to 22 m. Beyond that the visible terrain had
	# no collider, so a car that ran wide fell through, lost ground contact and
	# slid away unbraked. Collide with the same visible triangles out to the
	# recovery boundary, starting slightly inside the road apron edge so there
	# is no gap. The road chunks stay on top inside 22 m and keep their surface.
	var faces := PackedVector3Array()
	for z: int in range(count.y):
		for x: int in range(count.x):
			var a := z*(count.x+1)+x
			var b := a+count.x+1
			var center_at: Vector3=(vertices[a]+vertices[b+1])*.5
			var near := nearest(center_at)
			if float(near.distance)<16 or float(near.distance)>70: continue
			for index: int in [a,a+1,b+1,a,b+1,b]: faces.append(vertices[index])
	if faces.is_empty(): return
	var body := StaticBody3D.new()
	body.name="RunoffTerrainCollision"
	body.collision_layer=1
	body.collision_mask=2
	body.set_meta("surface_id",generator.definition.shoulder_surface)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.shape=shape
	body.add_child(collider)
	dressing.add_child(body)


func _build_mountain_shoulders() -> void:
	# A matching visual/collision apron joins only the mountain bank to the road.
	# The opposite bank stays open so the visible cliff remains a real drop.
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for i: int in range(route.points.size()-1):
		var side := generator.definition.mountain_side_at(route.distances[i])
		var next_side := generator.definition.mountain_side_at(route.distances[i+1])
		if absf(side)<.01 or side*next_side<=0: continue
		var rows: Array[PackedVector3Array] = []
		for row: int in [i,i+1]:
			var edge := generator.vertex_at(row,2 if side<0 else 6)
			var across := route.rights[row]*signf(side)
			var far := edge+across*5
			far.y=rendered_height_at(far.x,far.z)+.025
			var points := PackedVector3Array()
			for j: int in range(6):
				var p := edge.lerp(far,float(j)/5)
				if j>0: p.y=maxf(p.y,rendered_height_at(p.x,p.z)+.025)
				points.append(p)
			rows.append(points)
		for j: int in range(5):
			var a: Vector3=rows[0][j]
			var b: Vector3=rows[1][j]
			var c: Vector3=rows[0][j+1]
			var d: Vector3=rows[1][j+1]
			var vertices: Array=[a,b,c,c,b,d] if side>0 else [a,c,b,c,d,b]
			for vertex: Vector3 in vertices: builder.add_vertex(vertex)
			count+=6
	if count==0: return
	builder.generate_normals()
	var mesh := builder.commit()
	var visual := MeshInstance3D.new()
	visual.name="MountainShoulderJoin"
	visual.mesh=mesh
	var material := ShaderMaterial.new()
	material.shader=preload("res://assets/shaders/stage_ground.gdshader")
	material.set_shader_parameter("alpine_terrain",true)
	_theme_ground(material)
	visual.material_override=material
	dressing.add_child(visual)
	var body := StaticBody3D.new()
	body.name="MountainShoulderCollision"
	body.collision_layer=1
	body.collision_mask=2
	body.set_meta("surface_id",3)
	var collision := CollisionShape3D.new()
	collision.shape=mesh.create_trimesh_shape()
	body.add_child(collision)
	dressing.add_child(body)


func _build_mountains() -> void:
	if generator.definition.environment_id=="coast":
		var sea := MeshInstance3D.new()
		sea.name = "CoastalOcean"
		var plane := PlaneMesh.new()
		plane.size = Vector2(14000,14000)
		sea.mesh = plane
		sea.position = center
		sea.position.y = -25
		var material := ShaderMaterial.new()
		material.shader = preload("res://assets/shaders/coastal_ocean.gdshader")
		sea.material_override = material
		dressing.add_child(sea)
		return
	# Reuse approved faceted silhouettes, expanding the background around the entire stage.
	var sample := RallySampleLandscape.new()
	sample.center = center
	sample.dressing.free()
	sample.dressing = dressing
	sample._build_mountains()
	for child: Node in dressing.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("MountainLayer"):
			child.scale = Vector3(2.8,1.65,2.8)
			child.position = center-child.scale*center
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			child.material_override = _rock_material(.012)
		elif str(child.name) == "DistantValleyFloor":
			child.scale = Vector3(1.5,1,1.5)
			# The background floor must never intersect a lower section of the route.
			var minimum := route.points[0].y
			for point: Vector3 in route.points: minimum = minf(minimum,point.y)
			child.position.y = minimum-100
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sample.dressing = null
	sample.free()


func _rock_material(scale_value: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader=preload("res://assets/shaders/painted_mountain.gdshader")
	material.set_shader_parameter("rock_albedo",preload("res://assets/brushline/mountain-rock.png"))
	material.set_shader_parameter("rock_scale",scale_value)
	return material


func _build_highland_edges() -> void:
	if generator.definition.environment_id!="highland" or generator.definition.mountain_cliff_sections.is_empty(): return
	var rocks := RallySampleMeshes.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(generator.definition.seed_value)
	for section: Vector3 in generator.definition.mountain_cliff_sections:
		var mountain_side := signf(section.z)
		var s := section.x+18.0
		while s<section.y-14:
			var station := s+rng.randf_range(-9,9)
			var half := route.width_at(station)*.5
			var shoulder := ground_at(station,mountain_side*(half+15+rng.randf_range(-2,5)))
			var at := to_local(shoulder)
			var height := rng.randf_range(2.5,6.5)
			var span := rng.randf_range(2.5,5.5)
			var rock_color := Color("64767b").lerp(Color("879293"),rng.randf_range(0,0.55))
			rocks.ellipsoid(Vector3(span,height,span*rng.randf_range(.65,1.15)),at+Vector3.UP*height*.42,rock_color,Vector3(0,rng.randf_range(-PI,PI),rng.randf_range(-.12,.12)))
			s += rng.randf_range(32,48)
	var face := MeshInstance3D.new()
	face.name = "HighlandRidgeOutcrops"
	face.mesh = rocks.finish()
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	face.material_override = _rock_material(.10)
	dressing.add_child(face)


func _build_obstacles() -> void:
	var body := StaticBody3D.new()
	body.name = "CombinedSceneryObstacles"
	body.collision_layer = 4
	body.collision_mask = 2
	for placement: Dictionary in foliage.placements:
		var tree: bool = placement.kind in ["pine","umbrella"]
		var rock: bool = placement.kind=="rock" and placement.scale>0.8 and absf(placement.lateral)<11
		if (not tree and not rock) or absf(placement.lateral) > 14: continue
		var collision := CollisionShape3D.new()
		if tree:
			var cylinder := CylinderShape3D.new()
			cylinder.radius = 0.20*float(placement.scale)
			cylinder.height = 4*float(placement.scale)
			collision.position = placement.point+Vector3.UP*cylinder.height*0.5
			collision.shape = cylinder
		else:
			var sphere := SphereShape3D.new()
			sphere.radius = 0.6*float(placement.scale)
			collision.position = placement.point+Vector3.UP*0.4*float(placement.scale)
			collision.shape = sphere
		body.add_child(collision)
	if body.get_child_count()>0:
		add_child(body)
		obstacles.append(body)
	else: body.free()


func _build_gravel() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 164307
	var mesh := RallySampleGravel.pebble_mesh()
	for start: int in range(0,int(route.length)-20,40):
		if generator.definition.surface_id(start+20) != 1: continue
		var transforms: Array[Transform3D] = []
		for i: int in range(1600):
			var s := rng.randf_range(start,start+40)
			var lateral := rng.randf_range(-2.7,2.7)
			if absf(absf(lateral)-0.8)<0.28 and rng.randf()<0.75: continue
			var at := ground_at(s,lateral)+Vector3.UP*0.001
			var radius := rng.randf_range(0.025,0.055)
			var basis := route.pose_at(s).basis*Basis(Vector3.UP,rng.randf()*TAU)
			transforms.append(Transform3D(basis.scaled_local(Vector3(radius,rng.randf_range(0.004,0.014),radius)),at))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = transforms.size()
		var center := Vector3.ZERO
		for transform: Transform3D in transforms: center += transform.origin
		if not transforms.is_empty(): center /= transforms.size()
		for i: int in range(transforms.size()):
			var local := transforms[i]
			local.origin -= center
			mm.set_instance_transform(i,local)
		var visual := MultiMeshInstance3D.new()
		visual.name = "Aggregate%d"%start
		visual.position = center
		visual.multimesh = mm
		visual.visibility_range_end = 75*RallySampleDressing.VISIBILITY_SCALE
		visual.visibility_range_end_margin = 12
		visual.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dressing.add_child(visual)
		gravel_batches += 1


func _build_guardrails() -> void:
	var body := StaticBody3D.new()
	body.name = "CombinedGuardrails"
	body.collision_layer = 4
	body.collision_mask = 2
	for section: Vector2 in generator.definition.guardrail_sections:
		for s: int in range(int(section.x),int(section.y),4):
			var angle := route.tangent_at(s).signed_angle_to(route.tangent_at(s+8),Vector3.UP)
			if absf(angle)<0.025: continue
			var lateral := signf(angle)*(route.width_at(s)*0.5+1.1)
			var a := ground_at(s,lateral)+Vector3.UP*0.62
			var b := ground_at(s+4,lateral)+Vector3.UP*0.62
			var rotation := Basis.looking_at((b-a).normalized()).get_euler()*180/PI
			var rail := GrayboxGeometry.box(dressing,"Guardrail",Vector3(0.12,0.18,a.distance_to(b)+0.1),(a+b)*0.5,Color("929b8d"),false,rotation)
			(rail.get_child(0) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var collision := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(0.12,0.18,a.distance_to(b)+0.1)
			collision.shape = shape
			collision.position = (a+b)*0.5
			collision.rotation_degrees = rotation
			body.add_child(collision)
			var post := GrayboxGeometry.box(dressing,"RailPost",Vector3(0.11,0.70,0.11),a-Vector3.UP*0.3,Color("5e6b60"))
			(post.get_child(0) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if body.get_child_count()>0:
		add_child(body)
		obstacles.append(body)
	else: body.free()


func spectator_intrusion(point: Vector3) -> bool:
	for region: Dictionary in spectator_regions:
		var a: Vector3 = region.a
		var b: Vector3 = region.b
		var delta := Vector2(b.x-a.x,b.z-a.z)
		var t := clampf(Vector2(point.x-a.x,point.z-a.z).dot(delta)/maxf(delta.length_squared(),0.01),0,1)
		var at := a.lerp(b,t)
		if absf(point.y-at.y)<4 and Vector2(point.x-at.x,point.z-at.z).length()<2.3: return true
	return false


func set_quality(low: bool) -> void:
	for batch: MultiMeshInstance3D in grass_batches: batch.visible = not low
	for batch: MultiMeshInstance3D in all_batches:
		if str(batch.name).begins_with("Aggregate"): batch.visible = not low
		elif not str(batch.name).begins_with("grass"):
			batch.visibility_range_end = minf(286,RallySampleDressing.default_visibility(str(batch.name))) if low else RallySampleDressing.default_visibility(str(batch.name))


func _theme_ground(material: ShaderMaterial) -> void:
	material.set_shader_parameter("rock_albedo",preload("res://assets/brushline/mountain-rock.png"))
	var colors: Array=RallyScreenprintStyle.current().biome_palettes[generator.definition.environment_id]
	material.set_shader_parameter("grass_dark",colors[0])
	material.set_shader_parameter("grass_light",colors[1])


func _build_landmarks() -> void:
	for entry: Dictionary in generator.definition.landmarks:
		var root := Node3D.new()
		root.name = entry.kind.capitalize()
		dressing.add_child(root)
		root.position = ground_at(entry.s,entry.side*18)
		root.rotation.y = route.pose_at(entry.s).basis.get_euler().y
		var builder := RallySampleMeshes.new()
		match entry.kind:
			"lighthouse":
				root.add_child(RallyLighthouseBeacon.new())
				builder.cone(3,2.1,20,Vector3(0,10,0),Color("eee3c7"),12)
				builder.cone(2.65,2.4,2,Vector3(0,8,0),Color("c45d3e"),12)
				builder.cone(3.3,3.3,.4,Vector3(0,20,0),Color("4c6966"),12)
				builder.cone(2.0,2.0,3,Vector3(0,21.5,0),Color("a6d2ce"),8)
				builder.cone(3,0,2,Vector3(0,24,0),Color("c45d3e"),8)
				builder.box(Vector3(1.3,2.5,.2),Vector3(0,1.25,2.9),Color("314f51"))
			"stones":
				for i: int in range(7):
					var angle := i*TAU/7
					builder.ellipsoid(Vector3(1.1,2.6+i%2,1.1),Vector3(sin(angle)*5,1.6,cos(angle)*5),Color("7e929c"))
				builder.box(Vector3(3.2,.65,1.5),Vector3(0,.33,0),Color("a2b0ad"))
			_:
				builder.box(Vector3(8,5,6),Vector3(0,2.5,0),Color("a95132"))
				for side: float in [-1,1]:
					builder.box(Vector3(5.1,.25,7),Vector3(side*2,6,0),Color("594e45"),Vector3(0,0,-side*.65))
				builder.box(Vector3(1.6,2.8,.15),Vector3(0,1.4,3.05),Color("e2b26b"))
				for side: float in [-1,1]: builder.box(Vector3(1.4,1.5,.16),Vector3(side*2.4,2.8,3.05),Color("a9c8bc"))
		var mesh := MeshInstance3D.new()
		mesh.mesh = builder.finish()
		root.add_child(mesh)
		if entry.kind!="stones":
			mesh.visible=false
			RallyScreenprintProps.add(root,"lighthouse" if entry.kind=="lighthouse" else "cabin")


func rendered_height_at(x: float,z: float) -> float:
	# Interpolate the exact triangles used by StageTerrain, not the analytic
	# noise function between grid samples (which can float metres over slopes).
	if terrain_vertices.is_empty(): return height_at(x,z)
	var cell := (Vector2(x,z)-terrain_start)/terrain_cell_size
	var ix := clampi(floori(cell.x),0,terrain_count.x-1)
	var iz := clampi(floori(cell.y),0,terrain_count.y-1)
	var u := clampf(cell.x-ix,0,1)
	var v := clampf(cell.y-iz,0,1)
	var a := iz*(terrain_count.x+1)+ix
	var b := a+terrain_count.x+1
	if u>=v: return terrain_vertices[a].y*(1-u)+terrain_vertices[a+1].y*(u-v)+terrain_vertices[b+1].y*v
	return terrain_vertices[a].y*(1-v)+terrain_vertices[b+1].y*u+terrain_vertices[b].y*(v-u)


func terrain_slope_at(point: Vector3) -> float:
	var dx := (rendered_height_at(point.x+.5,point.z)-rendered_height_at(point.x-.5,point.z))
	var dz := (rendered_height_at(point.x,point.z+.5)-rendered_height_at(point.x,point.z-.5))
	return Vector2(dx,dz).length()
