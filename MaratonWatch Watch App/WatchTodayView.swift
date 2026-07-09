//
//  WatchTodayView.swift
//  MaratonWatch Watch App
//
//  Pantalla de inicio del reloj: un carrusel deslizable de días del plan que
//  arranca en hoy. Cada día muestra qué toca (tocable para ir al entrenamiento)
//  y el marcado rápido de suplementos. Reutiliza `DailyPlanInfo` y
//  `SupplementTracker` del código compartido.
//

import SwiftUI
import SwiftData

struct WatchTodayView: View {
    @Query(sort: \WorkoutDay.date) private var days: [WorkoutDay]
    @Query(sort: \SupplementLog.date) private var logs: [SupplementLog]

    @State private var selection = 0
    @State private var didInit = false

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(days.indices, id: \.self) { i in
                    WatchDayPage(day: days[i], logs: logs)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationTitle(navTitle)
            .onAppear(perform: selectTodayOnce)
        }
    }

    private var navTitle: String {
        guard days.indices.contains(selection) else { return "GymLog" }
        return Calendar.current.isDateInToday(days[selection].date)
            ? "Hoy"
            : days[selection].date.weekdayAndDay
    }

    /// Selecciona el día de hoy (o el próximo) la primera vez que aparece.
    private func selectTodayOnce() {
        guard !didInit, !days.isEmpty else { return }
        let cal = Calendar.current
        if let i = days.firstIndex(where: { cal.isDateInToday($0.date) }) {
            selection = i
        } else {
            let start = cal.startOfDay(for: Date())
            selection = days.firstIndex(where: { $0.date >= start }) ?? (days.count - 1)
        }
        didInit = true
    }
}

// MARK: - Página de un día

private struct WatchDayPage: View {
    let day: WorkoutDay
    let logs: [SupplementLog]
    @Environment(\.modelContext) private var context

    private var tint: Color { day.type.color }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(headerText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    WatchWorkoutView(day: day)
                } label: {
                    workoutCard
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Suplementos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(SupplementKind.allCases) { kind in
                        WatchSupplementRow(
                            kind: kind,
                            taken: SupplementTracker.isTaken(kind, on: day.date, logs: logs),
                            streak: SupplementTracker.currentStreak(kind, logs: logs, today: day.date)
                        ) {
                            SupplementTracker.toggle(kind, on: day.date, logs: logs, context: context)
                        }
                    }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
    }

    private var headerText: String {
        if Calendar.current.isDateInToday(day.date) {
            return "Hoy · Córdoba en \(PlanConstants.daysUntilRace())d"
        }
        return day.date.weekdayAndDay
    }

    private var workoutCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(day.type.displayName, systemImage: day.type.symbolName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            Text(day.type == .descanso ? day.todayHeadline : day.title)
                .font(.headline)
                .multilineTextAlignment(.leading)
            HStack(spacing: 4) {
                Image(systemName: day.dailyStatus.symbolName)
                Text(day.dailyStatus.label)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(day.dailyStatus.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.18)))
    }
}

// MARK: - Fila de suplemento

private struct WatchSupplementRow: View {
    let kind: SupplementKind
    let taken: Bool
    let streak: Int
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: kind.symbolName)
                    .foregroundStyle(kind.color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.displayName)
                        .font(.body)
                    Text(streak > 0
                         ? "🔥 \(streak) \(streak == 1 ? "día" : "días")"
                         : (taken ? "Tomado" : "Pendiente"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: taken ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(taken ? kind.color : .secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}
