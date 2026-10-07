/*
 * Weather <-> JSON, for the on-device cache.
 *
 * JSON.parse gives back plain objects, not instances: the model classes carry methods
 * (Weather.hasActiveAlerts, Astro.progressAt, Alert.isCurrent) and Date fields that a raw parse
 * would leave as strings. So every field is copied back onto a real instance here rather than
 * casting the parsed object — ArkTS is strict about this and the views would break on the first
 * method call otherwise.
 *
 * Dates are stored as epoch milliseconds, which also keeps the payload timezone-free.
 */

import {
  Alert,
  Astro,
  Current,
  Daily,
  HalfDay,
  Hourly,
  LocationModel,
  Minutely,
  PollenEntry,
  PrecipitationProbability,
  Temperature,
  trimHourlyFromNow,
  Weather
} from '../model/Weather';
import { WeatherKind } from '../model/WeatherKind';
import { AirQualityConcentrations } from '../model/Pollutant';

/* ------------------------------------------------------------------ plain shapes */

interface JsonTemperature {
  t: number | null;
  f: number | null;
}

/** The six concentrations, in the units the model holds them in (CO in mg/m³). */
interface JsonAirQuality {
  pm25: number | null;
  pm10: number | null;
  o3: number | null;
  no2: number | null;
  so2: number | null;
  co: number | null;
}

function airQualityOut(value: AirQualityConcentrations | null): JsonAirQuality | null {
  if (value === null) {
    return null;
  }
  return {
    pm25: value.pm25,
    pm10: value.pm10,
    o3: value.o3,
    no2: value.no2,
    so2: value.so2,
    co: value.co
  };
}

function airQualityIn(value: JsonAirQuality | null | undefined): AirQualityConcentrations | null {
  if (value === null || value === undefined) {
    return null;
  }
  const air = new AirQualityConcentrations();
  air.pm25 = value.pm25;
  air.pm10 = value.pm10;
  air.o3 = value.o3;
  air.no2 = value.no2;
  air.so2 = value.so2;
  air.co = value.co;
  return air;
}

interface JsonHalfDay {
  text: string | null;
  kind: number;
  temp: JsonTemperature | null;
  prob: number | null;
  precip: number | null;
  /** The rain and snow parts of `precip`, both in mm — HalfDay.precipitationRain / .precipitationSnow. */
  rain: number | null;
  snow: number | null;
  windSpeed: number | null;
  windDegree: number | null;
  /** Optional: a row written before the gusts line existed just shows no gusts. */
  windGusts?: number | null;
}

interface JsonDaily {
  date: number;
  day: JsonHalfDay | null;
  night: JsonHalfDay | null;
  aqi: number | null;
  uv: number | null;
  sunshine: number | null;
  /** Degree days, in deci-celsius — see Daily.heatingDegreeDay. */
  hdd: number | null;
  cdd: number | null;
  air: JsonAirQuality | null;
}

interface JsonHourly {
  date: number;
  text: string | null;
  kind: number;
  daylight: boolean;
  aqi: number | null;
  air: JsonAirQuality | null;
  temp: JsonTemperature | null;
  prob: number | null;
  humidity: number | null;
  dewPoint: number | null;
  precip: number | null;
  rain: number | null;
  snow: number | null;
  pressure: number | null;
  cloudCover: number | null;
  visibility: number | null;
  uv: number | null;
  windSpeed: number | null;
  windDegree: number | null;
  windGusts?: number | null;
}

interface JsonAstro {
  riseTime: string;
  setTime: string;
  phase: string;
  riseDate: number | null;
  setDate: number | null;
  phaseAngle: number;
}

interface JsonPollen {
  name: string;
  level: number;
  levelName: string;
  /** Grains per cubic metre — the detail grid's subtitle needs the number, not only the level. */
  concentration: number;
}

interface JsonCurrent {
  text: string | null;
  kind: number;
  temp: JsonTemperature | null;
  humidity: number | null;
  dewPoint: number | null;
  pressure: number | null;
  visibility: number | null;
  uv: number | null;
  windSpeed: number | null;
  windGusts: number | null;
  windDegree: number | null;
  precip: number | null;
  aqi: number | null;
  air: JsonAirQuality | null;
  pollen: JsonPollen[];
  sun: JsonAstro | null;
  moon: JsonAstro | null;
  dailyForecast: string | null;
  hourlyForecast: string | null;
}

interface JsonMinutely {
  date: number;
  endingDate: number;
  intensity: number;
}

interface JsonWeather {
  refreshTime: number | null;
  todayIndex: number | null;
  current: JsonCurrent | null;
  daily: JsonDaily[];
  hourly: JsonHourly[];
  minutely: JsonMinutely[];
}

/* ------------------------------------------------------------------- to JSON */

function temperatureOut(value: Temperature | null): JsonTemperature | null {
  return value === null ? null : { t: value.temperature, f: value.feelsLikeTemperature };
}

