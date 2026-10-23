class_name Foliage
extends RefCounted
## Trees and grass built in code: tapered trunks and branches, leaf clusters made of crossed
## alpha-tested cards with a drawn leaf texture, conifers from drooping needle sprays, and
## small grass clumps for the verges. Canopy normals point away from the crown's centre so the
## light falls on a tree as a whole (soft round shading) instead of on each flat card.

static var _leaf_tex: ImageTexture
static var _needle_tex: ImageTexture
static var _grass_tex: ImageTexture

# ------------------------------------------------------------------ textures
static func _blend(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var o := img.get_pixel(x, y)
	var a := c.a + o.a * (1.0 - c.a)
	if a <= 0.0:
		return
	var rgb := (Color(c.r, c.g, c.b) * c.a + Color(o.r, o.g, o.b) * o.a * (1.0 - c.a)) / a
	img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, a))

static func leaf_texture() -> ImageTexture:
	## a spray of small leaves on a transparent card
	if _leaf_tex != null:
		return _leaf_tex
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.3, 0.1, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 150:
		# leaves concentrate towards the middle of the card so its square outline never shows
		var r := sqrt(rng.randf()) * n * 0.44
		var a0 := rng.randf() * TAU
		var cx := n * 0.5 + cos(a0) * r
		var cy := n * 0.5 + sin(a0) * r
		var ang := rng.randf() * TAU
		var ln := rng.randf_range(9.0, 16.0)
		var wd := ln * rng.randf_range(0.38, 0.5)
		var shade := rng.randf_range(0.55, 1.0)
		var col := Color(0.30, 0.52, 0.16).lerp(Color(0.52, 0.66, 0.22), rng.randf()) * shade
		var ca := cos(ang)
		var sa := sin(ang)
		for yy in range(int(cy - ln) - 1, int(cy + ln) + 2):
			for xx in range(int(cx - ln) - 1, int(cx + ln) + 2):
				var dx := xx - cx
				var dy := yy - cy
				var u := (dx * ca + dy * sa) / ln
				var v := (-dx * sa + dy * ca) / wd
				var d := u * u + v * v
				if d < 1.0:
					var vein := 1.0 - 0.18 * exp(-v * v * 40.0)       # a lighter mid-rib
					_blend(img, xx, yy, Color(col.r * vein, col.g * vein, col.b * vein, clampf((1.0 - d) * 6.0, 0.0, 1.0)))
	img.generate_mipmaps()
	_leaf_tex = ImageTexture.create_from_image(img)
	return _leaf_tex

static func needle_texture() -> ImageTexture:
	## a fir spray: a stem along the card with needles fanning out to both sides
	if _needle_tex != null:
		return _needle_tex
	var w := 128
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.08, 0.16, 0.08, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for side_stem in 5:
		var sx := w * 0.5 + (side_stem - 2) * 14.0
		var y0 := 20.0 + absf(float(side_stem - 2)) * 28.0
		for y in range(int(y0), h - 6):
			var t := float(y - y0) / float(h - y0)
			var spread := (1.0 - t) * 22.0 + 6.0
			for k in 2:
				var sgn := -1.0 if k == 0 else 1.0
				if rng.randf() < 0.55:
					var ln := spread * rng.randf_range(0.7, 1.0)
					var col := Color(0.10, 0.22, 0.10).lerp(Color(0.18, 0.32, 0.14), rng.randf())
					for s in range(int(ln)):
						_blend(img, int(sx + sgn * s), int(y + s * 0.45), Color(col.r, col.g, col.b, 0.95))
			_blend(img, int(sx), y, Color(0.16, 0.12, 0.08, 1.0))
	img.generate_mipmaps()
	_needle_tex = ImageTexture.create_from_image(img)
	return _needle_tex

static func grass_texture() -> ImageTexture:
	## blades of grass rising from the bottom edge of the card
	if _grass_tex != null:
		return _grass_tex
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.4, 0.15, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for b in 70:
		var x0 := rng.randf_range(4.0, w - 4.0)
		var ht := rng.randf_range(0.45, 0.98) * h
		var lean := rng.randf_range(-0.35, 0.35)
		var col := Color(0.36, 0.48, 0.17).lerp(Color(0.55, 0.58, 0.26), rng.randf())
		for s in range(int(ht)):
			var t := float(s) / ht
			var x := x0 + lean * s * t
			var half := 1.6 * (1.0 - t)
			var c := col * (0.55 + 0.45 * t)
			for dx in range(int(-half) - 1, int(half) + 2):
				_blend(img, int(x) + dx, h - 1 - s, Color(c.r, c.g, c.b, clampf(half + 0.6 - absf(dx), 0.0, 1.0)))
	img.generate_mipmaps()
	_grass_tex = ImageTexture.create_from_image(img)
	return _grass_tex

# ------------------------------------------------------------------ materials
static func bark_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.24, 0.19, 0.14)
	m.roughness = 0.95
	return m

static func card_material(tex: Texture2D, backlight: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.vertex_color_use_as_albedo = true            # per-tree tint from the MultiMesh colour
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.85
	m.backlight_enabled = true
	m.backlight = backlight
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

# ------------------------------------------------------------------ geometry helpers
static func _limb(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, sides: int) -> void:
	## a tapered tube from a to b
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT).normalized()
	var up := side.cross(axis).normalized()
	for i in sides:
		var t0 := TAU * i / sides
		var t1 := TAU * (i + 1) / sides
		var d0 := side * cos(t0) + up * sin(t0)
		var d1 := side * cos(t1) + up * sin(t1)
		var v := [a + d0 * ra, a + d1 * ra, b + d1 * rb, b + d0 * rb]
		var nn := [d0, d1, d1, d0]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(nn[k])
			st.set_uv(Vector2(float(i) / sides, 1.0 if k in [2, 3] else 0.0))
			st.add_vertex(v[k])

