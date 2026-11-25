class_name RallyShowcaseWorld
extends RefCounted

var viewport: SubViewport
var scene: Node3D
var actor := RallyGhostPlayer.new()
var clips: Dictionary = {}
var surface_fx := RallyReplaySurfaceFX.new()
var active_clip := ""
var animal_station := 0.0
var last_clock := -1.0
var clock_materials: Array[ShaderMaterial] = []
var headlights: Array[SpotLight3D] = []
var look := ""

# The film-only highway uses the same vehicle and stage machinery without
# registering a new selectable challenge or writing to a player's profile.
static func challenge_for(stage_id: String,vehicle_id: String) -> RallyChallengeDefinition:
	if stage_id!="reference_highway": return RallyContentCatalog.challenge(stage_id,vehicle_id)
	var challenge := RallyChallengeDefinition.new()
	challenge.stage=preload("res://resources/stages/reference_highway.tres").duplicate(true)
	challenge.vehicle=RallyContentCatalog.vehicle(vehicle_id)
	return challenge

func prepare(parent: Node,stage_id: String,vehicle_id: String,progress: Callable,visual_look: String = "") -> void:
	look=visual_look
	viewport=SubViewport.new()
	viewport.name="Showcase_"+stage_id
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	viewport.physics_object_picking=false
	viewport.audio_listener_enable_3d=false
	# Same anti-aliasing as live driving (RallyStagePresentation): FXAA, no MSAA.
	viewport.msaa_3d=Viewport.MSAA_DISABLED
	viewport.screen_space_aa=Viewport.SCREEN_SPACE_AA_FXAA
	parent.add_child(viewport)
	scene=RallyGameApp.STAGE_SCENE.instantiate()
	scene.managed_flow=true
	scene.challenge=challenge_for(stage_id,vehicle_id)
	# The wet roadside is open ground in the reference. This dressing flag
	# does not change the route, road collision profile, or recorded poses.
	if look=="night": scene.challenge.stage.mountain_cliff_sections=PackedVector3Array()
	scene.profile=RallyProfileStore.new()
	scene.profile.data=RallyProfileStore.fresh()
	scene.profile.path="user://showcase-isolated/profile.json"
	scene.free_practice=true
	scene.demonstration=true
	var generator: RallyStageGenerator=scene.get_node("Stage")
	generator.auto_build=false
	generator.definition=scene.challenge.stage
	scene.process_mode=Node.PROCESS_MODE_DISABLED
	viewport.add_child(scene)
	await generator.build_incremental(progress)
	scene.start()
	_disable_runtime(scene)
	scene.vehicle.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	scene.vehicle.freeze=true
	scene.vehicle.collision_layer=0
	scene.vehicle.collision_mask=0
	scene.vehicle.command_source=Callable()
	scene.vehicle.hide()
	scene.ghost.hide()
	# Focus/device notifications still arrive on disabled Nodes; isolate their pause signals too.
	for signal_name: String in ["safety_pause_requested","pause_requested","focus_returned"]:
		for connection: Dictionary in scene.controls.get_signal_connection_list(signal_name):
			scene.controls.disconnect(signal_name,connection.callable)
	scene.controls.set_process_input(false)
	scene.controls.set_process_unhandled_input(false)
	scene.feedback.dispose()
	for child: Node in scene.get_children():
		if child is CanvasLayer: child.hide()
		if child is AudioStreamPlayer3D: child.stop()
	scene.checkpoint_visual.hide()
	scene.debug_visual.hide()
	scene.presentation.tire_marks.visual.hide()
	scene.presentation.tail_streaks.visual.hide()
	scene.broadcast.photos_enabled=false
	scene.wildlife.events.clear()
	scene.session.phase=RallyStageSession.Phase.RUNNING
	for symbol: Sprite3D in scene.presentation.checkpoints.symbols: symbol.hide()
	if not look.is_empty(): RallyReferenceLook.apply(scene,look)
	_collect_clock_materials(scene,{})
	for node: Node in scene.vehicle.get_children():
		if node is SpotLight3D:
			headlights.append(node)
			node.reparent(scene)
	actor.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	scene.add_child(actor)
	surface_fx.film_look=look
	surface_fx.build(scene)
	for i: int in range(surface_fx.particles.size()):
		var emitter: GPUParticles3D=surface_fx.particles[i].emitter
		emitter.process_mode=Node.PROCESS_MODE_DISABLED
		emitter.use_fixed_seed=true
		emitter.seed=170+i

