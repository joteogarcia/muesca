import SwiftUI
import AppKit

// Agenda por días: una tira de días que se desplaza con el trackpad (o con clic),
// con el día elegido en el centro y sus eventos debajo.
// Sustituye a la lista de «próximos eventos»; la vista de mes sigue en MonthGrid.swift.

extension CalendarService {

    /// Día elegido en la tira (hoy si no hay ninguno)
    var stripDay: Date { gridCalendar.startOfDay(for: selectedDay ?? Date()) }

    /// Mueve la tira n días (negativo = hacia atrás)
    func shiftDay(_ delta: Int) {
        guard let d = gridCalendar.date(byAdding: .day, value: delta, to: stripDay) else { return }
        moveStrip(to: d)
    }

    func moveStrip(to date: Date, animated: Bool = true) {
        let cal = gridCalendar
        let day = cal.startOfDay(for: date)
        // Los puntos de color se cargan por meses: recargar al cambiar de mes
        if !cal.isDate(day, equalTo: monthAnchor, toGranularity: .month) || monthDots.isEmpty {
            monthAnchor = day
            loadMonth()
        }
        loadDay(day)
        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { selectedDay = day }
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { selectedDay = day }
        }
    }

    // MARK: Arrastre con el ratón (pinchar y deslizar)

    /// Cambia el día central sin animación y sin consultar el calendario (durante el arrastre)
    private func setCenterQuietly(_ day: Date) {
        let cal = gridCalendar
        if !cal.isDate(day, equalTo: monthAnchor, toGranularity: .month) {
            monthAnchor = day
            loadMonth()     // solo al cambiar de mes: puntos de color
        }
        selectedDay = day
    }

    func stripDragChanged(_ translation: CGFloat, time: Date, cellWidth w: CGFloat) {
        guard w > 0 else { return }
        if !stripDragging {
            stripDragging = true
            stripDragSteps = 0
            stripHoverX = nil
            stripVelocity = 0
            stripDragLastX = 0
            stripDragLastTime = time
        }
        // Velocidad propia (pt/s), suavizada: en el Mac el gesto no la da con ratón
        let dt = time.timeIntervalSince(stripDragLastTime)
        if dt > 0.004 {
            let v = (translation - stripDragLastX) / CGFloat(dt)
            stripVelocity = stripVelocity * 0.4 + v * 0.6
            stripDragLastX = translation
            stripDragLastTime = time
        }
        let steps = Int((-translation / w).rounded())
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            if steps != stripDragSteps,
               let d = gridCalendar.date(byAdding: .day, value: steps - stripDragSteps, to: stripDay) {
                setCenterQuietly(d)
                stripDragSteps = steps
            }
            // Lo que sobra (menos de medio día) desplaza la tira de forma continua
            stripDrag = translation + CGFloat(steps) * w
        }
    }

    func stripDragEnded(cellWidth w: CGFloat) {
        guard w > 0 else { return }
        // Si el ratón llevaba un rato quieto antes de soltar, no hay lanzamiento
        let still = Date().timeIntervalSince(stripDragLastTime) > 0.08
        let v = still ? 0 : stripVelocity
        // Inercia: distancia ≈ velocidad × 0,22 s (máx. 10 días)
        let extra = max(-10, min(10, Int((-v * 0.22 / w).rounded())))
        let cal = gridCalendar
        let target = cal.date(byAdding: .day, value: extra, to: stripDay) ?? stripDay

        // 1) Saltar al día final sin que se note: el desplazamiento compensa el salto
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            setCenterQuietly(cal.startOfDay(for: target))
            stripDrag += CGFloat(extra) * w
            stripDragging = false
        }
        // 2) Rodar hasta él (más días, algo más de recorrido) y encajar con un leve rebote
        let response = 0.38 + min(0.5, 0.045 * Double(abs(extra)))
        withAnimation(.spring(response: response, dampingFraction: 0.8)) {
            stripDrag = 0
        }
        stripDragSteps = 0
        stripVelocity = 0
        loadDay(target)
    }

    /// «Hoy», «Mañana», «Ayer» o «vie 7 nov»
    func stripTitle(for date: Date) -> String {
        let cal = gridCalendar
        if cal.isDateInToday(date) { return L("agenda.today") }
        if cal.isDateInTomorrow(date) { return L("agenda.tomorrow") }
        if cal.isDateInYesterday(date) { return L("agenda.yesterday") }
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f.string(from: date).capitalized(with: AppLanguage.locale)
    }
}

