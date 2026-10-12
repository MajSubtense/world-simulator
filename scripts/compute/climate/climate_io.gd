class_name ClimateIO
extends RefCounted
## CPU↔GPU 编解码。
## 上传参数、回读数据、解码到 Packed 数组。
##
## 只依赖 ClimateBuffers 具名访问器，不依赖 PlanetData。
## 不写回 PlanetData —— 写回由 ClimateEngine 做。

var rd: RenderingDevice
var buffers: ClimateBuffers
var N: int = 0

static func create(rendering_device: RenderingDevice, b: ClimateBuffers) -> ClimateIO:
	var io := ClimateIO.new()
	io.rd = rendering_device
	io.buffers = b
	io.N = b.N
	return io

# ============================================================
#  回读 + 解码
# ============================================================

func read_temperature() -> PackedFloat32Array:
	return rd.buffer_get_data(buffers.temp()).to_float32_array()

func read_pressure() -> PackedFloat32Array:
	return rd.buffer_get_data(buffers.pressure()).to_float32_array()

func read_wind() -> PackedVector3Array:
	var wf := rd.buffer_get_data(buffers.wind()).to_float32_array()
	var out := PackedVector3Array(); out.resize(N)
	for i in N:
		out[i] = Vector3(wf[i * 4], wf[i * 4 + 1], wf[i * 4 + 2])
	return out

func read_hum_atm() -> PackedFloat32Array:
	return rd.buffer_get_data(buffers.hum_atm()).to_float32_array()

func read_precip() -> PackedFloat32Array:
	return rd.buffer_get_data(buffers.precip()).to_float32_array()

func read_cloud() -> PackedFloat32Array:
	return rd.buffer_get_data(buffers.cloud()).to_float32_array()

func read_snow() -> PackedFloat32Array:
	return rd.buffer_get_data(buffers.snow()).to_float32_array()

func read_soil() -> PackedFloat32Array:
	return rd.buffer_get_data(buffers.soil()).to_float32_array()

func read_river_input() -> PackedFloat32Array:
	return rd.buffer_get_data(buffers.river_input()).to_float32_array()

func read_veg_potential() -> PackedFloat32Array:
	return rd.buffer_get_data(buffers.veg_potential()).to_float32_array()

func read_veg_density() -> PackedFloat32Array:
	return rd.buffer_get_data(buffers.veg_density()).to_float32_array()

func read_flow_dir() -> PackedInt32Array:
	return rd.buffer_get_data(buffers.flow_dir()).to_int32_array()

func read_flow(substeps: int) -> PackedFloat32Array:
	var target: RID = buffers.flow_out_a() if (substeps % 2 == 0) else buffers.flow_out_b()
	return rd.buffer_get_data(target).to_float32_array()

func read_temp_ema() -> PackedFloat32Array:
	return rd.buffer_get_data(buffers.temp_ema()).to_float32_array()