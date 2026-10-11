class_name MapBakerGpu
extends RefCounted
## GPU 地图烘焙。地图的每个像素从 data.f_is_land_face / f_elevation 读取，
## 保证与 3D 球体、气候数据完全一致。

var face_lookup: FaceLookup
var rd: RenderingDevice

var _shader: RID
var _pipeline: RID
var _params_buffer: RID
var _grid_offsets: RID
var _grid_faces: RID
var _normals_buffer: RID

var _N: int = 0
var _initialized: bool = false

const GRID_LON := 32
const GRID_LAT := 16

const SHADER := """
#version 450
layout(local_size_x = 8, local_size_y = 8) in;

layout(set=0, binding=0, std430) readonly buffer Params {
    ivec4 data;
} P;

layout(set=0, binding=1, std430) readonly buffer GridOffsets { int data[]; } grid_off;
layout(set=0, binding=2, std430) readonly buffer GridFaces   { int data[]; } grid_fc;
layout(set=0, binding=3, std430) readonly buffer Normals     { vec4 data[]; } nrm;
layout(set=0, binding=4, std430) readonly buffer IsLand      { int data[]; } is_land;
layout(set=0, binding=5, std430) readonly buffer Elev        { float data[]; } elev;

layout(set=0, binding=6, rgba8) uniform restrict writeonly image2D out_base;
layout(set=0, binding=7, rgba8) uniform restrict writeonly image2D out_face;

const int GLON = 32;
const int GLAT = 16;

vec3 uv_to_dir(float u, float v, int proj) {
    if (proj == 0) {
        float lon = (u - 0.5) * 6.2831853;
        float lat = (0.5 - v) * 3.14159265;
        float cl = cos(lat);
        return vec3(cl * cos(lon), sin(lat), cl * sin(lon));
    }
    float mx = (u - 0.5) * 2.0;
    float my = (0.5 - v);
    if (mx*mx + 4.0*my*my > 1.0) return vec3(0.0);
    float theta = asin(clamp(my * 2.0, -1.0, 1.0));
    float phi_term = (2.0*theta + sin(2.0*theta)) / 3.14159265;
    float phi = asin(clamp(phi_term, -1.0, 1.0));
    float ct = cos(theta);
    float lam = (abs(ct) > 0.001) ? 3.14159265 * mx / ct : 0.0;
    float cl = cos(phi);
    return vec3(cl * cos(lam), sin(phi), cl * sin(lam));
}

int find_face(vec3 dir) {
    float lon = atan(dir.z, dir.x);
    int lc = int((lon + 3.14159265) / 6.2831853 * float(GLON));
    lc = ((lc % GLON) + GLON) % GLON;
    float lat = asin(clamp(dir.y, -1.0, 1.0));
    int rc = clamp(int((lat + 1.5707963) / 3.14159265 * float(GLAT)), 0, GLAT - 1);

    int best = -1;
    float best_dot = -2.0;
    for (int dr = -2; dr <= 2; dr++) {
        int r = rc + dr;
        if (r < 0 || r >= GLAT) continue;
        for (int dl = -2; dl <= 2; dl++) {
            int l = ((lc + dl) % GLON + GLON) % GLON;
            int key = r * GLON + l;
            int s = grid_off.data[key];
            int e = grid_off.data[key + 1];
            for (int i = s; i < e; i++) {
                int ff = grid_fc.data[i];
                float d = dot(nrm.data[ff].xyz, dir);
                if (d > best_dot) { best_dot = d; best = ff; }
            }
        }
    }
    return best;
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    int w = P.data.x;
    int h = P.data.y;
    if (coord.x >= w || coord.y >= h) return;

    float u = (float(coord.x) + 0.5) / float(w);
    float v = (float(coord.y) + 0.5) / float(h);

    vec3 dir = uv_to_dir(u, v, P.data.z);
    if (dot(dir, dir) < 0.5) {
        imageStore(out_base, coord, vec4(0.0));
        imageStore(out_face, coord, vec4(0.0));
        return;
    }

    int face = find_face(dir);
    if (face < 0) {
        imageStore(out_base, coord, vec4(0.0));
        imageStore(out_face, coord, vec4(0.0));
        return;
    }

    int land_flag = is_land.data[face];
    float height_v = elev.data[face];

    // base_tex：R=land(0/1)，G=elevation 编码到 [0,1]
    //   编码：g = (h + 0.2) / 1.3  ；解码：h = g * 1.3 - 0.2
    float hh = clamp((height_v + 0.2) / 1.3, 0.0, 1.0);

    vec4 base;
    base.r = (land_flag == 1) ? 1.0 : 0.0;
    base.g = hh;
    base.b = 0.0;
    base.a = 1.0;

    // face_tex：24 位 face_id
    int r = face & 255;
    int g = (face >> 8) & 255;
    int b = (face >> 16) & 255;
    vec4 fc;
    fc.r = float(r) / 255.0;
    fc.g = float(g) / 255.0;
    fc.b = float(b) / 255.0;
    fc.a = 1.0;

    imageStore(out_base, coord, base);
    imageStore(out_face, coord, fc);
}
"""