// MARK: - Cabecera: ‹ Hoy ›  (y «Hoy» para volver si te has movido)

struct DayStripHeader: View {
    @EnvironmentObject var calendar: CalendarService

    var body: some View {
        let day = calendar.stripDay
        let isToday = calendar.gridCalendar.isDateInToday(day)
        HStack(spacing: 2) {
            arrow("chevron.left") { calendar.shiftDay(-1) }
            Text(calendar.stripTitle(for: day))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(minWidth: 62)
                .id(day)
                .transition(.opacity)
            arrow("chevron.right") { calendar.shiftDay(1) }
            if !isToday {
                Button { calendar.moveStrip(to: Date()) } label: {
                    Text(L("agenda.today"))
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.red.opacity(0.85)))
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .help(L("month.today"))
                .padding(.leading, 4)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: day)
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

// MARK: - Tira de días + eventos del día

struct DayStripView: View {
    @EnvironmentObject var calendar: CalendarService

    var body: some View {
        let cal = calendar.gridCalendar
        let center = calendar.stripDay
        let days = (-3...3).compactMap { cal.date(byAdding: .day, value: $0, to: center) }

        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { g in
                let visible = 7
                let w = g.size.width / CGFloat(visible)
                // Se pintan 2 días más por cada lado para que entren al arrastrar
                // Días de sobra a cada lado para que se vean rodar al lanzar la tira
                let range = -14...14
                let all = range.compactMap { cal.date(byAdding: .day, value: $0, to: center) }
                HStack(spacing: 0) {
                    ForEach(Array(all.enumerated()), id: \.element) { i, d in
                        // Distancia al centro en días (con decimales mientras se arrastra)
                        let signed = (CGFloat(i + range.lowerBound) * w + calendar.stripDrag) / w
                        let dist = abs(signed)
                        // Lupa tipo Dock (solo sin arrastrar)
                        let lens: CGFloat = {
                            guard !calendar.stripDragging, let x = calendar.stripHoverX else { return 0 }
                            let cx = (CGFloat(i + range.lowerBound + 3) + 0.5) * w + calendar.stripDrag
                            return max(0, 1 - abs(cx - x) / (w * 1.6))
                        }()
                        StripDayCell(date: d,
                                     selected: d == center && !calendar.stripDragging,
                                     isToday: cal.isDateInToday(d),
                                     dots: calendar.monthDots[cal.startOfDay(for: d)] ?? [])
                            .frame(width: w)
                            .opacity(max(Double(max(0.15, 1 - dist * 0.22)), 0.4 + 0.6 * Double(lens)))
                            .scaleEffect(max(0.78, 1 - dist * 0.05) + 0.22 * lens, anchor: .bottom)
                            // Efecto tambor: los días giran al alejarse del centro
                            .rotation3DEffect(.degrees(Double(max(-3, min(3, signed))) * -14),
                                              axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                            .zIndex(Double(lens) - Double(dist))
                    }
                }
                .frame(width: w * CGFloat(all.count), height: g.size.height)
                .offset(x: CGFloat(range.lowerBound + 3) * w + calendar.stripDrag)
                .frame(width: g.size.width, height: g.size.height, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let p): if !calendar.stripDragging { calendar.stripHoverX = p.x }
                    case .ended: calendar.stripHoverX = nil
                    }
                }
                // Prioridad alta: si el ratón se mueve, es arrastre; si no, el clic llega al día
                .highPriorityGesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .local)
                        .onChanged { v in calendar.stripDragChanged(v.translation.width, time: v.time, cellWidth: w) }
                        .onEnded { _ in calendar.stripDragEnded(cellWidth: w) }
                )
                .animation(.easeOut(duration: 0.14), value: calendar.stripHoverX)
            }
            .frame(height: 50)
            // Deslizar con dos dedos: cada ~40 pt, un día
            .background(StripScrollCatcher { step in calendar.shiftDay(step) })

