class_name RallyShowcaseDirector
extends Control

signal finished
signal exited
signal preparation_progress(value: float)
const MANIFEST := "res://resources/showcase/film.json"
const REFERENCE_MANIFEST := "res://resources/showcase/reference_film.json"
const DURATION := 75.0
var manifest_path := MANIFEST
var duration := DURATION
var reference_cut := false
var worlds: Dictionary = {}
var shots: Array = []
var clock := 0.0
var playing := false
var ready_to_play := false
var active_shot := -1
var active_world := ""
var image := TextureRect.new()
var dissolve := TextureRect.new()
var curtain := ColorRect.new()
var titles := Label.new()
var pause_panel := PanelContainer.new()
var soundtrack := RallyShowcaseAudio.new()
var previous_image: ImageTexture
var sample: Array = []
var failed_message := ""
var telemetry_hud := RallyShowcaseHUD.new()
var reference_hud := RallyReferenceHUD.new()
var rain := ColorRect.new()
var rain_material := ShaderMaterial.new()
var performance := RallyShowcaseMetrics.new()

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	for canvas: TextureRect in [image,dissolve]:
		canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		canvas.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		canvas.stretch_mode=TextureRect.STRETCH_SCALE
		canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE
		add_child(canvas)
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.color=Color.BLACK
	curtain.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rain.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rain_material.shader=preload("res://assets/shaders/reference_rain.gdshader")
	rain.material=rain_material
	rain.hide()
	add_child(rain)
	add_child(telemetry_hud)
	add_child(reference_hud)
	add_child(curtain)
	titles.add_theme_font_override("font",RallyFonts.bold())
	titles.add_theme_font_size_override("font_size",32)
	titles.add_theme_color_override("font_shadow_color",Color(0,0,0,.7))
	titles.add_theme_constant_override("shadow_offset_x",2)
	titles.add_theme_constant_override("shadow_offset_y",2)
	titles.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(titles)
	add_child(soundtrack)
	performance.enabled=DisplayServer.get_name()!="headless"
	for argument: String in OS.get_cmdline_args():
		if argument.begins_with("--fixed-fps") or argument.begins_with("--write-movie"): performance.enabled=false
	_build_pause()
	resized.connect(_resize)
	get_viewport().size_changed.connect(_resize)
	_resize()

func prepare() -> bool:
	var manifest: Variant=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if manifest is not Dictionary or manifest.get("shots",[]) is not Array or manifest.get("clips",{}) is not Dictionary:
		failed_message="演示素材读取失败"
		return false
	shots=manifest.get("shots",[])
	duration=float(manifest.get("duration",0))
	reference_cut=manifest.get("style","")=="reference"
	failed_message="演示驾驶素材不完整"
	# Validate the edit before allocating any 3D worlds.
	var clips := {}
	for id: String in manifest.get("clips",{}):
		var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(manifest.clips[id]))
		if data is not Dictionary or data.get("vehicle","") not in ["R200","F160","A240"]: return false
		var challenge := RallyShowcaseWorld.challenge_for(data.get("stage",""),data.vehicle)
		if challenge==null or not RallyGhostRecording.valid(data.get("recording",{}),challenge.key()): return false
		var telemetry: Variant=data.get("telemetry")
		if telemetry is not Array or telemetry.size()<2: return false
		clips[id]=data
	var groups := {}
	var end := 0.0
	for shot: Variant in shots:
		if shot is not Dictionary or not clips.has(shot.get("clip","")): return false
		var data: Dictionary=clips[shot.clip]
		if shot.get("stage","")!=data.stage or not is_equal_approx(float(shot.get("start",-1)),end): return false
		var length := float(shot.get("duration",0))
		var source := float(shot.get("source_in",-1))
		if length<=0 or source<0 or source+length>float(data.recording.duration): return false
		end+=length
		var look: String=shot.get("look","")
		if reference_cut and look not in ["day","burned","sunset","night"]: return false
		var key := world_key(shot)
		if not groups.has(key): groups[key]=[]
		else:
			var first: Dictionary=groups[key][0]
			if first.stage!=shot.stage or clips[first.clip].vehicle!=data.vehicle: return false
		groups[key].append(shot)
	if groups.is_empty() or not is_equal_approx(end,duration): return false
	var index := 0
	for key: String in groups:
		var shot: Dictionary=groups[key][0]
		var world := RallyShowcaseWorld.new()
		worlds[key]=world
		await world.prepare(self,shot.stage,str(clips[shot.clip].vehicle),func(value: float,_message: String): preparation_progress.emit((index+value)/float(groups.size())),shot.get("look",""))
		world.viewport.size=RallyNativeResolution.pixel_size(self)
		for cut: Dictionary in groups[key]:
			if not world.clips.has(cut.clip): world.add_clip(cut.clip,clips[cut.clip])
		world.render(shot,float(shot.start),0)
		world.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
		if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
		world.deactivate()
		index+=1
	failed_message=""
	ready_to_play=true
	preparation_progress.emit(1)
	return true

static func world_key(shot: Dictionary) -> String:
	return shot.get("look",shot.stage)

func _resize() -> void:
	# Render the film at the window's real pixel size, not the 1280x720 UI canvas.
	var pixels := RallyNativeResolution.pixel_size(self)
	for world: RallyShowcaseWorld in worlds.values(): world.viewport.size=pixels
	titles.position=Vector2(40,40)
	pause_panel.position=(size-Vector2(300,240))*.5
	pause_panel.size=Vector2(300,240)

