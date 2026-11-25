class_name RallyTireMarks
extends RefCounted

const CAPACITY := 4096
const LIFETIME := 70.0
var visual := MultiMeshInstance3D.new()
var mesh := MultiMesh.new()
var previous: Array[Vector3] = [Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]
var linked: Array[bool] = [false,false,false,false]
var surfaces: Array[int] = [-1,-1,-1,-1]
var births := PackedFloat32Array()
var opacity := PackedFloat32Array()
var colors: Array[Color] = []
var cursor: int = 0
var count: int = 0
var fade_cursor: int = 0
var clock: float = 0
var film_tracks := false


func build(parent: Node3D) -> void:
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_colors = true
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/tire_marks.gdshader")
	plane.material = material
	mesh.mesh = plane
	mesh.instance_count = CAPACITY
	mesh.visible_instance_count = 0
	visual.name = "TransientTireMarks"
	visual.multimesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)
	births.resize(CAPACITY)
	opacity.resize(CAPACITY)
	colors.resize(CAPACITY)


func break_trails() -> void:
	linked.fill(false)


func clear() -> void:
	break_trails()
	cursor = 0
	count = 0
	mesh.visible_instance_count = 0


func update(car: RallyVehicle,dt: float) -> void:
	update_wheels(car.wheels,dt)


func update_wheels(wheels: Array[RallyWheelState],dt: float) -> void:
	clock += dt
	for i: int in range(4):
		var wheel := wheels[i]
		var id := wheel.surface.surface_id
		var active := wheel.grounded and wheel.load>100 and wheel.normal.y>0.5 and wheel.surface.water_depth<0.008 and absf(wheel.longitudinal_speed)>0.6
		if id==0:
			var slip_limit := .05 if film_tracks else .16
			var angle_limit := .035 if film_tracks else .12
			active=active and (absf(wheel.slip)>slip_limit or absf(wheel.slip_angle)>angle_limit)
		if not active:
			linked[i] = false
			continue
		if not linked[i] or surfaces[i]!=id:
			previous[i] = wheel.point
			linked[i] = true
			surfaces[i] = id
			continue
		var distance := previous[i].distance_to(wheel.point)
		if distance<0.30: continue
		if distance<2.0:
			var up := wheel.normal.normalized()
			var forward := (wheel.point-previous[i]).slide(up).normalized()
			var right := forward.cross(up).normalized()
			var basis := Basis(right,up,-forward).scaled_local(Vector3(0.23,1,distance+0.035))
			mesh.set_instance_transform(cursor,Transform3D(basis,(wheel.point+previous[i])*0.5+up*0.014))
			var color := Color("3b3022") if id!=0 else Color("141918")
			color.a = (0.33 if id==0 else 0.47) if film_tracks else (0.25 if id==2 else 0.15)
			births[cursor] = clock
			opacity[cursor] = color.a
			colors[cursor] = color
			mesh.set_instance_color(cursor,color)
			cursor = (cursor+1)%CAPACITY
			count = mini(count+1,CAPACITY)
			mesh.visible_instance_count = count
		previous[i] = wheel.point
	for n: int in range(mini(32,count)):
		var index := fade_cursor%maxi(count,1)
		var color := colors[index]
		color.a = opacity[index]*(1-smoothstep(LIFETIME*0.65,LIFETIME,clock-births[index]))
		colors[index] = color
		mesh.set_instance_color(index,color)
		fade_cursor += 1
