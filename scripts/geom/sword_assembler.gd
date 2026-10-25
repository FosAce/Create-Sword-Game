class_name SwordAssembler
extends RefCounted
## 从一份 SwordData 现场搭出"成品刀"节点（刀身 + 刀柄 + 护手）。
## 工作台预览、收藏馆、启动时挂架都走这一条路。


static func blank_carve_tex() -> ImageTexture:
	var img := Image.create_empty(320, 480, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	return ImageTexture.create_from_image(img)


static func build_node(s: SwordData) -> Node3D:
	var root := Node3D.new()
	if s.outline.size() < 4:
		return root

	var bm := BladeBuilder.build(s)
	if bm != null:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/damascus.gdshader")
		var u := s.damascus_uniforms()
		for k in u:
			mat.set_shader_parameter(k, u[k])
		if s.face_mask != null:
			mat.set_shader_parameter("face_tex", ImageTexture.create_from_image(s.face_mask))
			mat.set_shader_parameter("face_rect", Vector4(s.face_rect.position.x, s.face_rect.position.y, s.face_rect.size.x, s.face_rect.size.y))
		else:
			mat.set_shader_parameter("face_relief", 0.0)
		if s.clay_mask != null:
			mat.set_shader_parameter("clay_tex", ImageTexture.create_from_image(s.clay_mask))
		mat.set_shader_parameter("hamon", s.hamon)
		mat.set_shader_parameter("hot", 0.0)
		mat.next_pass = MeshKit.outline_mat(0.0007)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = mat
		root.add_child(mi)

	var info := BladeBuilder.analyze(s.mesh_outline())
	var hm := HandleBuilder.build(s, info["butt"], info["butt_dir"])
	if hm != null:
		var hmat := ShaderMaterial.new()
		hmat.shader = load("res://shaders/carve_wood.gdshader")
		var w := HandleBuilder.wood(s.handle_wood)
		hmat.set_shader_parameter("wood_dark", w["dark"])
		hmat.set_shader_parameter("wood_light", w["light"])
		if s.carve_mask != null:
			hmat.set_shader_parameter("carve_tex", ImageTexture.create_from_image(s.carve_mask))
		else:
			hmat.set_shader_parameter("carve_tex", SwordAssembler.blank_carve_tex())
		hmat.next_pass = MeshKit.outline_mat(0.0007)
		var hmi := MeshInstance3D.new()
		hmi.mesh = hm
		hmi.material_override = hmat
		root.add_child(hmi)

	var fmat := MeshKit.mat(Palette.STEEL_DARK, 0.28, 1.0)
	if s.guard_style == 2:
		fmat = MeshKit.mat(Color("c9a04a"), 0.3, 1.0)
	elif s.guard_style == 3:
		fmat = MeshKit.mat(Palette.WOOD_DARK, 0.75, 0.0)
	var fm := HandleBuilder.build_fittings(s, info["butt"], info["butt_dir"], 1)
	if fm != null:
		var fmi := MeshInstance3D.new()
		fmi.mesh = fm
		fmi.material_override = fmat
		root.add_child(fmi)
	# 尾铁单独一份 mesh + 一份材质（可以和护手不同色）
	var pm := HandleBuilder.build_fittings(s, info["butt"], info["butt_dir"], 2)
	if pm != null:
		var pmi := MeshInstance3D.new()
		pmi.mesh = pm
		pmi.material_override = MeshKit.mat(s.pommel_color, s.pommel_rough, s.pommel_metal)
		root.add_child(pmi)
	var g := SwordAssembler.gem_node(s, info["butt"], info["butt_dir"])
	if g != null:
		root.add_child(g)
	return root

## 护手宝石 + 金托座（workshop 预览和展台共用）
static func gem_node(s: SwordData, butt: Vector2, bdir: Vector2) -> Node3D:
	if s.gem_style <= 0:
		return null
	var root := Node3D.new()
	var cols := [Color("d02c2c"), Color("2f6bd0"), Color("1fa05a")]
	var col: Color = cols[clampi(s.gem_style - 1, 0, 2)]
	var axis := Vector3(bdir.x, bdir.y, 0.0).normalized()
	var pos := Vector3(butt.x, butt.y, 0.0) + axis * 0.024 + Vector3(0, 0, 0.026)
	var ring := MeshKit.add_torus(root, 0.020, 0.030, pos, Palette.GOLD, Vector3(90, 0, 0), 12)
	ring.material_override = MeshKit.mat(Palette.GOLD, 0.25, 1.0)
	var gem: MeshInstance3D
	if s.gem_shape == 1:
		# 棱形：六棱双锥 —— seg=6 / rings=2 出来就是一颗切工宝石
		gem = MeshKit.add_sphere(root, 0.026, pos, col, Vector3(1.0, 1.30, 0.80), 6, 2)
	else:
		gem = MeshKit.add_sphere(root, 0.021, pos, col, Vector3(1.0, 1.0, 0.55), 8, 6)
	gem.material_override = MeshKit.mat(col, 0.10, 0.05, col, 2.6)
	return root