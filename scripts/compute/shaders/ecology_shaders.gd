class_name EcologyShaders
extends RefCounted
## 生态层 shader：从气候推导潜在植被，更新实际密度。
##
## 输入温度用的是 EMA 平滑温度（temp_ema），不是瞬时温度。
## 这样昼夜振荡不会导致植被类型在一天内反复切换。

const ECOLOGY := """
#version 450
layout(local_size_x = 64) in;

layout(set=0, binding=0, std430) readonly buffer Temp { float data[]; } temp;
layout(set=0, binding=1, std430) readonly buffer HumAtm { float data[]; } hum_atm;
layout(set=0, binding=2, std430) readonly buffer Elev { float data[]; } elev;
layout(set=0, binding=3, std430) readonly buffer IsLand { int data[]; } is_land;

layout(set=0, binding=4, std430) buffer VegPotential { float data[]; } veg_pot;
layout(set=0, binding=5, std430) buffer VegDensity { float data[]; } veg_den;
layout(set=0, binding=6, std430) buffer TempEma { float data[]; } temp_ema;

layout(set=0, binding=7, std430) readonly buffer Params {
    float recovery_rate;
    float density_scale;
    float temp_ema_rate;
    float pad0;
} p;

// 类型编码：
//   0 = 荒地    1 = 冰盖    2 = 苔原    3 = 针叶林
//   4 = 温带草原 5 = 温带阔叶 6 = 地中海灌木 7 = 沙漠
//   8 = 稀树草原 9 = 热带雨林 10 = 湿地

float max_density_for_type(float t) {
    if (t < 0.5)  return 0.0;
    if (t < 1.5)  return 0.0;
    if (t < 2.5)  return 0.3;
    if (t < 3.5)  return 0.8;
    if (t < 4.5)  return 0.5;
    if (t < 5.5)  return 0.9;
    if (t < 6.5)  return 0.4;
    if (t < 7.5)  return 0.05;
    if (t < 8.5)  return 0.6;
    if (t < 9.5)  return 1.0;
    return 0.7;
}

float compute_potential_veg(float t, float hum, float elev_v, float land) {
    if (land < 0.5) return 0.0;
    if (t < -0.10) return 1.0;
    if (t < 0.00) return 2.0;

    float alt_adj = t - clamp(elev_v * 0.25, 0.0, 0.20);
    if (alt_adj < 0.0) return 1.0;
    if (alt_adj < 0.10) return 2.0;

    if (hum < 0.20) return 7.0;

    if (t > 0.60) {
        if (hum > 0.55) return 9.0;
        if (hum > 0.40) return 8.0;
        return 7.0;
    }
    if (t > 0.35) {
        if (hum > 0.55) return 5.0;
        if (hum > 0.40) return 4.0;
        return 6.0;
    }
    if (hum > 0.45) return 3.0;
    return 4.0;
}

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= temp.data.length()) return;

    float t_inst = temp.data[id];
    float t_ema = temp_ema.data[id];
    // EMA 更新：向瞬时温度靠拢
    t_ema = t_ema + (t_inst - t_ema) * p.temp_ema_rate;
    temp_ema.data[id] = t_ema;

    float hum = hum_atm.data[id];
    float ev = elev.data[id];
    float land = float(is_land.data[id]);

    // 用 EMA 温度判定植被类型
    float pot = compute_potential_veg(t_ema, hum, ev, land);
    veg_pot.data[id] = pot;

    float max_d = max_density_for_type(pot) * p.density_scale;
    float cur = veg_den.data[id];
    float rate = clamp(p.recovery_rate, 0.0, 1.0);
    veg_den.data[id] = cur + (max_d - cur) * rate;
}
"""