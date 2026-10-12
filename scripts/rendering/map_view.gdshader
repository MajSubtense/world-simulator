shader_type canvas_item;
render_mode unshaded;

uniform sampler2D base_tex : filter_nearest, repeat_disable;
uniform sampler2D face_tex : filter_nearest, repeat_disable;
uniform sampler2D temp_tex : filter_nearest, repeat_disable;
uniform sampler2D pressure_tex : filter_nearest, repeat_disable;
uniform sampler2D wind_tex : filter_nearest, repeat_disable;
uniform sampler2D hum_atm_tex : filter_nearest, repeat_disable;
uniform sampler2D precip_tex : filter_nearest, repeat_disable;
uniform sampler2D cloud_tex : filter_nearest, repeat_disable;
uniform sampler2D snow_tex : filter_nearest, repeat_disable;
uniform sampler2D soil_tex : filter_nearest, repeat_disable;
uniform sampler2D river_tex : filter_nearest, repeat_disable;
uniform sampler2D veg_type_tex : filter_nearest, repeat_disable;
uniform sampler2D veg_density_tex : filter_nearest, repeat_disable;
uniform sampler2D temp_ema_tex : filter_nearest, repeat_disable;
uniform ivec2 field_size = ivec2(1024, 16);

// 0=land 1=height 2=temp 3=pressure 4=wind 5=hum_atm
// 6=precip 7=cloud 8=snow 9=soil 10=rivers
// 11=veg_type 12=veg_density 13=temp_ema
uniform int mode = 0;
uniform float precip_scale = 50.0;

// ---- 昼夜遮罩 ----
uniform bool show_terminator = false;
uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform int projection = 0;    // 0=RECTANGULAR 1=MOLLWEIDE
uniform float night_darkness = 0.45;   // 夜晚压暗系数（1.0=全黑，0.0=不变）

// ============================================================
//  色阶函数
// ============================================================
vec3 temp_to_color(float t) {
	float tc = clamp(t, -0.5, 1.5);
	if (tc < 0.0) return mix(vec3(0.60, 0.80, 1.0), vec3(0.10, 0.30, 0.75), tc / 0.5 + 1.0);
	if (tc < 0.20) return mix(vec3(0.05, 0.10, 0.40), vec3(0.10, 0.35, 0.75), tc / 0.20);
	if (tc < 0.40) return mix(vec3(0.10, 0.35, 0.75), vec3(0.20, 0.75, 0.80), (tc - 0.20) / 0.20);
	if (tc < 0.60) return mix(vec3(0.20, 0.75, 0.80), vec3(0.55, 0.85, 0.30), (tc - 0.40) / 0.20);
	if (tc < 0.80) return mix(vec3(0.55, 0.85, 0.30), vec3(0.95, 0.75, 0.20), (tc - 0.60) / 0.20);
	return mix(vec3(0.95, 0.75, 0.20), vec3(0.85, 0.15, 0.10), (tc - 0.80) / 0.70);
}

vec3 pressure_color(float p) {
	float t = clamp(p * 0.5 + 0.5, 0.0, 1.0);
	return mix(vec3(0.10, 0.30, 0.75), vec3(0.85, 0.30, 0.20), t);
}

vec3 wind_color(vec3 w) {
	float mag = length(w);
	if (mag < 0.001) return vec3(0.15, 0.15, 0.20);
	float ang = atan(w.z, w.x);
	float h = (ang + 3.14159265) / 6.2831853;
	vec3 dir_col = 0.5 + 0.5 * cos(6.2831853 * (h + vec3(0.0, 1.0 / 3.0, 2.0 / 3.0)));
	return dir_col * clamp(mag * 3.0, 0.2, 1.0);
}

vec3 height_color(float h, bool land) {
	if (!land) {
		float t = clamp(-h / 0.15, 0.0, 1.0);
		return mix(vec3(0.18, 0.48, 0.72), vec3(0.05, 0.16, 0.42), t);
	}
	float hh = clamp(h, 0.0, 0.70);
	if (hh < 0.05) return mix(vec3(0.86, 0.80, 0.58), vec3(0.42, 0.68, 0.35), hh / 0.05);
	if (hh < 0.12) return mix(vec3(0.42, 0.68, 0.35), vec3(0.30, 0.55, 0.28), (hh - 0.05) / 0.07);
	if (hh < 0.22) return mix(vec3(0.30, 0.55, 0.28), vec3(0.50, 0.55, 0.30), (hh - 0.12) / 0.10);
	if (hh < 0.35) return mix(vec3(0.50, 0.55, 0.30), vec3(0.60, 0.50, 0.30), (hh - 0.22) / 0.13);
	if (hh < 0.50) return mix(vec3(0.60, 0.50, 0.30), vec3(0.65, 0.60, 0.58), (hh - 0.35) / 0.15);
	return mix(vec3(0.65, 0.60, 0.58), vec3(0.95, 0.96, 0.98), clamp((hh - 0.50) / 0.20, 0.0, 1.0));
}

