class_name ShadersWater
extends RefCounted
## 水循环 shader。
##
## ★ 如果你要修改云 / 降水行为，只需要改这个文件。
##
## 数据流（每 tick）：
##   EVAPORATE   ：soil → hum_atm（蒸发），temp -= 潜热
##   OROGRAPHIC  ：hum_atm → soil（地形降水），precip +=
##   CONDENSE    ：hum_atm → cloud → precip → soil → river_in
##                 + 温度 < 0 → snow；温度 > 0 → melt → river_in
##
## GPU buffer 绑定约定（见 GpuClimate._create_uniform_sets）：
##   hum_atm / soil / temp / precip / cloud / snow / river_in
##
## 参数来自 ClimateConfig：
##   蒸发：evap_rate_ocean / evap_rate_land / latent_heat
##   云化：cloud_form_rate / cloud_decay / cloud_threshold
##   降水：release_rate / orographic_factor / latent_heat_release
##   饱和：sat_base / sat_temp_factor
##   雪/土壤：melt_rate / runoff_ratio / baseflow_rate

const EVAPORATE := """
#version 450
layout(local_size_x = 64) in;

layout(set=0, binding=0, std430) readonly buffer IsLand { int data[]; } is_land;
layout(set=0, binding=1, std430) readonly buffer Normals { vec4 data[]; } normals;
layout(set=0, binding=2, std430) buffer Soil { float data[]; } soil;
layout(set=0, binding=3, std430) buffer HumAtm { float data[]; } hum_atm;
layout(set=0, binding=4, std430) buffer Temp { float data[]; } temp;
layout(set=0, binding=5, std430) readonly buffer Params {
    vec4 sun_dir;
    float evap_rate_ocean;
    float evap_rate_land;
    float latent_heat;
    float sat_base;
    float sat_temp_factor;
    float pad0;
    float pad1;
    float pad2;
} p;

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= hum_atm.data.length()) return;

    float t = max(temp.data[id], 0.05);
    float ha = hum_atm.data[id];
    float sat = max(p.sat_base * exp(p.sat_temp_factor * t), 0.05);

    float lat = asin(clamp(normals.data[id].y, -1.0, 1.0));
    bool rising = cos(6.0 * lat) > 0.0;

    float evap = 0.0;
    if (is_land.data[id] == 0) {
        float target_rh = rising ? 0.92 : 0.35;
        evap = (sat * target_rh - ha) * p.evap_rate_ocean;
        hum_atm.data[id] = ha + evap;
    } else {
        float target_rh = rising ? 0.65 : 0.25;
        float deficit = sat * target_rh - ha;
        if (deficit > 0.0) {
            float sw = soil.data[id];
            evap = min(deficit * p.evap_rate_land, sw * 0.05);
            soil.data[id] = sw - evap;
            hum_atm.data[id] = ha + evap;
        }
    }
    temp.data[id] = t - max(evap, 0.0) * p.latent_heat;
}
"""

const OROGRAPHIC := """
#version 450
layout(local_size_x = 64) in;

layout(set=0, binding=0, std430) readonly buffer Neighbors { int data[]; } nb;
layout(set=0, binding=1, std430) readonly buffer EdgeDirs { vec4 data[]; } ed;
layout(set=0, binding=2, std430) readonly buffer Elev { float data[]; } elev;
layout(set=0, binding=3, std430) readonly buffer Wind { vec4 data[]; } wind;
layout(set=0, binding=4, std430) readonly buffer IsLand { int data[]; } is_land;
layout(set=0, binding=5, std430) buffer HumAtm { float data[]; } hum_atm;
layout(set=0, binding=6, std430) buffer Soil { float data[]; } soil;
layout(set=0, binding=7, std430) buffer Temp { float data[]; } temp;
layout(set=0, binding=8, std430) buffer Precip { float data[]; } precip;
layout(set=0, binding=9, std430) readonly buffer Params {
    float orographic_factor;
    float latent_heat_release;
    float sat_base;
    float sat_temp_factor;
} p;

void main() {
    uint f = gl_GlobalInvocationID.x;
    if (f >= hum_atm.data.length()) return;
    if (is_land.data[f] == 0) return;

    vec3 w = wind.data[f].xyz;
    float my_elev = elev.data[f];
    float ha = hum_atm.data[f];
    float t = temp.data[f];
    int base = int(f) * 6;

    float uplift = 0.0;
    for (int s = 0; s < 6; s++) {
        int n = nb.data[base + s];
        if (n < 0) continue;
        vec3 e = ed.data[base + s].xyz;
        float v = -dot(w, e);
        if (v <= 0.0) continue;
        float dh = my_elev - elev.data[n];
        if (dh > 0.0) uplift += v * dh;
    }

    float sat = max(p.sat_base * exp(p.sat_temp_factor * t), 0.05);
    float RH = ha / sat;
    float precip_here = 0.0;
    if (RH > 1.0 && uplift > 0.0) {
        precip_here = uplift * p.orographic_factor * ha * (RH - 1.0);
        precip_here = min(precip_here, ha * 0.10);
    }

    hum_atm.data[f] = ha - precip_here;
    soil.data[f] += precip_here;
    temp.data[f] += precip_here * p.latent_heat_release;
    precip.data[f] += precip_here;
}
"""

