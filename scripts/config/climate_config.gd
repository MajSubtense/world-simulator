class_name ClimateConfig
extends Resource

# ---- 时间 ----
@export_range(0.1, 60.0, 0.1) var ticks_per_second: float = 1.2
@export_range(24, 720, 1) var day_length: int = 240
@export_range(0.0, 0.7, 0.01) var sun_tilt: float = 0.41
@export_range(0.0, 1.0, 0.01) var sun_season: float = 0.25

# ---- 温度 ----
@export_group("Temperature")
@export_range(0.0, 0.05, 0.001) var solar_absorption: float = 0.010
@export_range(0.0, 0.03, 0.001) var thermal_emission: float = 0.005
@export_range(0.0, 0.05, 0.001) var base_relaxation: float = 0.010
@export_range(0.0, 3.0, 0.1) var lapse_rate: float = 1.5
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

# ---- 云 / 降水 ★ 云雨核心参数 ----
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