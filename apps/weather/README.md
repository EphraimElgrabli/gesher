# Weather

`weather-cli` gives current conditions, hourly and daily forecasts and air quality for any place,
and manages your saved Weather locations. Every command is also an MCP tool in `weather-cli mcp`.

```sh
weather-cli current                      # default place: config weather.location, else first saved location
weather-cli current Haifa --units imperial
weather-cli hourly 'Tel Aviv' --from 'tomorrow 6:00' --hours 12
weather-cli daily 32.08,34.78 --days 3 --format pretty
weather-cli air-quality Haifa
weather-cli alerts Paris                 # severe-weather alerts: title, source, expiry, link
weather-cli next-hour London             # rain in the next hour: summary + wet periods (--every-minute)
weather-cli location search Springfield
weather-cli location add Haifa Eilat     # batch; re-adding is a no-op
weather-cli location remove Eilat        # exact name or id only
```

**For developers.** Weather is the reference implementation of the `AgentOperation` pattern (see
[AGENTS.md](../../AGENTS.md)): private WeatherFoundation serves forecasts, private GeoServices
resolves places, and private WeatherCore's `SyncedDataManager` stores saved locations (no
preference or database bytes are read or written). `Sources/WeatherCli/WeatherCli.swift` declares
the app and its context;
`Sources/WeatherCli/Operations/` holds one type per operation plus the agent-facing output
models; `Sources/WeatherCore/` holds the private-framework adapters and repositories.

A place is `lat,lon`, a saved location (exact name or id), or the top native geocoding result;
every response echoes the resolved `place`. Coordinates keep their exact values and take the name,
country and time zone of the place native reverse geocoding finds there, so times are local to it. Add/remove verify the result through a fresh native
context and check that other saved locations survived. Native persistence does not prove
iCloud sync has finished.

Saved locations live in the protected Weather group container: without Full Disk Access for the
CLI (or its launching app) they cannot be read and commands fail with `permission_denied`;
a place name or `lat,lon` still
works. Air quality needs the place's country code, which is derived by native reverse geocoding;
the service does not cover every country (e.g. IL, IS) and then answers `not_available`.

`alerts` and `next-hour` use WeatherFoundation's typed request
(`forecast:forLocation:locale:requestIdentifier:completionHandler:`, types 1024 and 2048), as the
Weather app does for its alert banner and next-hour chart. Next-hour precipitation exists only where
Apple offers it (for example the US and UK, not IL); elsewhere it answers `not_available`. Alerts
come from national services (e.g. METEO-FRANCE); an empty list means none was reported, and where
Apple has no alert provider the list is empty as well.
