class_name RiverShaders
extends RefCounted
## 河流 shader：流向 + 延迟传播。

const RIVER_FLOW := """
#version 450
layout(local_size_x = 64) in;

layout(set=0, binding=0, std430) readonly buffer Neighbors { int data[]; } nb;
layout(set=0, binding=1, std430) readonly buffer Elev { float data[]; } elev;
layout(set=0, binding=2, std430) readonly buffer IsLand { int data[]; } is_land;
layout(set=0, binding=3, std430) buffer FlowDir { int data[]; } flow_dir;
layout(set=0, binding=4, std430) readonly buffer LandScore { float data[]; } land_score;

void main() {
    uint f = gl_GlobalInvocationID.x;
    if (f >= elev.data.length()) return;
    if (is_land.data[f] == 0) { flow_dir.data[f] = -1; return; }

    float my_score = land_score.data[f];
    int base = int(f) * 6;
    int best = -1;
    float best_score = my_score - 0.0001;

    for (int s = 0; s < 6; s++) {
        int n = nb.data[base + s];
        if (n < 0) continue;
        if (is_land.data[n] == 0) { best = n; best_score = -1.0; break; }
        float ns = land_score.data[n];
        if (ns < best_score) { best_score = ns; best = n; }
    }
    flow_dir.data[f] = best;
}
"""

const RIVER_STEP := """
#version 450
layout(local_size_x = 64) in;

layout(set=0, binding=0, std430) readonly buffer Neighbors { int data[]; } nb;
layout(set=0, binding=1, std430) readonly buffer FlowDir { int data[]; } flow_dir;
layout(set=0, binding=2, std430) readonly buffer IsLand { int data[]; } is_land;
layout(set=0, binding=3, std430) readonly buffer RiverInput { float data[]; } river_in;
layout(set=0, binding=4, std430) readonly buffer StorageIn { float data[]; } st_in;
layout(set=0, binding=5, std430) readonly buffer FlowOutIn { float data[]; } fo_in;
layout(set=0, binding=6, std430) buffer StorageOut { float data[]; } st_out;
layout(set=0, binding=7, std430) buffer FlowOutOut { float data[]; } fo_out;
layout(set=0, binding=8, std430) readonly buffer Params {
    float flow_rate;
    float input_frac;
    float pad0;
    float pad1;
} p;

void main() {
    uint f = gl_GlobalInvocationID.x;
    if (f >= st_in.data.length()) return;
    if (is_land.data[f] == 0) {
        st_out.data[f] = 0.0;
        fo_out.data[f] = 0.0;
        return;
    }

    float st = st_in.data[f] + river_in.data[f] * 1000.0 * p.input_frac;
    int base = int(f) * 6;
    for (int s = 0; s < 6; s++) {
        int n = nb.data[base + s];
        if (n < 0) continue;
        if (flow_dir.data[n] == int(f)) st += fo_in.data[n];
    }

    float out_v = st * p.flow_rate;
    if (out_v > st) out_v = st;
    st -= out_v;

    st_out.data[f] = st;
    fo_out.data[f] = fo_in.data[f] + out_v;
}
"""