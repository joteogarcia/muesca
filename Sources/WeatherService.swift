import Foundation
import CoreLocation
import SwiftUI

/// Tiempo actual vía Open-Meteo (gratis, sin clave). Usa tu ubicación o una ciudad elegida.
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {

    struct Current: Equatable {
        var temperature: Double
        var code: Int
        var isDay: Bool
        var high: Double
        var low: Double
    }

    @Published private(set) var current: Current?
    @Published private(set) var place: String = ""

    private let manager = CLLocationManager()
    private var timer: Timer?
    private let cityKey = "weatherCity"
    private let fallbackCity = "Madrid"

    /// Ciudad elegida a mano; vacía = usar la ubicación del Mac.
    var manualCity: String { UserDefaults.standard.string(forKey: cityKey) ?? "" }

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func setManualCity(_ city: String) {
        UserDefaults.standard.set(city, forKey: cityKey)
        refresh()
    }

    func refresh() {
        if !manualCity.isEmpty {
            geocode(manualCity)
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            geocode(fallbackCity)
        default:
            manager.requestLocation()
        }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manualCity.isEmpty else { return }
        if manager.authorizationStatus != .notDetermined { refresh() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manualCity.isEmpty, let loc = locations.last else { return }
        fetch(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        reverseGeocode(loc)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if current == nil { geocode(fallbackCity) }
    }

    // MARK: Red

    private struct GeoResponse: Decodable {
        struct Result: Decodable { let name: String; let latitude: Double; let longitude: Double }
        let results: [Result]?
    }

    private struct ForecastResponse: Decodable {
        struct Cur: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
        struct Daily: Decodable { let temperature_2m_max: [Double]; let temperature_2m_min: [Double] }
        let current: Cur
        let daily: Daily
    }

    private func geocode(_ city: String) {
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: AppLanguage.resolved),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = comps.url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let geo = try? JSONDecoder().decode(GeoResponse.self, from: data),
                  let r = geo.results?.first else { return }
            DispatchQueue.main.async {
                self?.place = r.name
                self?.fetch(latitude: r.latitude, longitude: r.longitude)
            }
        }.resume()
    }

    private func fetch(latitude: Double, longitude: Double) {
        let s = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)"
            + "&current=temperature_2m,weather_code,is_day"
            + "&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1"
        guard let url = URL(string: s) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let f = try? JSONDecoder().decode(ForecastResponse.self, from: data) else {
                // Open-Meteo caído o saturado → proveedor de respaldo (MET Norway).
                self?.fetchMetNorway(latitude: latitude, longitude: longitude)
                return
            }
            let c = Current(
                temperature: f.current.temperature_2m,
                code: f.current.weather_code,
                isDay: f.current.is_day == 1,
                high: f.daily.temperature_2m_max.first ?? f.current.temperature_2m,
                low: f.daily.temperature_2m_min.first ?? f.current.temperature_2m
            )
            DispatchQueue.main.async { self?.current = c }
        }.resume()
    }

    // MARK: Respaldo: MET Norway (api.met.no), gratis y sin clave

    private struct MetResponse: Decodable {
        struct Properties: Decodable { let timeseries: [Entry] }
        struct Entry: Decodable { let data: EntryData }
        struct EntryData: Decodable {
            let instant: Instant
            let next_1_hours: Next?
            let next_6_hours: Next?
        }
        struct Instant: Decodable { let details: Details }
        struct Details: Decodable { let air_temperature: Double }
        struct Next: Decodable { let summary: Summary }
        struct Summary: Decodable { let symbol_code: String }
        let properties: Properties
    }

    private func fetchMetNorway(latitude: Double, longitude: Double) {
        let lat = String(format: "%.3f", latitude), lon = String(format: "%.3f", longitude)
        guard let url = URL(string: "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=\(lat)&lon=\(lon)") else { return }
        var req = URLRequest(url: url)
        req.setValue("Muesca/1.1 (uso personal)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data,
                  let m = try? JSONDecoder().decode(MetResponse.self, from: data),
                  let first = m.properties.timeseries.first else {
                // Ambos fallan: reintentar en 3 minutos.
                DispatchQueue.main.asyncAfter(deadline: .now() + 180) { self?.refresh() }
                return
            }
            let next24 = m.properties.timeseries.prefix(24).map(\.data.instant.details.air_temperature)
            let symbol = first.data.next_1_hours?.summary.symbol_code ?? first.data.next_6_hours?.summary.symbol_code ?? "cloudy"
            let c = Current(
                temperature: first.data.instant.details.air_temperature,
                code: Self.wmoCode(fromMet: symbol),
                isDay: !symbol.hasSuffix("_night"),
                high: next24.max() ?? first.data.instant.details.air_temperature,
                low: next24.min() ?? first.data.instant.details.air_temperature
            )
            DispatchQueue.main.async { self?.current = c }
        }.resume()
    }

    private static func wmoCode(fromMet symbol: String) -> Int {
        let s = symbol.components(separatedBy: "_").first ?? symbol
        if s.contains("thunder") { return 95 }
        if s.contains("snow") || s.contains("sleet") { return 71 }
        if s.contains("heavyrain") { return 65 }
        if s.contains("rainshowers") { return 80 }
        if s.contains("rain") { return 61 }
        switch s {
        case "clearsky": return 0
        case "fair": return 1
        case "partlycloudy": return 2
        case "fog": return 45
        default: return 3
        }
    }

    private func reverseGeocode(_ loc: CLLocation) {
        CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: AppLanguage.locale) { [weak self] marks, _ in
            guard let name = marks?.first?.locality else { return }
            DispatchQueue.main.async { self?.place = name }
        }
    }

    // MARK: Códigos WMO → símbolo y texto

    static func symbol(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func description(for code: Int) -> String {
        switch code {
        case 0: return L("wx.0")
        case 1: return L("wx.1")
        case 2: return L("wx.2")
        case 3: return L("wx.3")
        case 45, 48: return L("wx.fog")
        case 51...57: return L("wx.drizzle")
        case 61...67: return L("wx.rain")
        case 71...77: return L("wx.snow")
        case 80...82: return L("wx.showers")
        case 85, 86: return L("wx.snowShowers")
        case 95...99: return L("wx.storm")
        default: return ""
        }
    }
}
