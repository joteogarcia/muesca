import SwiftUI
import EventKit

// Vista de mes en cuadrícula para la agenda.
// Para quitarla: borrar este archivo y el botón de modo en AgendaView (NotchView.swift).

extension CalendarService {

    var gridCalendar: Calendar {
        var c = Calendar.current
        c.locale = AppLanguage.locale
        return c
    }

    /// Carga los puntos de color de todo el mes visible.
    func loadMonth() {
        guard access == .granted else { monthDots = [:]; return }
        let cal = gridCalendar
        guard let interval = cal.dateInterval(of: .month, for: monthAnchor) else { return }
        let start = cal.date(byAdding: .day, value: -7, to: interval.start) ?? interval.start
        let end = cal.date(byAdding: .day, value: 7, to: interval.end) ?? interval.end
        let events = eventStore.events(matching: eventStore.predicateForEvents(withStart: start, end: end, calendars: nil))

        var dots: [Date: [Color]] = [:]
        for ev in events {
            guard let calColor = ev.calendar?.color else { continue }
            // Un evento de varios días marca cada día que ocupa
            var day = cal.startOfDay(for: ev.startDate)
            let last = cal.startOfDay(for: ev.endDate.addingTimeInterval(ev.isAllDay ? -1 : 0))
            while day <= last {
                let color = Color(nsColor: calColor)
                if !(dots[day]?.contains(color) ?? false), (dots[day]?.count ?? 0) < 3 {
                    dots[day, default: []].append(color)
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        monthDots = dots
        if let d = selectedDay { loadDay(d) }
    }

    func shiftMonth(_ delta: Int) {
        guard let d = gridCalendar.date(byAdding: .month, value: delta, to: monthAnchor) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            monthAnchor = d
            selectedDay = nil
        }
        loadMonth()
    }

    func goToToday() {
        withAnimation(.easeInOut(duration: 0.2)) {
            monthAnchor = Date()
            selectedDay = nil
        }
        loadMonth()
    }

    func selectDay(_ date: Date) {
        loadDay(date)
        withAnimation(.easeInOut(duration: 0.2)) { selectedDay = date }
    }

    private func loadDay(_ date: Date) {
        let cal = gridCalendar
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        let now = Date()
        dayItems = eventStore.events(matching: eventStore.predicateForEvents(withStart: start, end: end, calendars: nil))
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map { makeItem($0, now: now, showDay: false) }
    }

    /// Días a mostrar (semanas completas que cubren el mes).
    func gridDays() -> [Date] {
        let cal = gridCalendar
        guard let interval = cal.dateInterval(of: .month, for: monthAnchor),
              let firstWeek = cal.dateInterval(of: .weekOfMonth, for: interval.start),
              let lastWeek = cal.dateInterval(of: .weekOfMonth, for: interval.end.addingTimeInterval(-1)) else { return [] }
        var days: [Date] = []
        var d = firstWeek.start
        while d < lastWeek.end {
            days.append(d)
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return days
    }
}

// MARK: - Vistas

/// Cabecera de la vista de mes: ‹ Noviembre 2026 ›
struct MonthHeader: View {
    @EnvironmentObject var calendar: CalendarService

    var body: some View {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.setLocalizedDateFormatFromTemplate("LLLL")
        let title = f.string(from: calendar.monthAnchor).capitalized(with: AppLanguage.locale)

        return HStack(spacing: 2) {
            if let day = calendar.selectedDay {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { calendar.selectedDay = nil }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                        Text(day, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(Color.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                arrow("chevron.left") { calendar.shiftMonth(-1) }
                Button { calendar.goToToday() } label: {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(minWidth: 62)
                }
                .buttonStyle(.plain)
                .help(L("month.today"))
                arrow("chevron.right") { calendar.shiftMonth(1) }
            }
        }
    }

    private func arrow(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.7))
                .frame(width: 16, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MonthGridView: View {
    @EnvironmentObject var calendar: CalendarService

    var body: some View {
        if calendar.selectedDay != nil {
            dayList
        } else {
            grid
        }
    }

    private var grid: some View {
        let cal = calendar.gridCalendar
        let days = calendar.gridDays()
        let symbols = rotatedWeekdaySymbols(cal)
        let rows = max(1, days.count / 7)
        let month = cal.component(.month, from: calendar.monthAnchor)

        return VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, s in
                    Text(s)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { c in
                        let idx = r * 7 + c
                        if idx < days.count {
                            DayCell(date: days[idx],
                                    inMonth: cal.component(.month, from: days[idx]) == month,
                                    isToday: cal.isDateInToday(days[idx]),
                                    dots: calendar.monthDots[cal.startOfDay(for: days[idx])] ?? [])
                        }
                    }
                }
            }
        }
    }

    private var dayList: some View {
        VStack(alignment: .leading, spacing: 7) {
            if calendar.dayItems.isEmpty {
                Text(L("month.noEvents"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.55))
            } else {
                ForEach(calendar.dayItems.prefix(3)) { item in
                    EventRow(item: item)
                }
                if calendar.dayItems.count > 3 {
                    Text(L("month.more", calendar.dayItems.count - 3))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.primary.opacity(0.5))
                }
            }
        }
        .transition(.opacity)
    }

    private func rotatedWeekdaySymbols(_ cal: Calendar) -> [String] {
        let s = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(s[first...] + s[..<first])
    }
}

struct DayCell: View {
    @EnvironmentObject var calendar: CalendarService
    let date: Date
    let inMonth: Bool
    let isToday: Bool
    let dots: [Color]

    var body: some View {
        let day = calendar.gridCalendar.component(.day, from: date)
        Button { calendar.selectDay(date) } label: {
            VStack(spacing: 1) {
                Text("\(day)")
                    .font(.system(size: 10, weight: isToday ? .bold : .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(isToday ? Color.white : Color.primary.opacity(inMonth ? 0.88 : 0.3))
                    .frame(width: 17, height: 13)
                    .background(Circle().fill(isToday ? Color.red : Color.clear).frame(width: 15, height: 15))
                HStack(spacing: 1.5) {
                    ForEach(Array(dots.enumerated()), id: \.offset) { _, c in
                        Circle().fill(c.opacity(inMonth ? 1 : 0.4)).frame(width: 3, height: 3)
                    }
                }
                .frame(height: 3)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 17)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
