// ============================================================
//  三渲二（赛璐璐）材质
//  不用引擎内置的 DIFFUSE_TOON，而是自己写 light()：
//   · 半兰伯特 wrap → 三段色阶（阴影 / 中间调 / 亮部），边界硬
//   · 阴影区不是单纯变暗，而是混入冷色（夏日傍晚的暖冷分层）
//   · 高光用高次幂 + smoothstep 切出一小块硬边
// ============================================================
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec3 albedo_col : source_color = vec3(0.80, 0.80, 0.80);
uniform bool use_vcolor = false;      // MultiMesh 的逐实例颜色
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec3 emis_col : source_color = vec3(0.0);
uniform float emis_energy = 0.0;

// 色阶
uniform float band_low = 0.34;        // 阴影亮度
uniform float band_mid = 0.66;        // 中间调亮度
uniform vec2 edge_a = vec2(0.40, 0.45);
uniform vec2 edge_b = vec2(0.70, 0.75);
uniform vec3 shadow_tint : source_color = vec3(0.52, 0.62, 0.86);

// 高光
uniform vec3 spec_col : source_color = vec3(1.0);
uniform float spec_power = 28.0;
uniform float spec_size : hint_range(0.0, 1.0) = 0.42;
uniform float spec_gain = 0.55;

// 边缘光（勾一圈暖光，动画感）
uniform float rim = 0.0;
uniform vec3 rim_col : source_color = vec3(1.0, 0.86, 0.66);

void fragment() {
	vec3 base = albedo_col;
	if (use_vcolor) {
		base *= COLOR.rgb;
	}
	ALBEDO = base;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = emis_col * emis_energy;
	if (rim > 0.01) {
		float r = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		EMISSION += rim_col * smoothstep(0.60, 0.68, r) * rim;
	}
}

void light() {
	float wrap = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	// 三段色阶：硬过渡
	float b = band_low
		+ (band_mid - band_low) * smoothstep(edge_a.x, edge_a.y, wrap)
		+ (1.0 - band_mid) * smoothstep(edge_b.x, edge_b.y, wrap);

	vec3 lc = LIGHT_COLOR * ATTENUATION;
	// 暗部混冷色，亮部保持光源本色
	float lit = clamp((b - band_low) / max(1.0 - band_low, 0.001), 0.0, 1.0);
	vec3 col = mix(lc * shadow_tint, lc, lit);
	DIFFUSE_LIGHT += ALBEDO * col * b;

	// 卡通高光：小块硬边
	vec3 h = normalize(LIGHT + VIEW);
	float sp = pow(clamp(dot(NORMAL, h), 0.0, 1.0), spec_power);
	sp = smoothstep(spec_size, spec_size + 0.05, sp) * spec_gain * (1.0 - roughness * 0.5);
	SPECULAR_LIGHT += lc * spec_col * sp;
}
