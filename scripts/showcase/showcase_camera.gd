class_name RallyShowcaseCamera
extends RefCounted

# A pure function of the editorial clock. Never integrate a second chase camera,
# follow chassis roll/yaw, switch shoulders, or depend on render frame rate.
static func evaluate(world: RallyShowcaseWorld,shot: Dictionary,clock: float) -> Dictionary:
	var t := float(shot.source_in)+clock-float(shot.start)
	var clip: Dictionary=world.clips[shot.clip]
	var record: Dictionary=clip.recording
	var sample := RallyGhostRecording.sample(record,t)
	var pose: Transform3D=sample.pose
	var a := RallyGhostRecording.sample(record,maxf(0,t-.12))
	var b := RallyGhostRecording.sample(record,minf(record.duration,t+.12))
	var center: Vector3=(a.pose.origin+pose.origin*2+b.pose.origin)*.25
	var telemetry := RallyShowcaseWorld.telemetry_at(clip,t)
	var s: float=telemetry[1]
	var route: RallyStageRoute=world.scene.generator.route
	var forward := (route.position_at(minf(route.length,s+15))-route.position_at(maxf(0,s-15))).normalized()
	forward.y=0; forward=forward.normalized()
	var right := forward.cross(Vector3.UP)
	var u := clampf((clock-float(shot.start))/float(shot.duration),0,1)
	var eye := center-forward*8+right*3+Vector3.UP*2.5
	var target := center+forward*4+Vector3.UP*.6
	var fov := 58.0
	match str(shot.get("camera_rail",shot.id)):
		"establish":
			eye=center-forward*24+right*lerpf(-32,-24,u)+Vector3.UP*lerpf(25,16,u)
			target=center+forward*30+Vector3.UP*5
			fov=64
		"chase":
			eye=center-forward*7+right*2.5+Vector3.UP*1.7
			target=center+forward*5+Vector3.UP*.55
			fov=64
		"side":
			eye=center+right*6-forward*1.5+Vector3.UP*3.2
			target=center+forward*2+Vector3.UP*.45
			fov=55
		"recovery":
			eye=center+right*6.4+forward*4+Vector3.UP*2.7
			target=center+Vector3.UP*.4
			fov=52
		"animals":
			var event_pose := route.pose_at(world.animal_station,0)
			eye=event_pose.origin+-event_pose.basis.x*8+event_pose.basis.z*18+Vector3.UP*4
			target=event_pose.origin+event_pose.basis.z*5+Vector3.UP*.5
			fov=53
		"coast_wide":
			eye=center+right*35-forward*22+Vector3.UP*28
			target=center+forward*22
			fov=61
		"hood":
			# Interpolated recording supplies small real chassis movement only.
			eye=pose*Vector3(0,.65,-1.05)
			target=eye-pose.basis.z*45-pose.basis.y*3
			return {"pose":Transform3D(Basis.looking_at(target-eye,pose.basis.y),eye),"fov":68.0}
		"bridge":
			var bridge := route.pose_at(770,0)
			eye=bridge.origin-bridge.basis.x*26+bridge.basis.z*20+Vector3.UP*19
			target=bridge.origin.lerp(center,.30)+Vector3.UP*.8
			fov=59
		"helicopter":
			eye=center-right*24-forward*18+Vector3.UP*12
			target=center+right*6+forward*12+Vector3.UP*5
			fov=58
		"cliff":
			eye=center-right*36-forward*28+Vector3.UP*22
			target=center+forward*20+Vector3.UP*2
			fov=58
		"night_chase":
			eye=center-forward*7.5-right*2.1+Vector3.UP*2.2
			target=center+forward*7+Vector3.UP*.7
			fov=62
		"outro":
			eye=center-forward*lerpf(10,27,u)-right*lerpf(3,14,u)+Vector3.UP*lerpf(5,20,u)
			target=center+forward*16
			fov=lerpf(58,63,u)
		"reference_chase", "reference_glide":
			# Centered game camera with a small heading lag through the bend.
			var glide: bool=shot.camera_rail=="reference_glide"
			var ahead := route.position_at(s+24)-route.position_at(s)
			var behind := route.position_at(s)-route.position_at(s-18)
			var heading := behind.lerp(ahead,.32).normalized()
			eye=center-heading*(9.6 if glide else 8.9)+Vector3.UP*(2.25 if glide else 1.96)
			target=center+ahead.normalized()*19+Vector3.UP*.82
			fov=64 if glide else 61
		"reference_overhead", "reference_departure":
			var depart: bool=shot.camera_rail=="reference_departure"
			eye=center-forward*(lerpf(13,37,u) if depart else 11)-right*lerpf(17,26,u)+Vector3.UP*lerpf(12,20,u)
			target=center+forward*(lerpf(6,22,u) if depart else 7)
			fov=lerpf(47,56,u)
		"reference_crest":
			# A fixed roadside camera lets the car recede down the far slope.
			var first := RallyShowcaseWorld.telemetry_at(clip,shot.source_in)
			var anchor := route.pose_at(first[1]+10,0)
			eye=anchor.origin+anchor.basis.x*4+anchor.basis.z*9+Vector3.UP*2.4
			target=route.position_at(first[1]+120)+Vector3.UP*6
			fov=53
		"reference_night_side":
			eye=center+forward*7+right*23+Vector3.UP*6
			target=center+forward*10
			fov=44
	var ground: float=world.scene.presentation.scenery.rendered_height_at(eye.x,eye.z)
	eye.y=maxf(eye.y,ground+1.1)
	return {"pose":Transform3D(Basis.looking_at(target-eye,Vector3.UP),eye),"fov":fov}
