shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform sampler2D field_tex : filter_nearest, repeat_disable;
uniform sampler2D is_land_tex : filter_nearest, repeat_disable;
uniform ivec2 tex_size = ivec2(1024, 16);
uniform int mode = 0;    // 0=land 1=height 2=temp 3=precip 4=cloud 5=snow 6=hum_atm
uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform float night_brightness = 0.22;

varying flat float face_idx;
varying vec3 world_normal;

vec3 land_color(float v) {
    return (v > 0.5) ? vec3(0.35, 0.60, 0.32) : vec3(0.05, 0.16, 0.42);
}

vec3 height_color(float h, bool land) {
    if (!land) {
        float t = clamp(-h / 0.15, 0.0, 1.0);
        return mix(vec3(0.18,0.48,0.72), vec3(0.05,0.16,0.42), t);
    }
    float hh = clamp(h, 0.0, 0.55);
    if (hh < 0.05) return mix(vec3(0.86,0.80,0.58), vec3(0.42,0.68,0.35), hh/0.05);
    if (hh < 0.12) return mix(vec3(0.42,0.68,0.35), vec3(0.30,0.55,0.28), (hh-0.05)/0.07);
    if (hh < 0.22) return mix(vec3(0.30,0.55,0.28), vec3(0.50,0.55,0.30), (hh-0.12)/0.10);
    if (hh < 0.32) return mix(vec3(0.50,0.55,0.30), vec3(0.60,0.50,0.30), (hh-0.22)/0.10);
    if (hh < 0.45) return mix(vec3(0.60,0.50,0.30), vec3(0.65,0.60,0.58), (hh-0.32)/0.13);
    return mix(vec3(0.65,0.60,0.58), vec3(0.95,0.96,0.98), clamp((hh-0.45)/0.10, 0.0, 1.0));
}

vec3 temp_color(float t) {
    float tc = clamp(t, -0.1, 1.1);
    if (tc < 0.20) return mix(vec3(0.05,0.10,0.40), vec3(0.10,0.35,0.75), tc/0.20);
    if (tc < 0.40) return mix(vec3(0.10,0.35,0.75), vec3(0.20,0.75,0.80), (tc-0.20)/0.20);
    if (tc < 0.60) return mix(vec3(0.20,0.75,0.80), vec3(0.55,0.85,0.30), (tc-0.40)/0.20);
    if (tc < 0.80) return mix(vec3(0.55,0.85,0.30), vec3(0.95,0.75,0.20), (tc-0.60)/0.20);
    return mix(vec3(0.95,0.75,0.20), vec3(0.85,0.15,0.10), (tc-0.80)/0.30);
}

vec3 precip_color(float p) {
    float t = clamp(p * 50.0, 0.0, 1.0);
    if (t < 0.01) return vec3(0.04, 0.04, 0.06);
    if (t < 0.25) return mix(vec3(0.10,0.15,0.35), vec3(0.20,0.30,0.65), t*4.0);
    if (t < 0.55) return mix(vec3(0.20,0.30,0.65), vec3(0.55,0.40,0.85), (t-0.25)/0.30);
    if (t < 0.85) return mix(vec3(0.55,0.40,0.85), vec3(0.85,0.60,0.95), (t-0.55)/0.30);
    return mix(vec3(0.85,0.60,0.95), vec3(1.0,0.95,1.0), (t-0.85)/0.15);
}

vec3 cloud_color(float c) {
    float t = clamp(c, 0.0, 1.0);
    if (t < 0.3) return mix(vec3(0.15,0.18,0.25), vec3(0.55,0.60,0.70), t/0.3);
    if (t < 0.7) return mix(vec3(0.55,0.60,0.70), vec3(0.92,0.95,1.0), (t-0.3)/0.4);
    return mix(vec3(0.92,0.95,1.0), vec3(0.60,0.65,0.75), (t-0.7)/0.3);
}

vec3 snow_color(float s) {
    float t = clamp(s * 5.0, 0.0, 1.0);
    if (t < 0.02) return vec3(0.10, 0.12, 0.18);
    if (t < 0.3) return mix(vec3(0.20,0.30,0.45), vec3(0.55,0.65,0.80), t/0.3);
    if (t < 0.7) return mix(vec3(0.55,0.65,0.80), vec3(0.90,0.94,1.0), (t-0.3)/0.4);
    return mix(vec3(0.90,0.94,1.0), vec3(1.0,1.0,1.0), (t-0.7)/0.3);
}

vec3 hum_atm_color(float h) {
    float t = clamp(h, 0.0, 1.0);
    if (t < 0.5) return mix(vec3(0.75,0.65,0.35), vec3(0.30,0.65,0.75), t*2.0);
    return mix(vec3(0.30,0.65,0.75), vec3(0.05,0.15,0.55), (t-0.5)*2.0);
}

vec3 temp_ema_color(float t) {
    return temp_color(t);
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
    if (t < 0.3) return mix(vec3(0.55,0.50,0.42), vec3(0.62,0.65,0.40), t/0.3);
    if (t < 0.7) return mix(vec3(0.62,0.65,0.40), vec3(0.35,0.68,0.32), (t-0.3)/0.4);
    return mix(vec3(0.35,0.68,0.32), vec3(0.08,0.42,0.14), (t-0.7)/0.3);
}

void vertex() {
    face_idx = UV.x;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    int fi = int(face_idx);
    int tx = fi % tex_size.x;
    int ty = fi / tex_size.x;
    vec2 uv = vec2(
        (float(tx) + 0.5) / float(tex_size.x),
        (float(ty) + 0.5) / float(tex_size.y)
    );

    float v = texture(field_tex, uv).r;
    float land_v = texture(is_land_tex, uv).r;
    bool land = land_v > 0.5;

    vec3 col;
    if (mode == 0) {
        col = land_color(v);
    } else if (mode == 1) {
        col = height_color(v, land);
    } else if (mode == 2) {
        col = temp_color(v);
        float d = dot(normalize(world_normal), sun_dir);
        float day = smoothstep(-0.20, 0.20, d);
        col *= mix(night_brightness, 1.0, day);
    } else if (mode == 3) {
        col = precip_color(v);
    } else if (mode == 4) {
        col = cloud_color(v);
    } else if (mode == 5) {
        col = land ? snow_color(v) : vec3(0.05, 0.16, 0.42);
    } else if (mode == 6) {
        col = hum_atm_color(v);
    } else if (mode == 7) {
        col = land ? veg_type_color(v) : vec3(0.05, 0.16, 0.42);
    } else if (mode == 8) {
        col = land ? veg_density_color(v) : vec3(0.05, 0.16, 0.42);
    } else if (mode == 9) {
        col = temp_ema_color(v);
    } else {
        col = vec3(0.5, 0.5, 0.5);
    }

    ALBEDO = col;
}