func add_clip(id: String,data: Dictionary) -> void:
	data["gate_times"]=[]
	for gate: float in scene.session.gates:
		var crossing := -100.0
		for row: Array in data.telemetry:
			if row[1]>=gate: crossing=row[0]; break
		data.gate_times.append(crossing)
	clips[id]=data

func render(shot: Dictionary,clock: float,dt: float,cut: bool = false) -> Array:
	for material: ShaderMaterial in clock_materials: material.set_shader_parameter("cinematic_time",clock)
	var data: Dictionary=clips[shot.clip]
	var record: Dictionary=data.recording
	var time := float(shot.source_in)+clock-float(shot.start)
	if active_clip!=str(shot.clip):
		active_clip=str(shot.clip)
		if actor.get_child_count()==0:
			actor.build(scene.challenge.vehicle,record,false)
			if not look.is_empty(): RallyReferenceLook.paint_actor(actor.get_child(0),look)
			scene.presentation.car_style._bind_lamps(actor.get_child(0))
			RallyVehiclePlate.attach(actor.get_child(0),scene.challenge.vehicle,"BRUSHLINE")
		else: actor.recording=record
		surface_fx.clear()
	actor.update(time,Vector3.ZERO,true)
	var sample := RallyGhostRecording.sample(record,time)
	var telemetry := telemetry_at(data,time)
	scene.vehicle.transform=sample.pose
	scene.vehicle.linear_velocity=-sample.pose.basis.z*float(telemetry[2])
	scene.vehicle.command.brake=telemetry[6]
	scene.session.progress=telemetry[1]
	scene.session.next_gate=1
	while scene.session.next_gate<scene.session.gates.size()-1 and scene.session.gates[scene.session.next_gate]<scene.session.progress: scene.session.next_gate+=1
	if str(shot.id)=="animals": animal_station=telemetry_at(data,float(shot.source_in)+5.8)[1]
	var camera_pose := RallyShowcaseCamera.evaluate(self,shot,clock)
	scene.camera.global_transform=camera_pose.pose
	scene.camera.fov=camera_pose.fov
	# Frame-independent absolute scene clock; the default driving camera is never run.
	scene.presentation.elapsed=clock-dt
	scene.presentation.sky_life.clock=clock-dt
	scene.presentation.checkpoints.light_time=clock-dt
	scene.presentation.update(dt,false)
	scene.presentation.environment.sky.sky_material.set_shader_parameter("cloud_drift",clock*.00035)
	var gate: int=scene.session.next_gate-1
	scene.presentation.checkpoints.beam_material.set_shader_parameter("passed_gate",gate)
	scene.presentation.checkpoints.beam_material.set_shader_parameter("passed_time",float(data.gate_times[gate])-float(shot.source_in)+float(shot.start))
	# All flock positions and wingbeats derive from the editorial clock, including seek.
	var sky: RallySkyLife=scene.presentation.sky_life
	var chapter: float=0 if shot.stage=="sunset_ridge" else (34 if shot.stage=="sunlit_cape" else 60)
	for i: int in range(sky.flocks.size()):
		var flock: Dictionary=sky.flocks[i]
		flock.time=clampf(clock-chapter-i*2,0,26)
		flock.done=false
	sky.clock=clock
	sky.advance(0,-1)
	scene.presentation.flare.current_strength=0
	scene.presentation.flare.update(scene.camera,scene.presentation.atmosphere.sun_direction,true,1)
	if look=="night":
		scene.presentation.flare.overlay.hide()
		scene.presentation.car_style.brake_material.emission_energy_multiplier=2.6 if telemetry[6]>.1 else .65
	for symbol: Sprite3D in scene.presentation.checkpoints.symbols: symbol.hide()
	# Replay a short history at an edit or seek so tire tracks don't materialize
	# from nothing on a cut. The history is local to this recording, never linked across edits.
	if not look.is_empty() and (cut or (dt==0 and not is_equal_approx(clock,last_clock))):
		surface_fx.clear()
		for step: int in range(54,0,-1):
			var past := time-step/30.0
			if past>=0: _surface_frame(record,past,1.0/30.0,false)
	# Keep GPU effects in the same clock domain, including pause.
	for entry: Dictionary in surface_fx.particles: entry.emitter.process_mode=Node.PROCESS_MODE_ALWAYS
	_surface_frame(record,time,dt,true)
	for i: int in range(headlights.size()):
		headlights[i].transform=sample.pose*Transform3D(Basis(Vector3.RIGHT,deg_to_rad(-5)),Vector3((-1 if i==0 else 1)*.65,.15,-scene.challenge.vehicle.body_size.z*.5-.25))
	_render_events(shot,clock,dt)
	last_clock=clock
	return telemetry

