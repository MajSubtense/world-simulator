class_name SolarModel
extends RefCounted
## 太阳方向模型。纯静态。
##
## 约定：
##   day_length：一天多少 tick
##   tilt：地轴倾角（0 = 无倾角，[0,1] 之间的值；0.3 约等于地球）
##   season：季节相位，[0, 1]，0 = 春分，0.25 = 夏至，0.5 = 秋分，0.75 = 冬至
## 返回：从球心指向太阳的单位向量

static func sun_direction(tick: int, day_length: int,
		tilt: float, season: float = 0.0) -> Vector3:
	var day_len := maxi(1, day_length)
	var day_angle := float(tick % day_len) / float(day_len) * TAU

	var season_angle := season * TAU
	var y := tilt * sin(season_angle)

	var cos_y := sqrt(maxf(0.0, 1.0 - y * y))
	return Vector3(cos(day_angle) * cos_y, y, sin(day_angle) * cos_y).normalized()

## 某个面朝向太阳的辐射强度（0 = 背光，1 = 正对）
static func solar_intensity(face_normal: Vector3, sun_dir: Vector3) -> float:
	return maxf(face_normal.dot(sun_dir), 0.0)

## 根据 tick 返回当天的"小时数"（用于 UI 显示）
static func hour_of_day(tick: int, day_length: int) -> float:
	var day_len := maxi(1, day_length)
	return float(tick % day_len) / float(day_len) * 24.0