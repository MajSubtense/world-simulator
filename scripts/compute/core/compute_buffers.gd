class_name ComputeBuffers
extends RefCounted
## 命名 storage buffer 表。所有 GPU buffer 通过 StringName 访问，
## 避免 30+ 裸露 RID 字段。
##
## 用法：
##   var bufs := ComputeBuffers.new(rd)
##   bufs.add_f32(&"temp", N, initial_temp)
##   bufs.update_f32(&"temp", new_temp)
##   var t := bufs.read_f32(&"temp")
##   bufs.free_all()
##
## 注意：与 ComputeProgram 配合时，若 buffer 被重建，
## 必须让 ComputeProgram.clear_set_cache()，否则 uniform set 会绑定旧 RID。

var _rd: RenderingDevice
var _store: Dictionary = {}  # StringName → RID

func _init(rd: RenderingDevice) -> void:
	_rd = rd

# ---- 创建 ----

## 通用字节 buffer。
func add(name: StringName, byte_size: int,
		init: PackedByteArray = PackedByteArray()) -> RID:
	if _store.has(name):
		push_error("[ComputeBuffers] 重复创建: %s" % name)
		return _store[name]
	var buf: RID
	if init.size() >= byte_size:
		buf = _rd.storage_buffer_create(byte_size, init)
	else:
		buf = _rd.storage_buffer_create(byte_size)
	_store[name] = buf
	return buf

func add_f32(name: StringName, count: int,
		init: PackedFloat32Array = PackedFloat32Array()) -> RID:
	var bytes := init.to_byte_array() if init.size() == count else PackedByteArray()
	return add(name, count * 4, bytes)

func add_i32(name: StringName, count: int,
		init: PackedInt32Array = PackedInt32Array()) -> RID:
	var bytes := init.to_byte_array() if init.size() == count else PackedByteArray()
	return add(name, count * 4, bytes)

## 用于 GLSL vec4 对齐的 buffer（如 vec4 sun_dir）。
## 传入的 values 长度必须是 4 的倍数。
func add_vec4_f32(name: StringName, vec4_count: int,
		init: PackedFloat32Array = PackedFloat32Array()) -> RID:
	var count := vec4_count * 4
	var bytes := init.to_byte_array() if init.size() == count else PackedByteArray()
	return add(name, count * 4, bytes)

# ---- 访问 ----

func get_buf(name: StringName) -> RID:
	return _store.get(name, RID())

func has(name: StringName) -> bool:
	return _store.has(name)

# ---- 更新 ----

func update_f32(name: StringName, values: PackedFloat32Array) -> void:
	var buf := get_buf(name)
	if buf != RID():
		_rd.buffer_update(buf, 0, values.size() * 4, values.to_byte_array())

func update_i32(name: StringName, values: PackedInt32Array) -> void:
	var buf := get_buf(name)
	if buf != RID():
		_rd.buffer_update(buf, 0, values.size() * 4, values.to_byte_array())

func update_raw(name: StringName, bytes: PackedByteArray) -> void:
	var buf := get_buf(name)
	if buf != RID():
		_rd.buffer_update(buf, 0, bytes.size(), bytes)

## 把 buffer 的前 float_count 个 float 全部置零。
func zero_fill(name: StringName, float_count: int) -> void:
	var buf := get_buf(name)
	if buf == RID():
		return
	var zeros := PackedFloat32Array()
	zeros.resize(float_count)
	_rd.buffer_update(buf, 0, float_count * 4, zeros.to_byte_array())

# ---- 回读 ----

func read_f32(name: StringName) -> PackedFloat32Array:
	var buf := get_buf(name)
	if buf == RID():
		return PackedFloat32Array()
	return _rd.buffer_get_data(buf).to_float32_array()

func read_i32(name: StringName) -> PackedInt32Array:
	var buf := get_buf(name)
	if buf == RID():
		return PackedInt32Array()
	return _rd.buffer_get_data(buf).to_int32_array()

func read_bytes(name: StringName) -> PackedByteArray:
	var buf := get_buf(name)
	if buf == RID():
		return PackedByteArray()
	return _rd.buffer_get_data(buf)

# ---- 释放 ----

func free_all() -> void:
	for buf in _store.values():
		if buf != RID():
			_rd.free_rid(buf)
	_store.clear()