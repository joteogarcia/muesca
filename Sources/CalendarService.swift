import AppKit
import EventKit
import SwiftUI

/// Próximos eventos (hoy y mañana) de todos los calendarios configurados en el Mac.
final class CalendarService: ObservableObject {

    enum Access { case notDetermined, denied, granted }

    struct Item: Identifiable {
        let id: String
        let title: String
        let label: String
        let color: Color
        let isNow: Bool
        let start: Date
        let end: Date
        let isAllDay: Bool
        let joinURL: URL?
    }

    /// Reunión que empieza en ≤ 5 min o que está en curso: se avisa en la isla.
    @Published private(set) var upcoming: Item?

    // Vista de mes (MonthGrid.swift)
    enum AgendaMode: String { case upcoming, month }
    @Published var agendaMode: AgendaMode =
        AgendaMode(rawValue: UserDefaults.standard.string(forKey: "agendaMode") ?? "") ?? .upcoming {
        didSet { UserDefaults.standard.set(agendaMode.rawValue, forKey: "agendaMode") }
    }
    @Published var monthAnchor = Date()
    @Published var selectedDay: Date?
    /// Colores de calendario con eventos, por día (inicio del día).
    @Published var monthDots: [Date: [Color]] = [:]
    @Published var dayItems: [Item] = []
    let eventStore: EKEventStore

    @Published private(set) var access: Access = .notDetermined
    @Published private(set) var items: [Item] = []

    private var store: EKEventStore { eventStore }

    init() { eventStore = EKEventStore() }
    private var timer: Timer?

    func start() {
        updateAccess()
        if access == .notDetermined { requestAccess() } else { load() }

        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.load()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.load()
        }
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.updateUpcoming() }
        RunLoop.main.add(t, forMode: .common)
    }

    func requestAccess() {
        let done: (Bool, Error?) -> Void = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateAccess()
                self?.load()
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: done)
        } else {
            store.requestAccess(to: .event, completion: done)
        }
    }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func updateAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined:
            access = .notDetermined
        case .denied, .restricted:
            access = .denied
        default:
            if #available(macOS 14.0, *) {
                access = status == .fullAccess ? .granted : .denied
            } else {
                access = .granted
            }
        }
    }

    func updateUpcoming() {
        let now = Date()
        // Desde 5 min antes hasta que termina (si se solapan, la que empieza antes)
        let next = items.first { item in
            guard !item.isAllDay else { return false }
            return item.start.timeIntervalSince(now) <= 5 * 60 && item.end > now
        }
        if next?.id != upcoming?.id {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { upcoming = next }
        }
    }

    func join(_ item: Item) {
        if let url = item.joinURL { NSWorkspace.shared.open(url) }
    }

    /// Enlace de Teams, Meet, Zoom o Webex en la URL, ubicación o notas del evento.
    private static func joinURL(for ev: EKEvent) -> URL? {
        let texts = [ev.url?.absoluteString, ev.location, ev.notes].compactMap { $0 }
        let pattern = #"https://[^\s<>"]*(teams\.microsoft\.com|teams\.live\.com|meet\.google\.com|zoom\.us|webex\.com)[^\s<>"]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        for text in texts {
            let range = NSRange(text.startIndex..., in: text)
            if let m = regex.firstMatch(in: text, range: range), let r = Range(m.range, in: text) {
                return URL(string: String(text[r]))
            }
        }
        return nil
    }

    func load() {
        guard access == .granted else { items = []; return }
        let cal = Calendar.current
        let now = Date()
        let start = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 2, to: start) else { return }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted {
                (cal.startOfDay(for: $0.startDate), $0.isAllDay ? 0 : 1, $0.startDate)
                    < (cal.startOfDay(for: $1.startDate), $1.isAllDay ? 0 : 1, $1.startDate)
            }

        items = events.prefix(8).map { makeItem($0, now: now) }
        // Registro de diagnóstico (local): próximos eventos detectados
        let f = DateFormatter(); f.dateFormat = "dd/MM HH:mm"
        Log.write("Agenda: \(events.count) eventos · " + events.prefix(4).map {
            "\(f.string(from: $0.startDate))–\(f.string(from: $0.endDate)) [\($0.calendar?.title ?? "?")]\($0.isAllDay ? " todo el día" : "")"
        }.joined(separator: " | "))
        updateUpcoming()
        loadMonth()
    }

    func makeItem(_ ev: EKEvent, now: Date, showDay: Bool = true) -> Item {
        let cal = Calendar.current
        let timeFmt = DateFormatter()
        timeFmt.locale = AppLanguage.locale
        timeFmt.dateStyle = .none
        timeFmt.timeStyle = .short
        do {
            let isNow = !ev.isAllDay && ev.startDate <= now && ev.endDate > now
            let day: String
            if cal.isDateInToday(ev.startDate) || (ev.isAllDay && ev.startDate < now) { day = L("agenda.today") }
            else if cal.isDateInTomorrow(ev.startDate) { day = L("agenda.tomorrow") }
            else { day = "" }

            let time: String
            if ev.isAllDay { time = L("agenda.allDay") }
            else if isNow { time = L("agenda.nowUntil", timeFmt.string(from: ev.endDate)) }
            else { time = "\(timeFmt.string(from: ev.startDate)) – \(timeFmt.string(from: ev.endDate))" }

            let label = isNow || day.isEmpty || !showDay ? time : "\(day) · \(time)"
            let color = ev.calendar.map { Color(nsColor: $0.color) } ?? .blue
            return Item(
                id: "\(ev.eventIdentifier ?? UUID().uuidString)-\(ev.startDate.timeIntervalSince1970)",
                title: ev.title ?? L("agenda.untitled"),
                label: label,
                color: color,
                isNow: isNow,
                start: ev.startDate,
                end: ev.endDate,
                isAllDay: ev.isAllDay,
                joinURL: Self.joinURL(for: ev)
            )
        }
    }
}
