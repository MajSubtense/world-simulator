class_name HeightConfig
extends Resource
## 高程生成参数。阶段 2 的单一真源。

@export_group("Base")
@export_range(0.0, 0.05, 0.005) var land_base: float = 0.010
@export_range(0.0, 0.40, 0.01) var continental_rise: float = 0.120
@export_range(0.5, 4.0, 0.1) var continental_pow: float = 2.0
@export_range(0.05, 0.5, 0.01) var coast_damping: float = 0.250

@export_group("Plateau")
@export_range(0.0, 0.20, 0.005) var plateau_height: float = 0.080
@export_range(0.3, 3.0, 0.05) var plateau_freq: float = 0.70
@export_range(-0.5, 0.5, 0.01) var plateau_threshold: float = 0.30
@export var plateau_seed: int = 33333

@export_group("Mountain")
@export_range(0.0, 1.0, 0.01) var mountain_peak: float = 0.550
@export_range(0.3, 3.0, 0.05) var belt_freq: float = 0.90
@export_range(0.0, 0.5, 0.01) var belt_threshold: float = 0.15
@export_range(1.0, 8.0, 0.1) var ridge_freq: float = 3.50
@export var mountain_seed: int = 11111

@export_group("Hill")
@export_range(0.0, 0.10, 0.005) var hill_detail: float = 0.025
@export_range(4.0, 24.0, 0.5) var hill_freq: float = 12.0

@export_group("Ocean")
@export_range(0.0, 0.40, 0.01) var ocean_depth: float = 0.10
@export_range(0.5, 8.0, 0.1) var ocean_freq: float = 1.2
@export var ocean_seed: int = 22222
@export_range(0.0, 0.10, 0.005) var ocean_detail: float = 0.02
@export_range(0.5, 20.0, 0.1) var ocean_detail_freq: float = 6.0