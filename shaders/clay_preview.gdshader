// 覆土预览：上=刀背（覆土区），下=刀刃。
// clay_tex 的 R 通道 = 泥层厚度，梯度处画出一条"刃文"白线。
shader_type canvas_item;

uniform sampler2D clay_tex : filter_linear, repeat_disable;

void fragment() {
	float c = texture(clay_tex, UV).r;
	// 钢基底：靠近刃口磨得更亮
	vec3 steel = mix(vec3(0.55, 0.56, 0.59), vec3(0.88, 0.89, 0.91), smoothstep(0.1, 1.0, UV.y));
	// 泥：灰绿陶土
	vec3 mud = mix(vec3(0.58, 0.55, 0.45), vec3(0.44, 0.43, 0.36), smoothstep(0.0, 1.0, UV.y));
	vec3 col = mix(steel, mud, smoothstep(0.04, 0.80, c));
	// 刃文预览线（细一点，像一条雾线）
	float g = length(vec2(dFdx(c), dFdy(c)));
	col = mix(col, vec3(0.99, 0.98, 0.94), clamp(g * 7.0, 0.0, 1.0) * 0.55);
	COLOR = vec4(col, 1.0);
}
