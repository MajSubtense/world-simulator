class_name ClimateConfig
extends Resource
## 气候模拟参数。阶段 3 的单一真源。

# ---- 时间 ----
## 现实每秒跑多少 tick。影响整体模拟速度。
@export_range(0.1, 60.0, 0.1) var ticks_per_second: float = 1.2
## 一天多少 tick。控制自转速度。
@export_range(24, 720, 1) var ticks_per_day: int = 240
## 一年多少 tick。控制季节变化速度。
@export_range(120, 100000, 120) var ticks_per_year: int = 14400
## 地轴倾角 [0, 1]。0 = 无季节，0.41 ≈ 地球（±24°），0.7 = 极端。
@export_range(0.0, 0.7, 0.01) var axial_tilt: float = 0.41
## 开局季节相位 [0, 1]。0=春分，0.25=夏至，0.5=秋分，0.75=冬至。
@export_range(0.0, 1.0, 0.01) var initial_season: float = 0.25

# ---- 温度 ----
@export_group("Temperature")
@export_range(0.0, 0.05, 0.001) var solar_absorption: float = 0.010
@export_range(0.0, 0.03, 0.001) var thermal_emission: float = 0.005
@export_range(0.0, 0.05, 0.001) var base_relaxation: float = 0.010
@export_range(0.0, 3.0, 0.1) var lapse_rate: float = 0.5
@export_range(0.0, 2.0, 0.05) var advection_speed: float = 0.4
@export_range(0.0, 0.5, 0.01) var diffusion_coeff: float = 0.15

# ---- 风 ----
@export_group("Wind")
@export_range(0.0, 1.0, 0.01) var circulation_amp: float = 0.3
@export_range(0.0, 3.0, 0.05) var wind_scale: float = 0.5

# ---- 大气湿度 ----
@export_group("Humidity")
@export_range(0.0, 0.20, 0.005) var humidity_advection: float = 0.03
@export_range(0.0, 0.10, 0.005) var humidity_diffusion_atm: float = 0.02
@export_range(0.0, 0.50, 0.01) var evap_rate_ocean: float = 0.20
@export_range(0.0, 0.30, 0.01) var evap_rate_land: float = 0.10
@export_range(0.0, 1.0, 0.05) var latent_heat: float = 0.30

# ---- 云 / 降水 ----
@export_group("Cloud / Rain")
@export_range(0.0, 1.0, 0.01) var cloud_form_rate: float = 0.05
@export_range(0.0, 0.1, 0.005) var cloud_decay: float = 0.010
@export_range(0.0, 1.0, 0.01) var cloud_threshold: float = 0.25
@export_range(0.0, 1.0, 0.05) var release_rate: float = 0.15
@export_range(0.0, 2.0, 0.05) var cloud_advection: float = 0.60

# ---- 地形降水 ----
@export_group("Orographic")
@export_range(0.0, 0.5, 0.005) var orographic_factor: float = 0.05
@export_range(0.0, 1.0, 0.05) var latent_heat_release: float = 0.30
@export_range(0.05, 0.5, 0.01) var sat_base: float = 0.15
@export_range(0.5, 5.0, 0.1) var sat_temp_factor: float = 2.5

# ---- 雪 / 土壤 ----
@export_group("Snow / Soil")
@export_range(0.0, 0.5, 0.005) var melt_rate: float = 0.05
@export_range(0.0, 1.0, 0.01) var runoff_ratio: float = 0.30
@export_range(0.0, 0.05, 0.001) var baseflow_rate: float = 0.005

# ---- 河流 ----
@export_group("River")
## 多少 tick 触发一次河流累积。
@export_range(1, 600, 1) var river_trigger_interval: int = 120
## 每次触发时执行多少子步。必须为偶数以保证 a/b buffer 交替正确。
@export_range(2, 600, 2) var river_substeps: int = 120
## 每子步流出的比例。
@export_range(0.0, 1.0, 0.01) var river_flow_rate: float = 0.30

# ---- 生态 ----
@export_group("Ecology")
## 每多少个气候 tick 更新一次生态层。
@export_range(1, 600, 1) var ecology_interval: int = 60
## 每次生态更新时，实际密度向潜在密度的靠拢比例（0~1）。
@export_range(0.0, 1.0, 0.01) var ecology_recovery_rate: float = 0.2
## 全局植被密度缩放。
@export_range(0.0, 2.0, 0.05) var ecology_density_scale: float = 1.0
## 生态层温度 EMA 系数。越大越跟随瞬时温度，越小越平滑。
@export_range(0.01, 1.0, 0.01) var ecology_temp_ema: float = 0.1