vec3 hum_atm_color(float h) {
	float t = clamp(h, 0.0, 1.0);
	if (t < 0.5) return mix(vec3(0.75, 0.65, 0.35), vec3(0.30, 0.65, 0.75), t * 2.0);
	return mix(vec3(0.30, 0.65, 0.75), vec3(0.05, 0.15, 0.55), (t - 0.5) * 2.0);
}

vec3 precip_color(float p) {
	float t = clamp(p * precip_scale, 0.0, 1.0);
	if (t < 0.01) return vec3(0.04, 0.04, 0.06);
	if (t < 0.25) return mix(vec3(0.10, 0.15, 0.35), vec3(0.20, 0.30, 0.65), t * 4.0);
	if (t < 0.55) return mix(vec3(0.20, 0.30, 0.65), vec3(0.55, 0.40, 0.85), (t - 0.25) / 0.30);
	if (t < 0.85) return mix(vec3(0.55, 0.40, 0.85), vec3(0.85, 0.60, 0.95), (t - 0.55) / 0.30);
	return mix(vec3(0.85, 0.60, 0.95), vec3(1.0, 0.95, 1.0), (t - 0.85) / 0.15);
}

vec3 cloud_color(float c) {
	float t = clamp(c, 0.0, 1.0);
	if (t < 0.3) return mix(vec3(0.15, 0.18, 0.25), vec3(0.55, 0.60, 0.70), t / 0.3);
	if (t < 0.7) return mix(vec3(0.55, 0.60, 0.70), vec3(0.92, 0.95, 1.0), (t - 0.3) / 0.4);
	return mix(vec3(0.92, 0.95, 1.0), vec3(0.60, 0.65, 0.75), (t - 0.7) / 0.3);
}

vec3 snow_color(float s) {
	float t = clamp(s * 5.0, 0.0, 1.0);
	if (t < 0.02) return vec3(0.10, 0.12, 0.18);
	if (t < 0.3) return mix(vec3(0.20, 0.30, 0.45), vec3(0.55, 0.65, 0.80), t / 0.3);
	if (t < 0.7) return mix(vec3(0.55, 0.65, 0.80), vec3(0.90, 0.94, 1.0), (t - 0.3) / 0.4);
	return mix(vec3(0.90, 0.94, 1.0), vec3(1.0, 1.0, 1.0), (t - 0.7) / 0.3);
}

vec3 soil_color(float w) {
	float t = clamp(w, 0.0, 1.0);
	if (t < 0.5) return mix(vec3(0.55, 0.45, 0.30), vec3(0.30, 0.55, 0.35), t * 2.0);
	return mix(vec3(0.30, 0.55, 0.35), vec3(0.05, 0.20, 0.30), (t - 0.5) * 2.0);
}

vec3 veg_type_color(float t) {
	int ti = int(t + 0.5);
	if (ti <= 0)  return vec3(0.50, 0.48, 0.45);
	if (ti == 1)  return vec3(0.95, 0.96, 0.98);
	if (ti == 2)  return vec3(0.62, 0.66, 0.56);
	if (ti == 3)  return vec3(0.18, 0.38, 0.26);
	if (ti == 4)  return vec3(0.72, 0.74, 0.38);
	if (ti == 5)  return vec3(0.34, 0.62, 0.30);
	if (ti == 6)  return vec3(0.56, 0.58, 0.34);
	if (ti == 7)  return vec3(0.88, 0.78, 0.45);
	if (ti == 8)  return vec3(0.76, 0.68, 0.38);
	if (ti == 9)  return vec3(0.08, 0.42, 0.14);
	if (ti == 10) return vec3(0.28, 0.55, 0.52);
	return vec3(0.5, 0.5, 0.5);
}

vec3 veg_density_color(float d) {
	float t = clamp(d, 0.0, 1.0);
	if (t < 0.01) return vec3(0.55, 0.50, 0.42);
	if (t < 0.3) return mix(vec3(0.55, 0.50, 0.42), vec3(0.62, 0.65, 0.40), t / 0.3);
	if (t < 0.7) return mix(vec3(0.62, 0.65, 0.40), vec3(0.35, 0.68, 0.32), (t - 0.3) / 0.4);
	return mix(vec3(0.35, 0.68, 0.32), vec3(0.08, 0.42, 0.14), (t - 0.7) / 0.3);
}