# ============================================================
func setup(lookup: FaceLookup) -> bool:
	face_lookup = lookup
	_N = lookup.gp.face_count

	rd = RenderingServer.create_local_rendering_device()
	if rd == null:
		push_error("MapBakerGpu: RD 创建失败")
		return false

	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = SHADER
	var sp := rd.shader_compile_spirv_from_source(src)
	if sp == null or sp.compile_error_compute != "":
		push_error("MapBakerGpu shader: " + (sp.compile_error_compute if sp else "空"))
		return false
	_shader = rd.shader_create_from_spirv(sp)
	_pipeline = rd.compute_pipeline_create(_shader)

	var nm := PackedFloat32Array(); nm.resize(_N * 4)
	for i in _N:
		var v := lookup.gp.face_normals[i]
		nm[i*4] = v.x; nm[i*4+1] = v.y; nm[i*4+2] = v.z
	_normals_buffer = rd.storage_buffer_create(_N * 16, nm.to_byte_array())

	var packed := _pack_grid(lookup)
	_grid_offsets = rd.storage_buffer_create(packed["offsets"].size() * 4, packed["offsets"].to_byte_array())
	_grid_faces = rd.storage_buffer_create(packed["faces"].size() * 4, packed["faces"].to_byte_array())

	_params_buffer = rd.storage_buffer_create(16)

	_initialized = true
	return true

func _pack_grid(lookup: FaceLookup) -> Dictionary:
	var offsets := PackedInt32Array()
	var faces := PackedInt32Array()
	var total: int = 0
	offsets.resize(lookup._cells.size() + 1)
	for i in lookup._cells.size():
		offsets[i] = total
		for f in lookup._cells[i]:
			faces.append(f)
			total += 1
	offsets[lookup._cells.size()] = total
	return {"offsets": offsets, "faces": faces}

# ============================================================
#  Bake
# ============================================================
func bake(data: PlanetData, w: int, h: int, projection: int) -> Dictionary:
	if not _initialized:
		return {}

	var il := PackedInt32Array(); il.resize(_N)
	for i in _N:
		il[i] = data.f_is_land_face[i]
	var b_land := rd.storage_buffer_create(_N * 4, il.to_byte_array())
	var b_elev := rd.storage_buffer_create(_N * 4, data.f_elevation.to_byte_array())

	var params := PackedInt32Array([w, h, projection, _N])
	rd.buffer_update(_params_buffer, 0, 16, params.to_byte_array())

	var fmt := RDTextureFormat.new()
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.width = w
	fmt.height = h
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	var base_tex_rd := rd.texture_create(fmt, RDTextureView.new(), [])
	var face_tex_rd := rd.texture_create(fmt, RDTextureView.new(), [])

	var u0 := _make_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0, _params_buffer)
	var u1 := _make_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1, _grid_offsets)
	var u2 := _make_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2, _grid_faces)
	var u3 := _make_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 3, _normals_buffer)
	var u4 := _make_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 4, b_land)
	var u5 := _make_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 5, b_elev)
	var u6 := _make_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 6, base_tex_rd)
	var u7 := _make_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 7, face_tex_rd)

	var uset := rd.uniform_set_create([u0, u1, u2, u3, u4, u5, u6, u7], _shader, 0)

	var gx: int = int(ceil(float(w) / 8.0))
	var gy: int = int(ceil(float(h) / 8.0))
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	rd.compute_list_bind_uniform_set(cl, uset, 0)
	rd.compute_list_dispatch(cl, gx, gy, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()

	var base_data := rd.texture_get_data(base_tex_rd, 0)
	var face_data := rd.texture_get_data(face_tex_rd, 0)

	var base_img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, base_data)
	var face_img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, face_data)

	rd.free_rid(uset)
	rd.free_rid(base_tex_rd)
	rd.free_rid(face_tex_rd)
	rd.free_rid(b_land)
	rd.free_rid(b_elev)

	return {
		"base_texture": ImageTexture.create_from_image(base_img),
		"face_texture": ImageTexture.create_from_image(face_img),
	}

func _make_uniform(t: RenderingDevice.UniformType, binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = t
	u.binding = binding
	u.add_id(rid)
	return u