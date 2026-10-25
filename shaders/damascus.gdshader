// ============================================================
//  花纹钢 / 大马士革钢 程序化着色器
//  UV: u = 沿刀身长度 (0 柄端 -> 1 刀尖)
//      v = 刀背(0) -> 刀刃(1)
//  现实依据：
//   折叠锻打 = 层数按 2^n 增长，酸洗后高碳层(珠光体/马氏体)被三氯化铁快速
//   腐蚀变暗，镍钢(15N20)或低碳铁抗腐蚀保持亮白，于是层与层显现为明暗条纹。
//   扭转 = 把层理沿坯料轴向旋转，磨平后表面出现人字/斜纹。
// ============================================================
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

const float TAU_ = 6.28318530718;

uniform float layer_freq : hint_range(1.0, 220.0) = 38.0; // 肉眼可见层数
uniform float twist : hint_range(0.0, 4.0) = 0.0;         // 扭转强度 0..3
uniform float chevron : hint_range(0.5, 6.0) = 2.0;       // 断面 V 形密度
uniform int style = 1;                                    // 0直纹 1扭转 2雨滴 3羽纹 4火焰纹
uniform float contrast : hint_range(0.0, 1.0) = 0.8;      // 两种钢的腐蚀反差
uniform float etch : hint_range(0.0, 1.0) = 0.0;          // 酸洗显现度
uniform float grain : hint_range(0.0, 1.0) = 0.28;        // 折叠紊乱度
uniform vec3 col_dark : source_color = vec3(0.17, 0.18, 0.21);
uniform vec3 col_bright : source_color = vec3(0.88, 0.89, 0.90);
uniform float base_rough : hint_range(0.0, 1.0) = 0.16;
uniform float grind_marks : hint_range(0.0, 1.0) = 0.25;  // 砂带磨痕
uniform float hot : hint_range(0.0, 1.0) = 0.0;           // 热态自发光
uniform vec3 hot_col : source_color = vec3(1.0, 0.36, 0.07);
uniform float seed = 12.0;

// 覆土烧刃：clay_tex 的 R 通道 = 泥层厚度（1 = 厚土，冷却慢，不硬化）
uniform sampler2D face_tex : filter_linear, repeat_disable;
uniform float face_relief = 1.0;
uniform float etch_relief = 1.0;   // 花纹蚀刻的凹凸强度
uniform float aniso = 0.0;         // 各向异性强度（研磨方向决定）
uniform bool aniso_on = true;      // 对比开关：关掉 = 普通高光
uniform vec4 face_rect = vec4(0.0, 0.0, 1.0, 1.0);   // xy=UV 起点, zw=UV 尺寸
uniform sampler2D clay_tex : filter_linear, repeat_disable;
uniform float hamon : hint_range(0.0, 1.0) = 0.0;

