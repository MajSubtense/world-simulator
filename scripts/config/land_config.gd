class_name LandConfig
extends Resource
## 海陆生成参数。阶段 1 的单一真源。

@export_range(0.0, 1.0, 0.01) var land_ratio: float = 0.40
@export_range(0.0, 1.0, 0.01) var land_dispersion: float = 0.50
@export var land_seed: int = 12345
@export_range(0.0, 1.0, 0.01) var erosion_strength: float = 0.30
@export var erosion_seed: int = 67890