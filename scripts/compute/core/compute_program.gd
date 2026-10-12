class_name ComputeProgram
extends RefCounted
## 一个计算着色器程序：编译 GLSL → 创建 pipeline → 缓存 uniform set。
##
## 用法：
##   var prog := ComputeProgram.compile(rd, SHADER_SOURCE, "climate")
##   var cl := rd.compute_list_begin()
##   rd.compute_list_bind_compute_pipeline(cl, prog.pipeline)
##   rd.compute_list_bind_uniform_set(cl, us, 0)
##   rd.compute_list_dispatch(cl, groups, 1, 1)
##   rd.compute_list_end()
##
## 释放：
##   prog.free()
##
## 若外部重建了某个 buffer 的 RID，需要调用 clear_set_cache()
## 让缓存的 uniform set 失效。

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var name: String = ""
var _cached_sets: Dictionary = {}  # key: String → RID

## 编译 GLSL 源，返回 ComputeProgram。失败返回 null。
static func compile(
		rendering_device: RenderingDevice,
		source: String,
		prog_name: String) -> ComputeProgram:
	if rendering_device == null:
		push_error("[ComputeProgram:%s] rd == null" % prog_name)
		return null
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = source
	var spirv := rendering_device.shader_compile_spirv_from_source(src)
	if spirv == null or spirv.compile_error_compute != "":
		var err := spirv.compile_error_compute if spirv else "null spirv"
		push_error("[ComputeProgram:%s] %s" % [prog_name, err])
		return null
	var p := ComputeProgram.new()
	p.rd = rendering_device
	p.name = prog_name
	p.shader = rendering_device.shader_create_from_spirv(spirv)
	p.pipeline = rendering_device.compute_pipeline_create(p.shader)
	return p

## 创建或取回缓存的 uniform set。
## buffers 是 ComputeBuffers 里的 StringName 列表，按 binding 顺序 0,1,2,...
## 若需混入外部 RID，请直接调 rd.uniform_set_create。
func get_or_create_set(key: String, buffers: ComputeBuffers, names: Array) -> RID:
	if _cached_sets.has(key):
		return _cached_sets[key]
	var us := _make_uniform_set(buffers, names)
	if us == RID():
		return RID()
	_cached_sets[key] = us
	return us

## buffer 重建后调用，让 uniform set 缓存失效。
func clear_set_cache() -> void:
	for us in _cached_sets.values():
		if us != RID():
			rd.free_rid(us)
	_cached_sets.clear()

## 释放所有 uniform set + pipeline + shader。
func dispose() -> void:
	clear_set_cache()
	if pipeline != RID():
		rd.free_rid(pipeline)
		pipeline = RID()
	if shader != RID():
		rd.free_rid(shader)
		shader = RID()

# ---- 内部 ----

func _make_uniform_set(buffers: ComputeBuffers, names: Array) -> RID:
	var uniforms: Array = []
	for i in names.size():
		var n: StringName = names[i]
		var buf := buffers.get_buf(n)
		if buf == RID():
			push_error("[ComputeProgram:%s] 缺少 buffer: %s" % [name, n])
			return RID()
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = i
		u.add_id(buf)
		uniforms.append(u)
	return rd.uniform_set_create(uniforms, shader, 0)