const CONDENSE := """
#version 450
layout(local_size_x = 64) in;

layout(set=0, binding=0, std430) readonly buffer Normals { vec4 data[]; } normals;
layout(set=0, binding=1, std430) readonly buffer IsLand { int data[]; } is_land;
layout(set=0, binding=2, std430) readonly buffer Elev { float data[]; } elev;
layout(set=0, binding=3, std430) buffer HumAtm { float data[]; } hum_atm;
layout(set=0, binding=4, std430) buffer Soil { float data[]; } soil;
layout(set=0, binding=5, std430) buffer Temp { float data[]; } temp;
layout(set=0, binding=6, std430) buffer Precip { float data[]; } precip;
layout(set=0, binding=7, std430) buffer Cloud { float data[]; } cloud;
layout(set=0, binding=8, std430) buffer Snow { float data[]; } snow;
layout(set=0, binding=9, std430) buffer RiverIn { float data[]; } river_in;
layout(set=0, binding=10, std430) readonly buffer Params {
    vec4 sun_dir;
    float sat_base;
    float sat_temp_factor;
    float cloud_form_rate;
    float cloud_decay;
    float cloud_threshold;
    float release_rate;
    float latent_heat_release;
    float dt;
    float melt_rate;
    float runoff_ratio;
    float baseflow_rate;
    float pad0;
} p;

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= hum_atm.data.length()) return;

    bool land = is_land.data[id] == 1;
    float t = max(temp.data[id], 0.05);
    float ha = hum_atm.data[id];
    float c = cloud.data[id];
    float sat = max(p.sat_base * exp(p.sat_temp_factor * t), 0.05);
    float RH = ha / sat;

    // ITCZ 随太阳直射点偏移
    float lat_sun = asin(clamp(p.sun_dir.y, -1.0, 1.0));
    float lat = asin(clamp(normals.data[id].y, -1.0, 1.0));
    float lat_rel = lat - lat_sun * 0.7;
    float w_vert = cos(4.0 * lat_rel);

    // 云化：只在上升带 + 相对湿度 > 0.80
    float cloud_gain = 0.0;
    if (RH > 0.80 && w_vert > 0.0) {
        float alt = 1.0 / (1.0 + max(elev.data[id], 0.0) * 2.0);
        cloud_gain = (RH - 0.80) * sat * p.cloud_form_rate * alt * p.dt;
    }
    ha -= cloud_gain;
    c += cloud_gain;

    // 云衰减
    float decay = c * p.cloud_decay * p.dt;
    c -= decay;
    ha += decay;

    // 持续降水：只释放超出阈值的部分
    float threshold = p.cloud_threshold * (land ? 1.0 : 1.5);
    if (w_vert < 0.0) threshold *= 3.0;

    float precip_here = 0.0;
    if (c > threshold) {
        float excess = c - threshold;
        float alt = 1.0 / (1.0 + max(elev.data[id], 0.0) * 2.0);
        precip_here = excess * 0.15 * alt;
        c -= precip_here;
    }

    hum_atm.data[id] = ha;
    cloud.data[id] = c;
    precip.data[id] = precip_here;
    temp.data[id] = t + precip_here * p.latent_heat_release;

    // 雪 / 土壤 / 河流
    if (land) {
        float s = snow.data[id];
        float w = soil.data[id];
        float river = 0.0;

        // 极地霜降
        if (t < -0.05 && ha > 0.1) {
            float frost = (ha - 0.1) * 0.005;
            s += frost;
            ha -= frost;
            hum_atm.data[id] = ha;
        }

        if (t < 0.0 && precip_here > 0.0) {
            s += precip_here;
            precip_here = 0.0;
        } else if (t > 0.0 && s > 0.0) {
            float melt = min(s, p.melt_rate * t * p.dt);
            s -= melt;
            river += melt;
        }

        float runoff = precip_here * p.runoff_ratio;
        float infiltration = precip_here * (1.0 - p.runoff_ratio);
        w += infiltration;
        float baseflow = w * p.baseflow_rate;
        w -= baseflow;
        river += runoff + baseflow;

        snow.data[id] = s;
        soil.data[id] = w;
        river_in.data[id] = river;
    } else {
        snow.data[id] = 0.0;
        soil.data[id] = 0.0;
        river_in.data[id] = 0.0;
    }
}
"""