func restart() -> void:
	performance.reset()
	clock=0
	active_shot=-1
	active_world=""
	for world: RallyShowcaseWorld in worlds.values():
		world.deactivate()
		world.surface_fx.clear()
		world.scene.presentation.sky_life.reset_flights()
		world.scene.presentation.checkpoints.last_gate=-1
	playing=true
	Input.mouse_mode=Input.MOUSE_MODE_HIDDEN
	pause_panel.hide()
	soundtrack.start()
	seek(0)

func _process(dt: float) -> void:
	if not ready_to_play or not playing: return
	performance.tick(Time.get_ticks_usec(),clock)
	clock=minf(duration,clock+dt)
	_render(dt)
	if clock>=duration:
		playing=false
		soundtrack.silence()
		finished.emit()

func seek(seconds: float) -> void:
	performance.break_interval()
	clock=clampf(seconds,0,duration)
	_render(0)

func _render(dt: float) -> void:
	if not ready_to_play: return
	var index := shot_at(clock)
	var shot: Dictionary=shots[index]
	var key := world_key(shot)
	var world: RallyShowcaseWorld=worlds[key]
	if active_world!=key:
		if not active_world.is_empty():
			if not reference_cut and DisplayServer.get_name()!="headless":
				previous_image=ImageTexture.create_from_image(worlds[active_world].viewport.get_texture().get_image())
				dissolve.texture=previous_image
			worlds[active_world].deactivate()
		active_world=key
		image.texture=world.viewport.get_texture()
		world.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	var cut := index!=active_shot
	if cut: world.surface_fx.clear()
	active_shot=index
	sample=world.render(shot,clock,dt,cut)
	if reference_cut:
		telemetry_hud.hide()
		titles.hide()
		dissolve.hide()
		curtain.hide()
		rain.visible=world.look=="night"
		if rain.visible:
			rain_material.set_shader_parameter("film_time",clock)
			rain_material.set_shader_parameter("headlights",.55 if shot.camera_rail=="reference_chase" else .25)
		reference_hud.visible=shot.get("hud",false)
		if reference_hud.visible: reference_hud.update_frame(world,shot,clock,sample)
	else:
		reference_hud.hide()
		telemetry_hud.model=RallyShowcaseInstruments.model(world,shot,clock,sample)
		telemetry_hud.queue_redraw()
		var chapter_start := 0.0 if index<5 else (34.0 if index<9 else 60.0)
		var chapter_time := clock-chapter_start
		titles.text=world.scene.challenge.stage.title
		titles.modulate.a=smoothstep(0,.25,chapter_time)*(1-smoothstep(1.5,2.2,chapter_time))
		dissolve.modulate.a=(1-smoothstep(0,.4,chapter_time)) if chapter_start>0 and previous_image!=null else 0
		curtain.color.a=maxf(1-smoothstep(0,.35,clock),smoothstep(duration-.6,duration,clock))
	var biome: String=world.scene.challenge.stage.environment_id
	var surface: int = world.scene.challenge.stage.surface_id(sample[1])
	soundtrack.sample(sample,world.scene.challenge.vehicle.vehicle_id,biome,shot.id,clock,not playing,duration,reference_cut,surface)

func shot_at(seconds: float) -> int:
	for i: int in range(shots.size()-1,-1,-1):
		if seconds>=float(shots[i].start): return i
	return 0

func set_playing(value: bool) -> void:
	if not ready_to_play: return
	performance.break_interval()
	playing=value
	Input.mouse_mode=Input.MOUSE_MODE_HIDDEN if playing else Input.MOUSE_MODE_VISIBLE
	pause_panel.visible=not playing
	if not playing:
		_render(0)
		pause_panel.get_child(0).get_child(1).grab_focus()
	else:
		for world: RallyShowcaseWorld in worlds.values():
			for entry: Dictionary in world.surface_fx.particles: entry.emitter.speed_scale=1 if world==worlds[active_world] else 0

func _input(event: InputEvent) -> void:
	if not ready_to_play or not visible: return
	var toggle: bool= event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_SPACE,KEY_ESCAPE]
	toggle=toggle or (event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_START)
	if toggle:
		set_playing(not playing)
		get_viewport().set_input_as_handled()
	elif not playing and event.is_action_pressed("ui_cancel"):
		set_playing(true)
		get_viewport().set_input_as_handled()

func _build_pause() -> void:
	pause_panel.theme=RallyScreenprintStyle.theme()
	add_child(pause_panel)
	var list := VBoxContainer.new()
	pause_panel.add_child(list)
	var title := Label.new()
	title.text="演示已暂停"
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(title)
	for entry: Array in [["继续播放",func(): set_playing(true),"play"],["重新播放",restart,"replay"],["返回主菜单",func(): exited.emit(),"exit"]]:
		var button := Button.new()
		button.text=entry[0]
		button.icon=load("res://assets/ui/icons/%s.svg"%entry[2])
		button.expand_icon=true
		button.add_theme_constant_override("icon_max_width",24)
		button.custom_minimum_size=Vector2(280,52)
		button.pressed.connect(entry[1])
		list.add_child(button)
	pause_panel.hide()

func _exit_tree() -> void:
	soundtrack.dispose()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
