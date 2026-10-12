class_name PlotMap
extends RefCounted
## 低精度 Goldberg 网格。每个面 = 一个「地块 / Plot」。
## 用于：玩家选点、领地划分、plot 内切平面参数化。
##
## 与 PlanetWorld.gp（subdiv=64）的区分：
##   PlotMap.gp    = 地块层（subdiv=8，642 面）
##   PlanetWorld.gp = cell 层（subdiv=64，40962 面）

const DEFAULT_SUBDIV := 8

var gp: GoldbergPolyhedron
var lookup: FaceLookup
var subdivision: int = DEFAULT_SUBDIV

func setup(subdiv: int = DEFAULT_SUBDIV, radius: float = 1.0) -> void:
	subdivision = subdiv
	gp = GoldbergPolyhedron.get_or_create(subdiv, radius)
	lookup = FaceLookup.new()
	lookup.setup(gp)

func face_count() -> int:
	return gp.face_count

func face_at(dir: Vector3) -> int:
	return lookup.find(dir)

func center_dir(f: int) -> Vector3:
	return gp.face_normals[f]