            dayEvents
        }
        // Al abrir la isla, siempre empieza en hoy
        .onAppear { calendar.moveStrip(to: Date()) }
    }

    private var dayEvents: some View {
        VStack(alignment: .leading, spacing: 7) {
            if calendar.dayItems.isEmpty {
                Text(L("month.noEvents"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.55))
            } else {
                ForEach(calendar.dayItems.prefix(2)) { item in
                    EventRow(item: item)
                }
                if calendar.dayItems.count > 2 {
                    Text(L("month.more", calendar.dayItems.count - 2))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.primary.opacity(0.5))
                }
            }
        }
        .id(calendar.stripDay)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: calendar.stripDay)
    }
}

struct StripDayCell: View {
    @EnvironmentObject var calendar: CalendarService
    let date: Date
    let selected: Bool
    let isToday: Bool
    let dots: [Color]

    var body: some View {
        let cal = calendar.gridCalendar
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let weekday = symbols[(cal.component(.weekday, from: date) - 1) % symbols.count]

        VStack(spacing: 2) {
                Text(weekday.uppercased())
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(selected ? 0.75 : 0.45))
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 13.5, weight: selected ? .bold : .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(isToday ? (selected ? Color.white : Color.red) : Color.primary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(isToday && selected ? Color.red : Color.clear))
                HStack(spacing: 2) {
                    ForEach(Array(dots.enumerated()), id: \.offset) { _, c in
                        Circle().fill(c).frame(width: 3.5, height: 3.5)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(selected ? 0.14 : 0))
            )
            .contentShape(Rectangle())
            .onTapGesture { calendar.moveStrip(to: date) }
    }
}

// MARK: - Desplazamiento continuo con el trackpad

/// A diferencia de SwipeCatcher (un paso por gesto), aquí cada tramo del
/// desplazamiento avanza un día, así que un deslizamiento largo recorre varios.
final class StripScrollView: NSView {
    var onStep: ((Int) -> Void)?
    private var accumulated: CGFloat = 0
    private let threshold: CGFloat = 40

    override func hitTest(_ point: NSPoint) -> NSView? {
        NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
    }

    override func scrollWheel(with e: NSEvent) {
        if e.phase == .began { accumulated = 0 }
        // Ratón con rueda: cada «clic» de rueda, un día
        guard e.hasPreciseScrollingDeltas else {
            let d = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) ? e.scrollingDeltaX : e.scrollingDeltaY
            if d != 0 { onStep?(d < 0 ? 1 : -1) }
            return
        }
        guard abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) else { super.scrollWheel(with: e); return }
        // La inercia (momentum) no cuenta: solo el movimiento de los dedos
        guard e.momentumPhase == [] else { return }
        accumulated += e.scrollingDeltaX
        while abs(accumulated) >= threshold {
            let step = accumulated < 0 ? 1 : -1
            onStep?(step)
            accumulated += accumulated < 0 ? threshold : -threshold
        }
        if e.phase == .ended || e.phase == .cancelled { accumulated = 0 }
    }
}

struct StripScrollCatcher: NSViewRepresentable {
    let onStep: (Int) -> Void
    func makeNSView(context: Context) -> StripScrollView {
        let v = StripScrollView()
        v.onStep = onStep
        return v
    }
    func updateNSView(_ v: StripScrollView, context: Context) { v.onStep = onStep }
}
