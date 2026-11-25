extends SceneTree

var car: RallyVehicle
var stage: RallyStageGenerator
var elapsed := 0.0
var station := 0.0
var lateral := 0.0
var steer := 0.0
var cap := 28.0
var drift_at := -1.0
var kick := .16
var hold := .8
var counter := 1.2
var drift_sign := -1.0
var hint := 0
var collisions := 0
var settings := {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var pair := arg.trim_prefix("--").split("=",true,1)
			settings[pair[0]]=pair[1]
	var id: String=settings.get("stage","sunset_ridge")
	var vehicle: String=settings.get("car","R200")
	var start := maxf(8,float(settings.get("start",8)))
	var duration := float(settings.get("duration",40))
	cap=float(settings.get("speed",28))
	drift_at=float(settings.get("drift",-1))
	kick=float(settings.get("kick",.16))
	hold=float(settings.get("hold",.8))
	counter=float(settings.get("counter",1.2))
	var world := Node3D.new()
	root.add_child(world)
	stage=RallyStageGenerator.new()
	var challenge := RallyShowcaseWorld.challenge_for(id,vehicle)
	stage.definition=challenge.stage
	world.add_child(stage)
	var definition := RallyContentCatalog.vehicle(vehicle)
	car=RallyVehicle.new()
	car.config=definition.physics_config()
	car.drivetrain.config=definition.drivetrain_config()
	car.aids.esp_mode=0 if drift_at>=0 else 2
	car.drivetrain.tc_mode=0 if drift_at>=0 else 2
	car.contact_monitor=true
	car.max_contacts_reported=8
	world.add_child(car)
	car.request_reset(stage.route.pose_at(start))
	for i: int in range(120): await physics_frame
	car.body_entered.connect(func(body: Node):
		if not body is StaticBody3D or not body.name.begins_with("Road"): collisions+=1)
	hint=stage.route.index_at(start)
	car.command_source=_drive
	var frames: Array=[]
	var telemetry: Array=[]
	var recorded := RallyGhostRecording.new()
	var max_lateral := 0.0
	var road_clear := true
	for tick: int in range(roundi(duration*120)+1):
		await physics_frame
		elapsed=float(tick)/120
		if tick%2!=0: continue
		recorded.capture(elapsed,car,true)
		var local := car.global_basis.inverse()*car.linear_velocity
		var slip := rad_to_deg(atan2(local.x,maxf(.5,-local.z)))
		var half := stage.route.width_at(station)*.5
		max_lateral=maxf(max_lateral,absf(lateral))
		road_clear=road_clear and absf(lateral)+car.config.body_size.x*.5<half+.3 and car.global_basis.y.y>.85
		telemetry.append([elapsed,station,car.linear_velocity.length(),slip,car.command.steer,car.command.throttle,car.command.brake,car.drivetrain.gear,car.drivetrain.rpm(),lateral,car.command.handbrake,car.aids.esp_active,car.drivetrain.tc_active])
	var data := {"stage":id,"vehicle":vehicle,"tier":0,"physics_hz":120,"sample_hz":60,"source":"physical_input_recording","start_station":start,"driver_settings":settings,"esp":car.aids.esp_mode,"tc":car.drivetrain.tc_mode,"abs":true,"recording":recorded.payload(challenge.key(),elapsed),"telemetry":telemetry,"max_lateral":max_lateral,"road_clear":road_clear,"collisions":collisions}
	var path: String=settings.get("out","res://logs/showcase/trial.json")
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(data))
	print("RECORDED ",path," ",telemetry.size()," frames, final s=",station," max_lateral=",max_lateral," clear=",road_clear)
	car.command_source=Callable()
	world.free()
	await process_frame
	quit()

func _drive(speed: float,dt: float) -> DriverCommand:
	var route := stage.route
	var projection := route.project(car.position,hint,50)
	hint=projection.index
	station=projection.s
	lateral=projection.lateral
	var look := clampf(4+speed*.45,7,16)
	var target := route.position_at(minf(station+look,route.length))
	var lane := float(settings.get("lane",0))
	if drift_at>=0 and elapsed<drift_at: lane+=float(settings.get("offset",1.5))
	if lane!=0: target+=route.pose_at(station+look).basis.x*lane
	var local := car.to_local(target)
	var angle := atan2(local.x,-local.z)
	var wanted := atan2(car.config.wheelbase*2*sin(angle),look)/car.config.max_steer_radians
	var velocity := car.global_basis.inverse()*car.linear_velocity
	var beta := atan2(velocity.x,maxf(1,-velocity.z))
	var goal := cap
	if elapsed>=float(settings.get("lift-from",INF)) and elapsed<float(settings.get("lift-to",INF)):
		goal=minf(cap,float(settings.get("lift-speed",cap)))
	for ahead: float in [0,15,30,50,80]:
		var s := clampf(station+ahead,0,route.length-12)
		var curvature := route.tangent_at(s).angle_to(route.tangent_at(s+10))/10
		var turn_speed := sqrt(4.5/maxf(curvature,.0001))
		goal=minf(goal,sqrt(turn_speed*turn_speed+7*ahead))
	var input := DriverCommand.new()
	input.throttle=clampf(.25+(goal-speed)*.3,0,1)
	input.brake=clampf((speed-goal)*.18,0,.65)
	# Slip feedback works through steering, never through artificial body forces.
	wanted += beta/car.config.max_steer_radians*.4 if absf(beta)>.14 else 0.0
	if drift_at>=0:
		var t := elapsed-drift_at
		if t>=-1.2 and t<0:
			input.throttle=0
			input.brake=.12
		elif t>=0 and t<hold:
			wanted=kick*drift_sign
			if car.drivetrain.gear>2: input.shift=-1
			input.throttle=1
			input.brake=0
		elif t>=hold and t<6:
			wanted=wanted*.8+beta/car.config.max_steer_radians*counter if absf(beta)>.07 else wanted
			wanted=clampf(wanted,-.60,.60)
			input.throttle=minf(input.throttle,.16 if absf(beta)>.10 else .35)
			input.brake=0
	steer=move_toward(steer,clampf(wanted,-.85,.85),dt*(4.0 if drift_at>=0 else 2.2))
	input.steer=steer
	return input
