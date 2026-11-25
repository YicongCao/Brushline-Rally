class_name RallyReplaySurfaceFX
extends RefCounted

# Reconstruct contact from replay poses against current stage collision. No live vehicle physics.
var wheels: Array[RallyWheelState] = []
var particles: Array[Dictionary] = []
var marks := RallyTireMarks.new()
var scene: Node3D
var definition: RallyVehicleDefinition
var film_look := ""

func build(owner_scene: Node3D) -> void:
	scene = owner_scene
	definition = scene.challenge.vehicle
	# Recorded poses are interpolated by the replay clock, not by physics ticks.
	marks.visual.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	marks.build(scene)
	marks.visual.name = "ReplayTireMarks"
	marks.film_tracks=not film_look.is_empty()
	var factory := RallyVehicleFeedback.new()
	for i: int in range(4):
		wheels.append(RallyWheelState.new())
		for kind: String in ["dust","mud","water"]:
			var emitter := factory._particle(kind)
			emitter.process_mode = Node.PROCESS_MODE_ALWAYS
			scene.add_child(emitter)
			particles.append({"wheel":i,"kind":kind,"emitter":emitter})
			if kind=="dust" and not film_look.is_empty(): _tune_film_dust(emitter)

func _tune_film_dust(emitter: GPUParticles3D) -> void:
	var material: StandardMaterial3D=emitter.draw_pass_1.surface_get_material(0)
	var process: ParticleProcessMaterial=emitter.process_material
	if film_look=="night":
		material.albedo_color=Color("bdcce9")
		material.emission=Color("9babcd")
		material.emission_energy_multiplier=.42
		process.gravity=Vector3(0,.11,0)
		process.scale_min=.33
		process.scale_max=.62
		process.spread=12
		emitter.lifetime=1.4
	elif film_look=="burned":
		material.albedo_color=Color("c0956d")
		material.emission=Color("f2a661")
		material.emission_energy_multiplier=.32
	else:
		process.scale_min=.38
		process.scale_max=.76

func update(sample: Dictionary,velocity: Vector3,spins_per_second: Array,dt: float,emit_particles: bool = true) -> void:
	if sample.is_empty():
		clear()
		return
	var pose: Transform3D = sample.pose
	for i: int in range(4):
		var wheel := wheels[i]
		var center := pose*Vector3((-0.5 if i%2==0 else .5)*definition.track_width,-sample.lengths[i],(-.5 if i<2 else .5)*definition.wheelbase)
		var query := PhysicsRayQueryParameters3D.create(center+Vector3.UP*.12,center-Vector3.UP*.46,1,[scene.vehicle.get_rid()])
		var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
		wheel.grounded = not hit.is_empty()
		wheel.load = 2500 if wheel.grounded else 0
		if not wheel.grounded: continue
		wheel.point = hit.position
		wheel.normal = hit.normal
		wheel.forward = (-pose.basis.z).rotated(pose.basis.y,sample.steer if i<2 else 0).slide(wheel.normal).normalized()
		wheel.right = wheel.forward.cross(wheel.normal)
		wheel.surface = RallySurfaceQuery.point_sample(hit.collider,hit.position)
		wheel.longitudinal_speed = velocity.dot(wheel.forward)
		wheel.lateral_speed = velocity.dot(wheel.right)
		wheel.slip_angle = atan2(wheel.lateral_speed,maxf(absf(wheel.longitudinal_speed),1))
		wheel.slip = (float(spins_per_second[i])*definition.physics_config().wheel_radius-wheel.longitudinal_speed)/maxf(absf(wheel.longitudinal_speed),1)
	if emit_particles:
		for entry: Dictionary in particles:
			var wheel := wheels[entry.wheel]
			var emitter: GPUParticles3D = entry.emitter
			var surface := wheel.surface
			var dust := surface.surface_id in [1,3,4,5] and surface.water_depth<.005
			if film_look=="night": dust=entry.wheel>=2
			emitter.speed_scale = 1 if dt>0 else 0
			emitter.emitting = dt>0 and wheel.grounded and absf(wheel.longitudinal_speed)>3 and ((entry.kind=="dust" and dust) or (entry.kind=="mud" and surface.surface_id==2 and surface.water_depth<.015) or (entry.kind=="water" and surface.water_depth>.005))
			emitter.global_position = wheel.point+Vector3.UP*.1
			emitter.global_basis = pose.basis
	if dt>0: marks.update_wheels(wheels,dt)

func clear() -> void:
	marks.clear()
	for entry: Dictionary in particles:
		entry.emitter.restart()
		entry.emitter.emitting = false

func dispose() -> void:
	for entry: Dictionary in particles:
		if is_instance_valid(entry.emitter): entry.emitter.queue_free()
	if is_instance_valid(marks.visual): marks.visual.queue_free()
