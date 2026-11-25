class_name RallyReferenceHUD
extends Control

const INK := Color("fff9ee")
const AMBER := Color("ffc07c")
const PANEL := Color(0.06,0.055,0.05,0.82)
const TRACK := Color(1,1,1,0.23)
var number_font := RallyHUD._racing_font()
var font := RallyFonts.bold()
var frame: Array = []
var timer := 0.0
var penalty := 0
var gate := 0
var gate_count := 0
var revs := 0.0
var road_hint := PackedVector2Array()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	hide()

func update_frame(world: RallyShowcaseWorld, shot: Dictionary, clock: float, telemetry: Array) -> void:
	frame=telemetry
	timer=float(shot.get("timer",0))+clock-float(shot.start)
	penalty=int(shot.get("penalty",0))
	gate=world.scene.session.next_gate
	gate_count=world.scene.session.gates.size()
	var drive: RallyDrivetrainConfig=world.scene.vehicle.drivetrain.config
	revs=clampf(inverse_lerp(drive.idle_rpm,drive.redline_rpm,frame[8]),0,1)
	var route: RallyStageRoute=world.scene.generator.route
	var station: float=frame[1]
	var relative := route.pose_at(station,0).affine_inverse()
	road_hint.clear()
	for i: int in range(9):
		var local := relative*route.position_at(station+i*6)
		road_hint.append(Vector2(clampf(local.x*1.1,-35,35),18-i*4.5))
	queue_redraw()

func _draw() -> void:
	if frame.is_empty(): return
	var scale_factor := minf(size.x/1280,size.y/720)
	var view := size/scale_factor
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE*scale_factor)
	var middle := view.x*.5
	var time := RallyHUD.time_text(timer).trim_prefix("0")
	if penalty>0: time+=" (+%d s)"%penalty
	var time_px := 29 if penalty>0 else 38
	var clock_width := maxf(182,number_font.get_string_size(time,HORIZONTAL_ALIGNMENT_LEFT,-1,time_px).x+26)
	draw_rect(Rect2(middle-clock_width*.5,12,clock_width,70),PANEL)
	_center(time,Vector2(middle,46),time_px,number_font)
	_center("检查点 %d / %d"%[gate,gate_count],Vector2(middle,70),14,font)
	draw_rect(Rect2(middle-54,89,108,58),Color(PANEL,.55))
	var hint := Transform2D(0,Vector2(middle,118))*road_hint
	draw_polyline(hint,INK,2.2,true)

	var gauge := Vector2(view.x-92,view.y-152)
	draw_arc(gauge,48,deg_to_rad(142),deg_to_rad(398),48,Color(PANEL,.90),10,true)
	if revs>.001:
		draw_arc(gauge,48,deg_to_rad(142),deg_to_rad(142+256*revs),48,AMBER,4,true)
	for i: int in range(11):
		var direction := Vector2.from_angle(deg_to_rad(142+i*25.6))
		draw_line(gauge+direction*39,gauge+direction*44,INK if i%5==0 else TRACK,1.4,true)
	var gear := int(frame[7])
	_center("R" if gear<0 else ("N" if gear==0 else str(gear)),gauge+Vector2(0,13),36,number_font)
	draw_rect(Rect2(view.x-158,view.y-98,132,80),Color(PANEL,.78))
	_center(str(roundi(frame[2]*3.6)),Vector2(gauge.x,view.y-49),52,number_font)
	_center("km/h",Vector2(gauge.x,view.y-28),15,number_font)

	var at := Vector2(24,view.y-90)
	draw_rect(Rect2(at,Vector2(147,72)),Color(PANEL,.78))
	draw_string(number_font,at+Vector2(8,21),"%.2f km"%(frame[1]/1000.0),HORIZONTAL_ALIGNMENT_LEFT,-1,20,INK)
	# Distinct vector symbols identify throttle, brake and steering without color.
	draw_colored_polygon(PackedVector2Array([at+Vector2(8,37),at+Vector2(19,37),at+Vector2(19,29)]),INK)
	draw_rect(Rect2(at+Vector2(9,44),Vector2(9,7)),INK,false,1.4)
	draw_circle(at+Vector2(13.5,61),4.5,INK,false,1.4,true)
	for index: int in range(3):
		var origin := at+Vector2(28,31+index*14)
		draw_rect(Rect2(origin,Vector2(110,4)),TRACK)
		if index==2:
			var steer := clampf(float(frame[4]),-1,1)*55
			draw_line(origin+Vector2(55,0),origin+Vector2(55,4),INK,1,true)
			draw_line(origin+Vector2(55,2),origin+Vector2(55+steer,2),INK,3,true)
		else:
			draw_rect(Rect2(origin,Vector2(110*clampf(frame[5+index],0,1),4)),INK)

func _center(text: String, at: Vector2, px: int, face: Font) -> void:
	var width := face.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,px).x
	draw_string(face,at-Vector2(width*.5,0),text,HORIZONTAL_ALIGNMENT_LEFT,-1,px,INK)
