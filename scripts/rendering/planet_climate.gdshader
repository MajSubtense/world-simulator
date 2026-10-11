shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform sampler2D field_tex : filter_nearest, repeat_disable;
uniform sampler2D is_land_tex : filter_nearest, repeat_disable;
uniform ivec2 tex_size = ivec2(1024, 16);
uniform int mode = 0;    // 0=land 1=height 2=climate
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
    } else {
        col = temp_color(v);
        float d = dot(normalize(world_normal), sun_dir);
        float day = smoothstep(-0.20, 0.20, d);
        float brightness = mix(night_brightness, 1.0, day);
        col *= brightness;
    }

    ALBEDO = col;
}