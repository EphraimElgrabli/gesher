import GesherKit
import GesherPlatform
import Foundation
import WeatherCore

@main
enum WeatherCli {
    static func main() { WeatherApp.make().main() }
}

/// The Weather app: its operations, defaults and shared dependencies.
/// This is the reference implementation of the AgentOperation pattern; see AGENTS.md.
enum WeatherApp {
    static func make(context: @escaping () throws -> WeatherContext = { WeatherContext() }) -> AgentApp<WeatherContext>
    {
        AgentApp(
            name: "weather",
            summary: "Forecasts, air quality and saved locations from Apple Weather.",
            instructions: """
                Places accept a city or address, a saved location name, or 'lat,lon'; omit the place to use \
                the user's default (configured, else the first saved location). The response always names the \
                resolved place: check it. Units default to the user's locale (metric: °C, km/h, km, mm, hPa). An \
                empty alerts list means Apple reported none, not that no warning exists where it has no provider.
                """,
            operations: [
                AnyOperation(CurrentWeather.self),
                AnyOperation(HourlyForecast.self),
                AnyOperation(DailyForecast.self),
                AnyOperation(AirQuality.self),
                AnyOperation(WeatherAlerts.self),
                AnyOperation(NextHourPrecipitation.self),
                AnyOperation(ListLocations.self),
                AnyOperation(SearchLocations.self),
                AnyOperation(AddLocations.self),
                AnyOperation(RemoveLocations.self),
            ],
            context: context)
    }
}

/// Dependencies shared by every Weather operation for the life of the process (or MCP session).
/// Repositories re-read native state on every call; nothing here caches user data.
final class WeatherContext {
    let runtime: WeatherRuntime
    let read: WeatherReadRepository
    let write: WeatherWriteRepository
    let config: UserConfig

    init(config: UserConfig = .load()) {
        runtime = WeatherRuntime()
        read = WeatherReadRepository(runtime: runtime)
        write = WeatherWriteRepository(runtime: runtime, readRepository: read)
        self.config = config
    }

    /// For tests: inject repositories (e.g. a favorites store in a temporary directory).
    init(runtime: WeatherRuntime, read: WeatherReadRepository, write: WeatherWriteRepository, config: UserConfig) {
        self.runtime = runtime
        self.read = read
        self.write = write
        self.config = config
    }

    /// Explicit place > configured `weather.location` > first saved location.
    func place(_ selector: String?) throws -> WeatherSavedLocationSnapshot {
        try read.resolvePlace(selector, fallback: config.value("weather", "location"))
    }

    /// Explicit units > configured `weather.units` > the user's locale.
    func units(_ explicit: Units?) -> Units {
        explicit ?? config.value("weather", "units").flatMap(Units.init(rawValue:))
            ?? (Locale.current.measurementSystem == .us ? .imperial : .metric)
    }
}
