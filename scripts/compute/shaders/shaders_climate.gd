class_name ShadersClimate
extends RefCounted
## 气候基础 shader：太阳、气压、风、平流、扩散、拷贝。
## 云/降水 → shaders_water.gd；河流 → shaders_river.gd。

const SOLAR := """
#version 450
layout(local_size_x = 64) in;

layout(set=0, binding=0, std430) readonly buffer Normals { vec4 data[]; } normals;
layout(set=0, binding=1, std430) readonly buffer HeatCap { float data[]; } heat_cap;
layout(set=0, binding=2, std430) readonly buffer BaseTemp { float data[]; } base_temp;
layout(set=0, binding=3, std430) readonly buffer Elev { float data[]; } elev;
layout(set=0, binding=4, std430) buffer Temp { float data[]; } temp;
layout(set=0, binding=5, std430) readonly buffer Params {
    vec4 sun_dir;
    float dt;
    float solar_abs;
    float thermal_emit;
    float base_relax;
    float lapse_rate;
    float pad0;
    float pad1;
    float pad2;
} p;

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= temp.data.length()) return;
    vec3 n = normals.data[id].xyz;
    float solar = max(dot(n, p.sun_dir.xyz), 0.0);
    float cap = heat_cap.data[id];
    float t = temp.data[id];
    float absorb = solar * p.solar_abs;
    float emit = t * p.thermal_emit;
    float target = base_temp.data[id] - elev.data[id] * p.lapse_rate;
    float pull = (target - t) * p.base_relax;
    t += (absorb - emit + pull) * cap * p.dt;
    t = clamp(t, -0.5, 1.5);
    temp.data[id] = t;
}
"""

const PRESSURE := """
#version 450
layout(local_size_x = 64) in;

layout(set=0, binding=0, std430) readonly buffer Temp { float data[]; } temp;
layout(set=0, binding=1, std430) readonly buffer Elev { float data[]; } elev;
layout(set=0, binding=2, std430) readonly buffer Normals { vec4 data[]; } normals;
layout(set=0, binding=3, std430) buffer Pressure { float data[]; } pressure;
layout(set=0, binding=4, std430) readonly buffer Params {
    vec4 sun_dir;
    float circulation_amp;
    float pad0;
    float pad1;
    float pad2;
} p;

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= temp.data.length()) return;
    float p_thermal = -temp.data[id] - elev.data[id] * 0.5;
    float lat = asin(clamp(normals.data[id].y, -1.0, 1.0));
    float p_band = -cos(6.0 * lat) * p.circulation_amp;
    pressure.data[id] = p_thermal + p_band;
}
"""

const WIND := """
#version 450
layout(local_size_x = 64) in;

layout(set=0, binding=0, std430) readonly buffer Neighbors { int data[]; } nb;
layout(set=0, binding=1, std430) readonly buffer EdgeDirs { vec4 data[]; } ed;
layout(set=0, binding=2, std430) readonly buffer Pressure { float data[]; } pressure;
layout(set=0, binding=3, std430) buffer Wind { vec4 data[]; } wind;
layout(set=0, binding=4, std430) readonly buffer Params { float scale; } p;

void main() {
    uint f = gl_GlobalInvocationID.x;
    if (f >= pressure.data.length()) return;
    float pf = pressure.data[f];
    int base = int(f) * 6;
    vec3 grad = vec3(0.0);
    for (int s = 0; s < 6; s++) {
        int n = nb.data[base + s];
        if (n < 0) continue;
        vec3 e = ed.data[base + s].xyz;
        grad += e * (pressure.data[n] - pf);
    }
    vec3 w = -grad * p.scale;
    wind.data[f] = vec4(w, length(w));
}
"""

const ADVECT := """
#version 450
layout(local_size_x = 64) in;

layout(set=0, binding=0, std430) readonly buffer Neighbors { int data[]; } nb;
layout(set=0, binding=1, std430) readonly buffer EdgeDirs { vec4 data[]; } ed;
layout(set=0, binding=2, std430) readonly buffer Wind { vec4 data[]; } wind;
layout(set=0, binding=3, std430) readonly buffer Src { float data[]; } src;
layout(set=0, binding=4, std430) buffer Dst { float data[]; } dst;
layout(set=0, binding=5, std430) readonly buffer Params { float k; } p;

void main() {
    uint f = gl_GlobalInvocationID.x;
    if (f >= src.data.length()) return;
    vec3 w = wind.data[f].xyz;
    float vf = src.data[f];
    int base = int(f) * 6;
    float flux = 0.0;
    for (int s = 0; s < 6; s++) {
        int n = nb.data[base + s];
        if (n < 0) continue;
        vec3 e = ed.data[base + s].xyz;
        float vn_out = dot(w, e);
        if (vn_out > 0.0) {
            flux -= vn_out * vf;
        } else {
            flux -= vn_out * src.data[n];
        }
    }
    dst.data[f] = vf + p.k * flux;
}
"""

const DIFFUSE := """
#version 450
layout(local_size_x = 64) in;

layout(set=0, binding=0, std430) readonly buffer Neighbors { int data[]; } nb;
layout(set=0, binding=1, std430) readonly buffer Src { float data[]; } src;
layout(set=0, binding=2, std430) buffer Dst { float data[]; } dst;
layout(set=0, binding=3, std430) readonly buffer Params { float d; } p;

void main() {
    uint f = gl_GlobalInvocationID.x;
    if (f >= src.data.length()) return;
    float vf = src.data[f];
    int base = int(f) * 6;
    float sum = 0.0;
    int cnt = 0;
    for (int s = 0; s < 6; s++) {
        int n = nb.data[base + s];
        if (n < 0) continue;
        sum += src.data[n] - vf;
        cnt += 1;
    }
    dst.data[f] = (cnt > 0) ? (vf + p.d * sum / float(cnt)) : vf;
}
"""

const COPY := """
#version 450
layout(local_size_x = 64) in;

layout(set=0, binding=0, std430) readonly buffer Src { float data[]; } src;
layout(set=0, binding=1, std430) buffer Dst { float data[]; } dst;

void main() {
    uint i = gl_GlobalInvocationID.x;
    if (i >= src.data.length()) return;
    dst.data[i] = src.data[i];
}
"""