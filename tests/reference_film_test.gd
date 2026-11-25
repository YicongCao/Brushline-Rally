extends "res://tests/test_suite.gd"

var app: RallyGameApp
var capture_dir := ""

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir=arg.trim_prefix("--capture-dir=")
	var graphical := DisplayServer.get_name()!="headless"
	root.size=Vector2i(1280,720)
	if graphical: DisplayServer.window_set_size(root.size)
	app=load("res://scenes/game/game.tscn").instantiate()
	app.profile.path="user://reference-film-test-%d/profile.json"%Time.get_ticks_usec()
	root.add_child(app)
	app.profile.data=RallyProfileStore.fresh()
	app.show_home()
	var baseline := JSON.stringify(app.profile.data)
	await create_timer(.35).timeout
	var entry := find_button("录屏复刻")
	check(entry!=null and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(entry.get_global_rect()),"Reference tile visible inside the desktop menu")
	if entry==null: finish(); return
	entry.grab_focus()
	await pad(JOY_BUTTON_A)
	var deadline := Time.get_ticks_msec()+120000
	while app.loading and Time.get_ticks_msec()<deadline: await process_frame
	var film := app.showcase
	check(is_instance_valid(film) and app.screen=="showcase","Menu confirm opens the reference cut")
	if not is_instance_valid(film): finish(); return
	film.set_process(false)
	check(film.ready_to_play and film.reference_cut and is_equal_approx(film.duration,52.375),"Reference cut has the 52.375-second runtime")
	check(film.shots.size()==11 and film.worlds.size()==4,"Eleven edits reuse four isolated looks")
	check(not film.worlds.sunset.scene.challenge.stage.stage_id in RallyContentCatalog.STAGES,"Highway is not a playable challenge")
	for shot: Dictionary in film.shots:
		var t: float=shot.start+shot.duration*.5
		film.seek(t)
		var world: RallyShowcaseWorld=film.worlds[shot.look]
		var clip: Dictionary=world.clips[shot.clip]
		check(world==film.worlds[film.active_world] and clip.source=="physical_input_recording" and clip.recording.gaps.is_empty() and clip.collisions==0,"Continuous recorded driving: "+str(shot.id))
		check(film.reference_hud.visible==shot.get("hud",false) and film.rain.visible==(shot.look=="night"),"HUD and weather follow the edit: "+str(shot.id))
		var camera: Camera3D=world.scene.camera
		var vehicle := world.actor.global_position
		var at := camera.unproject_position(vehicle)/Vector2(world.viewport.size)
		check(not camera.is_position_behind(vehicle) and Rect2(.04,.06,.92,.88).has_point(at),"Camera frames the car in "+str(shot.id))
		if film.reference_hud.visible:
			check(film.reference_hud.frame==film.sample and is_equal_approx(film.reference_hud.timer,shot.timer+shot.duration*.5),"HUD reads the active clip: "+str(shot.id))
		if shot.look!="sunset": check(world.surface_fx.marks.count>0,"Recorded contact rebuilds wheel trails on seek: "+str(shot.id))
		if shot.look=="night":
			check(world.headlights.size()==2 and world.headlights[0].visible and world.scene.presentation.environment.sky.sky_material.get_shader_parameter("film_moon"),"Night shot uses moon and projected headlights")
		if graphical and not capture_dir.is_empty(): await capture_shot(film,shot.id,t)
	film.seek(0)
	var opening: Transform3D=film.worlds.day.scene.camera.global_transform
	film.seek(50.75)
	check(opening.is_equal_approx(film.worlds.day.scene.camera.global_transform),"Last splice returns to the opening pose")
	film.seek(44.5)
	var clock := film.clock
	await pad(JOY_BUTTON_START)
	film._process(1)
	check(not film.playing and film.pause_panel.visible and film.clock==clock,"Pause freezes the editorial clock through Viewport input")
	await pad(JOY_BUTTON_A)
	check(film.playing and not film.pause_panel.visible,"South confirms the focused resume action")
	if graphical and not capture_dir.is_empty():
		root.size=Vector2i(1600,900)
		DisplayServer.window_set_size(root.size)
		await capture_shot(film,"desktop-hud",31.8)
		film.set_playing(false)
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture_dir.path_join("desktop-pause.png"))==OK,"Saved the desktop pause screenshot")
		film.set_playing(true)
	film.seek(film.duration-.01)
	film._process(.02)
	check(app.screen=="showcase_result" and not film.visible,"End of the new cut uses the replay page")
	await create_timer(.30).timeout
	var replay := find_button("再看一次")
	check(replay!=null,"Result page has a replay action")
	if replay!=null:
		replay.grab_focus()
		await pad(JOY_BUTTON_A)
		check(film.playing and film.clock==0 and app.showcase==film,"Replay reuses the reference worlds from the start")
	check(JSON.stringify(app.profile.data)==baseline and not FileAccess.file_exists(app.profile.path),"Film does not persist profile data or results")
	app.free()
	await process_frame
	finish()

func find_button(label: String) -> Control:
	for control: Control in RallyMenuInput.focusable(app.ui):
		if RallyMenuInput.token(control)==label: return control
	return null

func pad(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index=button
	event.pressed=true
	root.push_input(event)
	await process_frame
	event=event.duplicate()
	event.pressed=false
	root.push_input(event)
	await process_frame

func capture_shot(film: RallyShowcaseDirector,label: String,at: float) -> void:
	# Warm moving surface particles with the same playback path used by the app.
	film.seek(at-.85)
	for i: int in range(51):
		film._process(1.0/60.0)
		await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_dir.path_join(label+".png"))==OK,"Saved screenshot: "+label)