function halfDayOut(value: HalfDay | null): JsonHalfDay | null {
  if (value === null) {
    return null;
  }
  return {
    text: value.weatherText,
    kind: value.weatherKind as number,
    temp: temperatureOut(value.temperature),
    prob: value.precipitationProbability === null ? null : value.precipitationProbability.total,
    precip: value.precipitationTotal,
    rain: value.precipitationRain,
    snow: value.precipitationSnow,
    windSpeed: value.windSpeed,
    windDegree: value.windDegree,
    windGusts: value.windGusts
  };
}

function astroOut(value: Astro | null): JsonAstro | null {
  if (value === null) {
    return null;
  }
  return {
    riseTime: value.riseTime,
    setTime: value.setTime,
    phase: value.phase,
    riseDate: value.riseDate === null ? null : value.riseDate.getTime(),
    setDate: value.setDate === null ? null : value.setDate.getTime(),
    phaseAngle: value.phaseAngle
  };
}

export function serializeWeather(weather: Weather): string {
  const daily: JsonDaily[] = weather.dailyForecast.map((d: Daily): JsonDaily => ({
    date: d.date.getTime(),
    day: halfDayOut(d.day),
    night: halfDayOut(d.night),
    aqi: d.airQualityIndex,
    uv: d.uvIndex,
    sunshine: d.sunshineHours,
    hdd: d.heatingDegreeDay,
    cdd: d.coolingDegreeDay,
    air: airQualityOut(d.airQuality)
  }));
  // The FULL series, past hours included — the detail screens' day pager slices it (see
  // Weather.hourlyForecast). `nextHourlyForecast` is derived from it again on the way back in.
  const hourly: JsonHourly[] = weather.hourlyForecast.map((h: Hourly): JsonHourly => ({
    date: h.date.getTime(),
    text: h.weatherText,
    kind: h.weatherKind as number,
    daylight: h.daylight,
    aqi: h.airQualityIndex,
    air: airQualityOut(h.airQuality),
    temp: temperatureOut(h.temperature),
    prob: h.precipitationProbability === null ? null : h.precipitationProbability.total,
    humidity: h.relativeHumidity,
    dewPoint: h.dewPoint,
    precip: h.precipitationTotal,
    rain: h.precipitationRain,
    snow: h.precipitationSnow,
    pressure: h.pressure,
    cloudCover: h.cloudCover,
    visibility: h.visibility,
    uv: h.uvIndex,
    windSpeed: h.windSpeed,
    windDegree: h.windDegree,
    windGusts: h.windGusts
  }));
  const minutely: JsonMinutely[] = weather.minutelyForecast.map((m: Minutely): JsonMinutely => ({
    date: m.date.getTime(),
    endingDate: m.endingDate.getTime(),
    intensity: m.precipitationIntensity
  }));

  const c: Current | null = weather.current;
  const current: JsonCurrent | null = c === null ? null : {
    text: c.weatherText,
    kind: c.weatherKind as number,
    temp: temperatureOut(c.temperature),
    humidity: c.relativeHumidity,
    dewPoint: c.dewPoint,
    pressure: c.pressure,
    visibility: c.visibility,
    uv: c.uvIndex,
    windSpeed: c.windSpeed,
    windGusts: c.windGusts,
    windDegree: c.windDegree,
    precip: c.precipitationTotal,
    aqi: c.airQualityIndex,
    air: airQualityOut(c.airQuality),
    pollen: c.pollen.map((p: PollenEntry): JsonPollen => ({
      name: p.name, level: p.level, levelName: p.levelName, concentration: p.concentration
    })),
    sun: astroOut(c.sun),
    moon: astroOut(c.moon),
    dailyForecast: c.dailyForecast,
    hourlyForecast: c.hourlyForecast
  };

  const payload: JsonWeather = {
    refreshTime: weather.refreshTime === null ? null : weather.refreshTime.getTime(),
    todayIndex: weather.todayIndex,
    current: current,
    daily: daily,
    hourly: hourly,
    minutely: minutely
  };
  return JSON.stringify(payload);
}

/* ----------------------------------------------------------------- from JSON */

function temperatureIn(value: JsonTemperature | null): Temperature | null {
  if (value === null || value === undefined) {
    return null;
  }
  const t = new Temperature();
  t.temperature = value.t;
  t.feelsLikeTemperature = value.f;
  return t;
}

function probabilityIn(total: number | null): PrecipitationProbability | null {
  if (total === null || total === undefined) {
    return null;
  }
  const p = new PrecipitationProbability();
  p.total = total;
  return p;
}

function halfDayIn(value: JsonHalfDay | null): HalfDay | null {
  if (value === null || value === undefined) {
    return null;
  }
  const h = new HalfDay();
  h.weatherText = value.text;
  h.weatherKind = value.kind as WeatherKind;
  h.temperature = temperatureIn(value.temp);
  h.precipitationProbability = probabilityIn(value.prob);
  h.precipitationTotal = value.precip;
  // A cache written before these two existed parses them as undefined; `?? null` keeps the model's
  // "the source reported nothing" branch rather than putting undefined into a number|null field.
  h.precipitationRain = value.rain === undefined ? null : value.rain;
  h.precipitationSnow = value.snow === undefined ? null : value.snow;
  h.windSpeed = value.windSpeed;
  h.windDegree = value.windDegree;
  h.windGusts = value.windGusts === undefined ? null : value.windGusts;
  return h;
}