func _surface_frame(record: Dictionary,time: float,dt: float,emit_particles: bool) -> void:
	var sample := RallyGhostRecording.sample(record,time)
	var previous := RallyGhostRecording.sample(record,maxf(0,time-.01))
	var future := RallyGhostRecording.sample(record,minf(record.duration,time+.01))
	var span := maxf(.001,minf(record.duration,time+.01)-maxf(0,time-.01))
	var velocity: Vector3=(future.pose.origin-previous.pose.origin)/span
	var spins: Array=[]
	for i: int in range(4): spins.append((future.spins[i]-previous.spins[i])/span)
	surface_fx.update(sample,velocity,spins,dt,emit_particles)

func _render_events(shot: Dictionary,clock: float,dt: float) -> void:
	if str(shot.id)=="animals":
		var wildlife: RallyWildlife=scene.wildlife
		var clip: Dictionary=clips[shot.clip]
		animal_station=telemetry_at(clip,float(shot.source_in)+5.8)[1]
		wildlife.events=[{"s":animal_station,"side":1.0,"kind":"reindeer"}]
		wildlife.next_event=1
		wildlife.active=true
		wildlife.station=animal_station
		wildlife.side=1
		wildlife.kind="reindeer"
		wildlife.elapsed=7.0+clock-float(shot.start)
		for species: String in wildlife.skins: wildlife.skins[species].visible=species=="reindeer"
		wildlife.legs.assign(wildlife.skins.reindeer.get_meta("legs"))
		wildlife.deer.show()
		wildlife.advance(0)
	else:
		scene.wildlife.deer.hide()
		scene.wildlife.hooves.stop()
	var broadcast: RallyBroadcastHelicopter=scene.broadcast
	if str(shot.id)=="helicopter":
		broadcast.clock=clock
		broadcast.active_time=9-(clock-float(shot.start))
		broadcast.next_allowed_time=1000
		broadcast.photographed=true
		broadcast.advance(0)
		broadcast.rotor_audio.stop() # Shared soundtrack owns the single rotor voice.
	else:
		broadcast.airframe.hide()
		broadcast.rotor_audio.stop()
	if dt==0:
		for entry: Dictionary in surface_fx.particles: entry.emitter.speed_scale=0

func deactivate() -> void:
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	for entry: Dictionary in surface_fx.particles:
		entry.emitter.emitting=false
		entry.emitter.speed_scale=0
	scene.broadcast.rotor_audio.stop()
	scene.wildlife.hooves.stop()

static func telemetry_at(clip: Dictionary,time: float) -> Array:
	var values: Array=clip.telemetry
	var rate: float=clip.get("sample_hz",60)
	var index := clampi(int(time*rate),0,values.size()-2)
	var a: Array=values[index]
	var b: Array=values[index+1]
	var u := clampf((time-float(a[0]))/maxf(.0001,float(b[0])-float(a[0])),0,1)
	var result := a.duplicate()
	for i: int in [0,1,2,3,4,5,6,8,9]: result[i]=lerpf(a[i],b[i],u)
	return result

# start() explicitly enables the normal driving runtime and input children.
# Disable every owner after initialization; only the director advances this world.
func _disable_runtime(node: Node) -> void:
	# Isolation must not unregister the road collision used by replay wheel rays.
	if node is StaticBody3D: node.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	node.process_mode=Node.PROCESS_MODE_DISABLED
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	for child: Node in node.get_children(): _disable_runtime(child)

func _clock_material(material: Material,copies: Dictionary) -> Material:
	if material is not ShaderMaterial or material.shader==null: return material
	if material.shader.resource_path.get_file().get_basename() not in ["autumn_foliage","inflatable_arch","stage_water","coastal_ocean"]: return material
	var id: int=material.get_instance_id()
	if not copies.has(id):
		var copy: ShaderMaterial=material.duplicate()
		copies[id]=copy
		clock_materials.append(copy)
	return copies[id]

func _collect_clock_materials(node: Node,copies: Dictionary) -> void:
	if node is GeometryInstance3D and node.material_override!=null:
		node.material_override=_clock_material(node.material_override,copies)
	elif node is MeshInstance3D and node.mesh!=null:
		for surface: int in range(node.mesh.get_surface_count()):
			var material: Material=node.get_active_material(surface)
			if material!=null:
				var copy := _clock_material(material,copies)
				if copy!=material: node.set_surface_override_material(surface,copy)
	for child: Node in node.get_children(): _collect_clock_materials(child,copies)
