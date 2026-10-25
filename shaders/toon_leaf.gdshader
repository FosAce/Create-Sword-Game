// 双面版（树叶、棕榈叶、水草）：和三渲二主 shader 一样，只是不剔除背面
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform vec3 albedo_col : source_color = vec3(0.60, 0.85, 0.45);
uniform float roughness : hint_range(0.0, 1.0) = 0.82;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec3 emis_col : source_color = vec3(0.0);
uniform float emis_energy = 0.0;

uniform float band_low = 0.40;
uniform float band_mid = 0.72;
uniform vec2 edge_a = vec2(0.38, 0.44);
uniform vec2 edge_b = vec2(0.66, 0.72);
uniform vec3 shadow_tint : source_color = vec3(0.55, 0.68, 0.88);

uniform vec3 spec_col : source_color = vec3(1.0);
uniform float spec_power = 24.0;
uniform float spec_size : hint_range(0.0, 1.0) = 0.55;
uniform float spec_gain = 0.25;

uniform float rim = 0.0;
uniform vec3 rim_col : source_color = vec3(1.0, 0.92, 0.70);

// 叶脉（纯 UV 程序化，不需要贴图）
uniform float veins = 1.0;
uniform float vein_rows = 5.0;
uniform vec3 vein_col : source_color = vec3(0.62, 0.80, 0.42);

void fragment() {
	vec3 base = albedo_col;
	if (veins > 0.01) {
		float s = clamp(abs(UV.x - 0.5) * 2.0, 0.0, 1.0);   // 0 = 中肋, 1 = 叶缘
		// 中肋
		float rib = smoothstep(0.12, 0.0, s);
		// 侧脉：沿叶长方向的斜排细线
		float aa = fwidth(UV.y * vein_rows) * 1.6 + 0.02;
		float tv = abs(fract(UV.y * vein_rows - s * 5.0) * 2.0 - 1.0);
		float vein = smoothstep(0.58 - aa, 0.86 + aa, tv);
		vein *= 1.0 - smoothstep(0.80, 0.99, s);
		// 叶缘压暗、叶尖提亮
		float edge = smoothstep(0.68, 0.99, s);
		float tip = smoothstep(0.30, 1.0, UV.y);
		base *= 1.0 + 0.18 * tip;
		base = mix(base, mix(base, vein_col, 0.55), vein * 0.55 * veins);
		base = mix(base, base * 0.70, rib * 0.50 * veins);
		base = mix(base, base * 0.84, edge * 0.55);
	}
	ALBEDO = base;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = emis_col * emis_energy;
	if (rim > 0.01) {
		float r = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		EMISSION += rim_col * smoothstep(0.52, 0.62, r) * rim;
	}
}

void light() {
	float wrap = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	float b = band_low
		+ (band_mid - band_low) * smoothstep(edge_a.x, edge_a.y, wrap)
		+ (1.0 - band_mid) * smoothstep(edge_b.x, edge_b.y, wrap);
	vec3 lc = LIGHT_COLOR * ATTENUATION;
	float lit = clamp((b - band_low) / max(1.0 - band_low, 0.001), 0.0, 1.0);
	vec3 col = mix(lc * shadow_tint, lc, lit);
	DIFFUSE_LIGHT += ALBEDO * col * b;

	vec3 h = normalize(LIGHT + VIEW);
	float sp = pow(clamp(dot(NORMAL, h), 0.0, 1.0), spec_power);
	sp = smoothstep(spec_size, spec_size + 0.06, sp) * spec_gain;
	SPECULAR_LIGHT += lc * spec_col * sp;
}
