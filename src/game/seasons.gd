class_name Seasons
extends RefCounted
## Seasons from the axial tilt. The planet's year follows the calendar: in
## the north, spring starts at the March equinox, and the south has the
## opposite season. Near the equator the seasons barely matter (no item there
## has a season), but the name still follows the hemisphere.
##
## Everything is a pure function of the day index (days since 1 Jan 1970,
## the same as GameState.day), so the fast debug clock runs through the year.

const NAMES := ["spring", "summer", "autumn", "winter"]
## Day of the year of the March equinox.
const EQUINOX_DAY := 80
const DAYS_PER_YEAR := 365.25


## Day of the year (1..366) for a day index.
static func day_of_year(day_index: int) -> int:
	var date := Time.get_date_dict_from_unix_time(day_index * 86400)
	var start := Time.get_unix_time_from_datetime_dict({"year": date.year, "month": 1, "day": 1})
	return int((day_index * 86400 - start) / 86400) + 1


## Where the north is in its year: 0 at the spring equinox, 0.25 at the
## summer solstice, 0.5 at the autumn equinox, 0.75 at midwinter.
static func year_phase(day_index: int) -> float:
	return fposmod((day_of_year(day_index) - EQUINOX_DAY) / DAYS_PER_YEAR, 1.0)


## Local phase: the south is half a year off.
static func phase_at(day_index: int, latitude_degrees: float) -> float:
	var phase := year_phase(day_index)
	return fposmod(phase + 0.5, 1.0) if latitude_degrees < 0.0 else phase


static func season_at(day_index: int, latitude_degrees: float) -> String:
	return NAMES[int(phase_at(day_index, latitude_degrees) * 4.0) % 4]


static func display_name(season: String) -> String:
	return season.capitalize()