function astroIn(value: JsonAstro | null): Astro | null {
  if (value === null || value === undefined) {
    return null;
  }
  const a = new Astro();
  a.riseTime = value.riseTime;
  a.setTime = value.setTime;
  a.phase = value.phase;
  a.riseDate = value.riseDate === null ? null : new Date(value.riseDate);
  a.setDate = value.setDate === null ? null : new Date(value.setDate);
  a.phaseAngle = value.phaseAngle;
  return a;
}

/** Returns null on any malformed payload — a bad cache must never crash the screen. */
export function deserializeWeather(payload: string, utcOffsetSeconds: number): Weather | null {
  try {
    const parsed: JsonWeather = JSON.parse(payload) as JsonWeather;
    const weather = new Weather();
    weather.refreshTime = parsed.refreshTime === null ? null : new Date(parsed.refreshTime);
    weather.todayIndex = parsed.todayIndex;

    weather.dailyForecast = parsed.daily.map((d: JsonDaily): Daily => {
      const daily = new Daily();
      daily.date = new Date(d.date);
      daily.day = halfDayIn(d.day);
      daily.night = halfDayIn(d.night);
      daily.airQualityIndex = d.aqi;
      daily.uvIndex = d.uv;
      daily.sunshineHours = d.sunshine;
      // A cache written before degree days existed has neither key; both stay null, no row.
      daily.heatingDegreeDay = d.hdd === undefined ? null : d.hdd;
      daily.coolingDegreeDay = d.cdd === undefined ? null : d.cdd;
      daily.airQuality = airQualityIn(d.air);
      return daily;
    });

    weather.hourlyForecast = parsed.hourly.map((h: JsonHourly): Hourly => {
      const hourly = new Hourly();
      hourly.date = new Date(h.date);
      hourly.weatherText = h.text;
      hourly.weatherKind = h.kind as WeatherKind;
      hourly.daylight = h.daylight;
      hourly.airQualityIndex = h.aqi;
      hourly.airQuality = airQualityIn(h.air);
      hourly.temperature = temperatureIn(h.temp);
      hourly.precipitationProbability = probabilityIn(h.prob);
      hourly.relativeHumidity = h.humidity;
      hourly.dewPoint = h.dewPoint;
      hourly.precipitationTotal = h.precip;
      hourly.precipitationRain = h.rain === undefined ? null : h.rain;
      hourly.precipitationSnow = h.snow === undefined ? null : h.snow;
      hourly.pressure = h.pressure;
      hourly.cloudCover = h.cloudCover;
      hourly.visibility = h.visibility;
      hourly.uvIndex = h.uv;
      hourly.windSpeed = h.windSpeed;
      hourly.windDegree = h.windDegree;
      hourly.windGusts = h.windGusts === undefined ? null : h.windGusts;
      return hourly;
    });

    weather.minutelyForecast = parsed.minutely.map((m: JsonMinutely): Minutely => {
      const minutely = new Minutely();
      minutely.date = new Date(m.date);
      minutely.endingDate = new Date(m.endingDate);
      minutely.precipitationIntensity = m.intensity;
      return minutely;
    });

    if (parsed.current !== null && parsed.current !== undefined) {
      const c: JsonCurrent = parsed.current;
      const current = new Current();
      current.weatherText = c.text;
      current.weatherKind = c.kind as WeatherKind;
      current.temperature = temperatureIn(c.temp);
      current.relativeHumidity = c.humidity;
      current.dewPoint = c.dewPoint;
      current.pressure = c.pressure;
      current.visibility = c.visibility;
      current.uvIndex = c.uv;
      current.windSpeed = c.windSpeed;
      current.windGusts = c.windGusts;
      current.windDegree = c.windDegree;
      current.precipitationTotal = c.precip;
      current.airQualityIndex = c.aqi;
      current.airQuality = airQualityIn(c.air);
      current.pollen = c.pollen.map((p: JsonPollen): PollenEntry => {
        const entry = new PollenEntry();
        entry.name = p.name;
        entry.level = p.level;
        entry.levelName = p.levelName;
        entry.concentration = p.concentration === undefined ? 0 : p.concentration;
        return entry;
      });
      current.sun = astroIn(c.sun);
      current.moon = astroIn(c.moon);
      current.dailyForecast = c.dailyForecast;
      current.hourlyForecast = c.hourlyForecast;
      weather.current = current;
    }

    // Derived, never persisted: what "from now on" means has moved since the row was written.
    weather.nextHourlyForecast = trimHourlyFromNow(weather.hourlyForecast, utcOffsetSeconds);

    return weather;
  } catch (error) {
    console.warn('Cached weather could not be parsed: ' + (error as Error).message);
    return null;
  }
}