// ============================================================
//  投影：UV → 球面方向（与 MapProjection 一致）
// ============================================================
vec3 uv_to_dir(float u, float v, int proj) {
	if (proj == 0) {
		float lon = (u - 0.5) * 6.2831853;
		float lat = (0.5 - v) * 3.14159265;
		float cl = cos(lat);
		return vec3(cl * cos(lon), sin(lat), cl * sin(lon));
	}
	float mx = (u - 0.5) * 2.0;
	float my = (0.5 - v);
	if (mx * mx + 4.0 * my * my > 1.0) return vec3(0.0);
	float theta = asin(clamp(my * 2.0, -1.0, 1.0));
	float phi_term = (2.0 * theta + sin(2.0 * theta)) / 3.14159265;
	float phi = asin(clamp(phi_term, -1.0, 1.0));
	float ct = cos(theta);
	float lam = (abs(ct) > 0.001) ? 3.14159265 * mx / ct : 0.0;
	float cl = cos(phi);
	return vec3(cl * cos(lam), sin(phi), cl * sin(lam));
}

// ============================================================
//  fragment
// ============================================================
void fragment() {
	vec4 base = texture(base_tex, UV);
	vec4 fl = texture(face_tex, UV);

	int r = int(fl.r * 255.0 + 0.5);
	int g = int(fl.g * 255.0 + 0.5);
	int b = int(fl.b * 255.0 + 0.5);
	int face_idx = r + g * 256 + b * 65536;

	int W = field_size.x;
	int tx = face_idx % W;
	int ty = face_idx / W;
	vec2 fuv = vec2(
		(float(tx) + 0.5) / float(W),
		(float(ty) + 0.5) / float(field_size.y));

	bool land = base.r > 0.5;

	vec3 col;
	if (mode == 0) {
		col = land ? vec3(0.35, 0.60, 0.32) : vec3(0.05, 0.16, 0.42);
	} else if (mode == 1) {
		float h = base.g * 1.3 - 0.2;
		col = height_color(h, land);
	} else if (mode == 2) {
		col = temp_to_color(texture(temp_tex, fuv).r);
	} else if (mode == 3) {
		col = pressure_color(texture(pressure_tex, fuv).r);
	} else if (mode == 4) {
		col = wind_color(texture(wind_tex, fuv).xyz);
	} else if (mode == 5) {
		col = hum_atm_color(texture(hum_atm_tex, fuv).r);
	} else if (mode == 6) {
		col = precip_color(texture(precip_tex, fuv).r);
	} else if (mode == 7) {
		col = cloud_color(texture(cloud_tex, fuv).r);
	} else if (mode == 8) {
		if (!land) col = vec3(0.05, 0.16, 0.42);
		else col = snow_color(texture(snow_tex, fuv).r);
	} else if (mode == 9) {
		if (!land) col = vec3(0.05, 0.16, 0.42);
		else col = soil_color(texture(soil_tex, fuv).r);
	} else if (mode == 10) {
		float h = base.g * 1.3 - 0.2;
		col = height_color(h, land);

		float river = texture(river_tex, fuv).r;
		if (river > 0.05) {
			vec3 river_col = mix(vec3(0.20, 0.45, 0.85),
			                     vec3(0.60, 0.85, 1.0),
			                     smoothstep(0.05, 0.9, river));
			col = mix(col, river_col, smoothstep(0.05, 0.3, river));
		}
	} else if (mode == 11) {
		if (!land) col = vec3(0.05, 0.16, 0.42);
		else col = veg_type_color(texture(veg_type_tex, fuv).r);
	} else if (mode == 12) {
		if (!land) col = vec3(0.05, 0.16, 0.42);
		else col = veg_density_color(texture(veg_density_tex, fuv).r);
	} else if (mode == 13) {
		col = temp_to_color(texture(temp_ema_tex, fuv).r);
	} else {
		col = vec3(0.5, 0.5, 0.5);
	}

	// ---- 昼夜遮罩 ----
	if (show_terminator) {
		vec3 dir = uv_to_dir(UV.x, UV.y, projection);
		if (dot(dir, dir) > 0.5) {
			float sun_dot = dot(dir, sun_dir);
			// sun_dot > 0：白天；< 0：夜晚
			// 在 0 附近做平滑过渡（0.08 宽度 = 晨昏线附近渐变带）
			float day_factor = smoothstep(-0.08, 0.08, sun_dot);
			float dark = 1.0 - night_darkness * (1.0 - day_factor);
			col *= dark;
		}
	}

	COLOR = vec4(col, 1.0);
}