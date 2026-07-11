//
//  DayDetailView.swift
//  Maraton
//
//  Vista detallada de un día del plan. Se puede deslizar horizontalmente entre
//  todos los días del plan (o saltar tocando un día en la tira de la semana) y
//  muestra, para el día elegido, el entrenamiento, los datos de su semana, la
//  última corrida hasta ese día y los suplementos.
//

import SwiftUI
import SwiftData

struct DayDetailView: View {
    @Query(sort: \WorkoutDay.date) private var days: [WorkoutDay]

    var body: some View {
        NavigationStack {
            Group {
                if days.isEmpty {
                    ContentUnavailableView("Sin plan cargado", systemImage: "calendar")
                } else {
                    DayPager(days: days, initialDate: initialDate)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Día a mostrar al abrir: hoy si está en el plan; si no, el más cercano.
    private var initialDate: Date {
        if let today = DailyPlanInfo.workout(in: days)?.date { return today }
        let now = Date()
        let nearest = days.min {
            abs($0.date.timeIntervalSince(now)) < abs($1.date.timeIntervalSince(now))
        }
        return nearest?.date ?? now
    }
}

// MARK: - Carrusel de días

private struct DayPager: View {
    let days: [WorkoutDay]
    @State private var selection: Date

    init(days: [WorkoutDay], initialDate: Date) {
        self.days = days
        _selection = State(initialValue: initialDate)
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 16) {
                DetailHeader(date: selection)
                WeekStripView(days: days, selectedDate: selection) { date in
                    withAnimation { selection = date }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            TabView(selection: $selection) {
                ForEach(days) { day in
                    ScrollView {
                        DayContent(day: day, allDays: days)
                            .padding(.horizontal)
                            .padding(.bottom, 24)
                    }
                    .tag(day.date)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }
}

// MARK: - Encabezado

private struct DetailHeader: View {
    let date: Date

    private var isToday: Bool {
        PlanConstants.calendar.isDate(date, inSameDayAs: Date())
    }

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(date.dayMonth.capitalizedFirst)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Text(isToday ? "Hoy" : date.weekdayName.capitalizedFirst)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
            }
            Spacer()
        }
    }
}

// MARK: - Contenido de un día

private struct DayContent: View {
    let day: WorkoutDay
    let allDays: [WorkoutDay]

    private var cal: Calendar { PlanConstants.calendar }
    private var isToday: Bool { cal.isDate(day.date, inSameDayAs: Date()) }
    private var isFuture: Bool {
        cal.startOfDay(for: day.date) > cal.startOfDay(for: Date())
    }

    /// Racha de semanas con actividad hasta el día seleccionado.
    private var weekStreak: Int {
        StreakCalculator.currentWeekStreak(days: allDays, today: day.date)
    }

    /// Tonelaje de gimnasio de la semana del día seleccionado.
    private var weekTonnage: Double {
        WeeklyVolume.tonnage(for: day.date, among: allDays.flatMap(\.orderedExercises))
    }

    /// Última corrida registrada hasta el día seleccionado (incluido).
    private var lastRun: WorkoutDay? {
        allDays
            .filter { $0.isCompleted && $0.type.isRun && ($0.actualKm ?? 0) > 0 && $0.date <= day.date }
            .max { $0.date < $1.date }
    }

    var body: some View {
        VStack(spacing: 16) {
            DayHeroCard(day: day, isToday: isToday)

            QuickStatsRow(
                weekStreak: weekStreak,
                weekActualKm: WeeklyVolume.actualKm(for: day.date, among: allDays),
                weekPlannedKm: WeeklyVolume.plannedKm(for: day.date, among: allDays),
                weekTonnage: weekTonnage
            )

            if let lastRun {
                LastRunCard(run: lastRun)
            }

            // Los suplementos se registran para hoy o días pasados (por si me
            // olvidé de marcarlos); a futuro no tiene sentido.
            if !isFuture {
                SupplementsTodayCard(date: day.date)
            }
        }
    }
}

// MARK: - Tarjeta hero "¿Qué toca?"

private struct DayHeroCard: View {
    let day: WorkoutDay
    let isToday: Bool

    private var accent: Color { day.type.color }

    private var headline: String {
        if day.type == .descanso {
            return isToday ? "Hoy es día de descanso" : "Día de descanso"
        }
        return day.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(day.type.displayName, systemImage: day.type.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)

            Text(headline)
                .font(.system(size: 28, weight: .bold, design: .rounded))

            subtitle

            HStack {
                StatusBadge(status: day.dailyStatus)
                Spacer()
                if day.dailyStatus != .rest {
                    NavigationLink {
                        WorkoutDetailView(day: day)
                    } label: {
                        HStack(spacing: 4) {
                            Text(day.isCompleted ? "Ver detalle" : "Ver entrenamiento")
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(accent.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(accent.opacity(0.30), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var subtitle: some View {
        if day.type == .descanso {
            Text("Aprovechá para descansar o hacer movilidad suave.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if !day.detail.isEmpty {
            Text(day.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Fila de datos rápidos

private struct QuickStatsRow: View {
    let weekStreak: Int
    let weekActualKm: Double
    let weekPlannedKm: Double
    let weekTonnage: Double

    private var weekValue: String {
        weekPlannedKm > 0
            ? "\(weekActualKm.formattedKm)/\(weekPlannedKm.formattedKm) km"
            : "\(weekActualKm.formattedKm) km"
    }

    var body: some View {
        HStack(spacing: 12) {
            QuickStat(title: "Racha", value: "\(weekStreak) sem")
            QuickStat(title: "Semana", value: weekValue)
            QuickStat(title: "Gimnasio",
                      value: weekTonnage > 0 ? "\(weekTonnage.formattedKg) kg" : "—")
        }
    }
}

private struct QuickStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .dashboardCard()
    }
}

// MARK: - Badge de estado

struct StatusBadge: View {
    let status: DailyStatus

    var body: some View {
        Label(status.label, systemImage: status.symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(status.color.opacity(0.15)))
    }
}

#Preview {
    DayDetailView()
        .modelContainer(PreviewData.container)
}