varying vec3 vwp;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031 + seed * 0.017);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h21(i);
	float b = h21(i + vec2(1.0, 0.0));
	float c = h21(i + vec2(0.0, 1.0));
	float d = h21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	vwp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;

	// --- 折叠/锻打留下的组织紊乱 ---
	float w1 = fbm(vec2(u * 5.0, v * 2.5) + seed);
	float w2 = fbm(vec2(u * 13.0 + 31.0, v * 6.0 + 17.0) + seed);
	float uu = u + (w1 - 0.5) * grain * 0.11;
	float vv = v + (w2 - 0.5) * grain * 0.11;

	// --- 层理坐标 ---
	float coord = vv;
	if (style == 0) {
		// 直纹 / 梯纹：层理平直，仅轻微起伏
		coord = vv + sin(uu * TAU_ * chevron) * 0.012 * twist;
		coord += (w2 - 0.5) * 0.02;
	} else if (style == 1) {
		// 扭转纹：沿刀身形成人字 / 斜纹
		float tri = abs(fract(uu * chevron) - 0.5) * 2.0;
		coord = vv - tri * 0.34 * twist;
		coord += (uu - 0.5) * 0.16 * twist;
	} else if (style == 2) {
		// 雨滴纹：层理被锻打挤成水滴状团块
		coord = vv + (fbm(vec2(uu * 6.0, vv * 4.5) + 3.0) - 0.5) * 1.05;
	} else if (style == 3) {
		// 羽纹：像羽毛的斜向羽枝
		coord = vv + sin(uu * TAU_ * chevron) * 0.17 + (w2 - 0.5) * 0.26;
		coord += abs(fract(uu * 9.0) - 0.5) * 0.05;
	} else if (style == 5) {
		// 梯纹（切锻 ladder）：在坯料侧面剁一排槽再锻平，层理被切成"梯子"
		float rung = 5.5;
		float cell = floor(uu * rung);
		float fr = fract(uu * rung);
		coord = vv * (0.80 + 0.30 * h21(vec2(cell, 3.1))) + (fr - 0.5) * 0.12;
		coord += (w2 - 0.5) * 0.03;
	} else if (style == 6) {
		// 马赛克（罐锻 canister）：碎料装罐锻合，每一块的层理方向都不一样
		vec2 g = vec2(uu, vv) * vec2(8.5, 4.5);
		vec2 ip = floor(g);
		vec2 fp = fract(g);
		float best = 9.0;
		vec2 bid = ip;
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 o = vec2(float(i), float(j));
				vec2 c = o + vec2(h21(ip + o), h21(ip + o + 17.3)) - fp;
				float d = dot(c, c);
				if (d < best) {
					best = d;
					bid = ip + o;
				}
			}
		}
		float r1 = h21(bid);
		float r2 = h21(bid + 5.7);
		float ang = r1 * TAU_;
		vec2 dir = vec2(cos(ang), sin(ang));
		coord = dot(vec2(uu, vv), dir) * 0.75 + r2 * 0.55;
	} else if (style == 7) {
		// 土耳其扭绞：几根方棒捆一起扭，磨出来是一串"开花的 V"
		float k = abs(fract(uu * 2.4) - 0.5) * 2.0;
		coord = vv * (0.50 + 0.95 * k) + (1.0 - k) * 0.30 * twist;
		coord += (w1 - 0.5) * 0.06;
	} else {
		// 火焰 / 水波纹
		coord = vv + (fbm(vec2(uu * 2.6, vv * 1.8) * 2.0) - 0.5) * 0.8;
		coord += (uu - 0.5) * 0.32 * twist;
	}

	// 层数是离散的：用三角波做出明暗层
	float bands = coord * layer_freq;
	float tri = abs(fract(bands) - 0.5) * 2.0;
	float dark_layer = smoothstep(0.34, 0.62, tri);

	// 未酸洗 = 均匀抛光钢面；酸洗后高碳层变暗
	vec3 polished = vec3(0.80, 0.82, 0.85);
	vec3 etched = mix(col_bright, col_dark, dark_layer * contrast);

	// 研磨砂带痕（未酸洗时更明显）
	float marks = fbm(vec2(u * 180.0, v * 3.0)) * 0.06 * grind_marks * (1.0 - etch * 0.7);
	polished -= marks;
	etched -= marks * 0.4;

	// ---- 覆土烧刃 ----
	float clayv = texture(clay_tex, UV).r;
	if (hamon > 0.001) {
		// 覆土处 = 珠光体：几乎没有马氏体，酸洗后偏亮、花纹变淡
		float pearl = smoothstep(0.18, 0.72, clayv) * hamon;
		etched = mix(etched, mix(etched, vec3(0.74, 0.75, 0.77), 0.55), pearl);
		polished = mix(polished, polished * 1.05, pearl);
	}

	vec3 base = mix(polished, etched, etch);
	ALBEDO = base;

	// 刃文：硬化/未硬化的交界，现实中呈现为一条雾状白线
	if (hamon > 0.001) {
		float g = length(vec2(dFdx(clayv), dFdy(clayv)));
		float line = clamp(g * 7.0, 0.0, 1.0) * hamon;
		ALBEDO = mix(ALBEDO, vec3(0.96, 0.96, 0.94), line * 0.55);
	}
	// ---------- 刃面浮雕 / 金丝镶嵌 ----------
	float fm = 0.80;
	float fr = clamp(mix(base_rough, base_rough + 0.12, dark_layer * etch) + marks, 0.02, 0.95);
	float fe = 0.0;
	vec3 fec = vec3(0.0);
	if (face_relief > 0.01) {
		vec2 fuv = (UV - face_rect.xy) / max(face_rect.zw, vec2(0.0001));
		if (fuv.x < 0.0 || fuv.x > 1.0 || fuv.y < 0.0 || fuv.y > 1.0) {
			fuv = vec2(-1.0);
		}
		vec4 fc = fuv.x < 0.0 ? vec4(0.0) : texture(face_tex, fuv);
		float fd = clamp(fc.r, 0.0, 1.0);
		float fi = clamp(fc.g, 0.0, 1.0);
		if (fd > 0.005) {
			// 真正的浮雕：把深度贴图的梯度转成法线扰动（刃面 u 沿刃长、v 沿横向）
			float e2 = 0.0022;
			float gx2 = texture(face_tex, fuv + vec2(e2, 0.0)).r
				- texture(face_tex, fuv - vec2(e2, 0.0)).r;
			float gy2 = texture(face_tex, fuv + vec2(0.0, e2)).r
				- texture(face_tex, fuv - vec2(0.0, e2)).r;
			// 凹槽里压暗一点（粗糙的 AO），再让边缘反光
			float ridge2 = clamp(length(vec2(gx2, gy2)) * 18.0, 0.0, 1.0);
			base *= 1.0 - fd * 0.22;
			base += vec3(ridge2 * 0.22);
			fr = clamp(fr + ridge2 * 0.10 - fd * 0.08, 0.02, 1.0);
			// 法线：沿切线/副切线方向推，强度随深度起伏
			vec3 dn = vec3(gx2, gy2, 0.0) * face_relief * 6.0;
			NORMAL = normalize(NORMAL + dn);
		}
		if (fi > 0.01) {
			int ii2 = int(floor(fc.b * 8.0 + 0.5));
			vec3 ic2 = vec3(0.95, 0.78, 0.32);
			float im2 = 0.95;
			float ir2 = 0.26;
			float ie2 = 0.0;
			if (ii2 == 1) {
				ic2 = vec3(0.88, 0.91, 0.95); im2 = 0.95; ir2 = 0.16;
			} else if (ii2 == 2) {
				ic2 = vec3(0.93, 0.97, 1.0); im2 = 0.10; ir2 = 0.04; ie2 = 1.60;
			} else if (ii2 == 3) {
				ic2 = vec3(0.74, 0.45, 0.22); im2 = 0.90; ir2 = 0.36;
			} else if (ii2 == 4) {
				ic2 = vec3(0.12, 0.10, 0.09); im2 = 0.0; ir2 = 0.42;
			} else if (ii2 == 5) {
				ic2 = vec3(0.62, 0.16, 0.12); im2 = 0.05; ir2 = 0.38;
			}
			base = mix(base, ic2, fi * 0.92);
			fm = mix(fm, im2, fi);
			fr = mix(fr, ir2, fi);
			fe = ie2 * fi;
			fec = ic2;
		}
	}
	ALBEDO = base;
	METALLIC = fm;
	SPECULAR = 0.50;
	ROUGHNESS = fr;
	EMISSION += fec * fe;

	// ---------- 花纹的蚀刻深度 ----------
	// 层界处 dFdx/dFdy 很大 → 当成微观坡度扰法线，低碳层被蚀得凹下去
	float eam = etch * etch_relief;
	if (eam > 0.01) {
		float dxb = dFdx(dark_layer);
		float dyb = dFdy(dark_layer);
		float edge = clamp(length(vec2(dxb, dyb)) * 26.0, 0.0, 1.0);
		NORMAL = normalize(NORMAL + vec3(dxb, dyb, 0.0) * eam * 9.0);
		ALBEDO += vec3(edge * eam * 0.10);
	}

	// 酸洗产生的微观凹凸：很轻微，只为了让层界有一点反光感
	if (etch > 0.01) {
		vec3 dn = vec3(dFdx(dark_layer), dFdy(dark_layer), 0.0) * etch * 0.10;
		NORMAL = normalize(NORMAL + dn);
	}

	// 锻造加热到红热
	EMISSION = hot_col * hot * 2.0;
	if (hot > 0.01) {
		ALBEDO = mix(ALBEDO, hot_col * 0.55, hot * 0.90);
		METALLIC = 0.35;
		ROUGHNESS = 0.70;
	}
}