static func _card(st: SurfaceTool, c: Vector3, right: Vector3, up: Vector3, nrm_from: Vector3, uv_flip := false) -> void:
	## one textured quad centred on c; its normal points away from nrm_from (the crown's centre)
	var n := (c - nrm_from).normalized()
	n = (n + Vector3.UP * 0.35).normalized()
	var p := [c - right - up, c + right - up, c + right + up, c - right + up]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	if uv_flip:
		uv = [Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_uv(uv[k])
		st.add_vertex(p[k])

static func _random_dir(rng: RandomNumberGenerator) -> Vector3:
	return Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()

# ------------------------------------------------------------------ trees (origin at the foot of the trunk)
static func broadleaf_mesh(seed_: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_h := rng.randf_range(4.0, 5.2)
	var lean := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
	var top := Vector3(0, trunk_h, 0) + lean
	_limb(bark, Vector3(0, -0.3, 0), top, 0.30, 0.17, 8)
	var crown_c := top + Vector3(0, rng.randf_range(1.6, 2.3), 0)
	var crown_r := Vector3(rng.randf_range(2.8, 3.6), rng.randf_range(2.4, 3.0), rng.randf_range(2.8, 3.6))
	var tips: Array[Vector3] = []
	for b in rng.randi_range(6, 8):
		var h := rng.randf_range(0.55, 1.0)
		var a := Vector3(0, trunk_h * h, 0) + lean * h
		var ang := TAU * b / 7.0 + rng.randf_range(-0.3, 0.3)
		var d := Vector3(cos(ang), rng.randf_range(0.45, 1.0), sin(ang)).normalized()
		var tip := a + d * rng.randf_range(2.0, 3.4)
		_limb(bark, a, tip, 0.11, 0.035, 5)
		tips.append(tip)
	# leaf clusters: around the branch tips and filling the crown's shell
	var centres: Array[Vector3] = []
	for t in tips:
		centres.append(t)
	for k in 34:
		var dir := _random_dir(rng)
		var shell := rng.randf_range(0.55, 0.95)
		centres.append(crown_c + Vector3(dir.x * crown_r.x, dir.y * crown_r.y, dir.z * crown_r.z) * shell)
	for c in centres:
		for q in 3:
			var r := _random_dir(rng)
			var u := r.cross(_random_dir(rng)).normalized()
			var s := rng.randf_range(0.85, 1.25)
			_card(leaves, c, r * s, u * s, crown_c, q == 1)
	var mesh := ArrayMesh.new()
	bark.commit(mesh)
	mesh.surface_set_material(0, bark_material())
	leaves.commit(mesh)
	mesh.surface_set_material(1, card_material(leaf_texture(), Color(0.32, 0.42, 0.12)))
	return mesh

static func conifer_mesh(seed_: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sprays := SurfaceTool.new()
	sprays.begin(Mesh.PRIMITIVE_TRIANGLES)
	var height := rng.randf_range(10.0, 13.5)
	_limb(bark, Vector3(0, -0.3, 0), Vector3(0, height, 0), 0.28, 0.04, 7)
	var y := 1.6
	var whorl := 0
	while y < height - 0.4:
		var t := (y - 1.6) / (height - 2.0)
		var reach := lerpf(2.9, 0.45, t) * rng.randf_range(0.85, 1.1)
		var count := 7 if t < 0.7 else 5
		for b in count:
			var ang := TAU * b / count + whorl * 0.45 + rng.randf_range(-0.2, 0.2)
			var out := Vector3(cos(ang), 0, sin(ang))
			var droop := rng.randf_range(0.18, 0.4)
			var dir := (out - Vector3.UP * droop).normalized()
			var base := Vector3(0, y, 0)
			var c := base + dir * reach * 0.55
			var side := out.cross(Vector3.UP).normalized()
			# a flat spray along the branch and a second one tilted across it for volume
			_card(sprays, c, side * reach * 0.36, dir * reach * 0.55, Vector3(0, y + 0.8, 0))
			_card(sprays, c, (side * 0.5 + Vector3.UP * 0.5).normalized() * reach * 0.3, dir * reach * 0.55, Vector3(0, y + 0.8, 0), true)
		y += rng.randf_range(0.55, 0.75)
		whorl += 1
	var mesh := ArrayMesh.new()
	bark.commit(mesh)
	mesh.surface_set_material(0, bark_material())
	sprays.commit(mesh)
	mesh.surface_set_material(1, card_material(needle_texture(), Color(0.12, 0.2, 0.08)))
	return mesh

static func grass_mesh() -> ArrayMesh:
	## a clump: three crossed cards, about 0.5 m tall, bent slightly outwards
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var ang := PI * k / 3.0
		var right := Vector3(cos(ang), 0, sin(ang)) * 0.45
		var up := Vector3(0, 0.27, 0)
		var c := Vector3(0, 0.26, 0)
		var p := [c - right - up, c + right - up, c + right + up + right * 0.15, c - right + up - right * 0.15]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uv[i])
			st.add_vertex(p[i])
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	var m := card_material(grass_texture(), Color(0.3, 0.38, 0.1))
	m.alpha_scissor_threshold = 0.4
	mesh.surface_set_material(0, m)
	return mesh
