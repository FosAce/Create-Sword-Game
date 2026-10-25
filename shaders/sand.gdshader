// ============================================================
//  海床 / 沙滩：顶点色 + 水下焦散（caustics）
//  焦散是水面对光线的聚焦，在浅水沙底上形成游动的亮网。
//  做法：两层不同方向/速度的正弦叠加，再用"脊线"取亮。
// ============================================================
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform float water_y = 0.0;
uniform vec3 caustic_col : source_color = vec3(0.70, 0.96, 0.94);
uniform float caustic_strength : hint_range(0.0, 2.0) = 1.4;
uniform float caustic_scale = 1.45;
uniform float caustic_speed = 0.55;
uniform vec3 wet_col : source_color = vec3(0.78, 0.72, 0.60);

varying vec3 vwp;

void vertex() {
	vwp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float caustic(vec2 p, float t) {
	// 三层方向不同的波动叠加，形成不规则的网状亮线
	float a = sin(dot(p, vec2(2.7, 1.9)) + t * 1.6);
	float b = sin(dot(p, vec2(-1.8, 3.1)) - t * 1.15);
	float c = sin(dot(p, vec2(4.3, -2.2)) + t * 2.05);
	float v = (a + b + c) / 3.0;
	// 取脊线（绝对值越小越亮），再锐化
	float web = 1.0 - abs(v);
	web = pow(clamp(web, 0.0, 1.0), 7.0);
	// 用另一层低频噪声调制，让亮网成团
	float clump = 0.55 + 0.75 * sin(dot(p, vec2(0.7, 0.9)) + t * 0.5);
	return clamp(web * clump, 0.0, 1.0);
}

void fragment() {
	vec3 base = COLOR.rgb;
	// 水深：水面以下才是水下
	float depth = max(0.0, water_y - vwp.y);
	float under = smoothstep(0.0, 0.18, depth);
	// 越深焦散越弱
	float atten = exp(-depth * 0.85);
	float ca = caustic(vwp.xz * caustic_scale, TIME * caustic_speed) * under * atten;

	// 湿沙带：跟着浪的涨落一起进退（沙滩上那条深色的湿印）
	float surge = 0.5 + 0.5 * sin(TIME * 0.36);
	float band = 0.10 + surge * 0.13;
	float wet = smoothstep(band + 0.06, band - 0.05, vwp.y);
	wet = clamp(wet, 0.0, 1.0);
	base = mix(base, base * 0.80, wet * 0.75);
	base = mix(base, wet_col, wet * 0.08);

	ALBEDO = base * (1.0 + ca * 0.30);
	EMISSION = caustic_col * ca * 0.55 * caustic_strength;
	ROUGHNESS = clamp(0.92 - ca * 0.25 - wet * 0.25, 0.35, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.35;
	// 高度场是三角面片拼的，逐片法线会让水下透出一块块方格 —— 沙子改成平法线
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.30));
}
