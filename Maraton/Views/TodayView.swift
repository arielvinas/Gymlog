//
//  TodayView.swift
//  Maraton
//
//  Pantalla de aterrizaje: respuesta inmediata sobre qué hacer hoy.
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(sort: \WorkoutDay.date) private var days: [WorkoutDay]

    private var todayWorkout: WorkoutDay? {
        DailyPlanInfo.workout(in: days)
    }

    /// Última corrida registrada con distancia, para la tarjeta de resumen.
    private var lastRun: WorkoutDay? {
        days
            .filter { $0.isCompleted && $0.type.isRun && ($0.actualKm ?? 0) > 0 }
            .max { $0.date < $1.date }
    }

    private var weekStreak: Int {
        StreakCalculator.currentWeekStreak(days: days)
    }

    private var projection: RaceProjection? {
        let runs = RaceProjectionBuilder.samples(from: days)
        return AveragePaceProjection().project(from: runs, today: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TodayHeader()
                    WeekStripView(days: days)
                    TodayHeroCard(day: todayWorkout)
                    QuickStatsRow(
                        weekStreak: weekStreak,
                        weekActualKm: WeeklyVolume.actualKm(among: days),
                        weekPlannedKm: WeeklyVolume.plannedKm(among: days),
                        projection: projection
                    )
                    if let lastRun {
                        LastRunCard(run: lastRun)
                    }
                    SupplementsTodayCard()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Encabezado de la pantalla

private struct TodayHeader: View {
    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().weekdayDayMonth)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Text("Hoy")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
            }
            Spacer()
            countdownPill
        }
    }

    private var countdownPill: some View {
        Label("Córdoba · \(PlanConstants.daysUntilRace()) días", systemImage: "flag.checkered")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.red.opacity(0.15)))
    }
}

// MARK: - Tarjeta hero "¿Qué hago hoy?"

private struct TodayHeroCard: View {
    let day: WorkoutDay?

    private var accent: Color {
        day?.type.color ?? .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let day {
                Label(day.type.displayName, systemImage: day.type.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)

                Text(day.type == .descanso ? day.todayHeadline : day.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                subtitle(for: day)

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
            } else {
                Text("Hoy no hay entrenamiento programado")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Aprovechá para descansar o hacer movilidad suave.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
    private func subtitle(for day: WorkoutDay) -> some View {
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
    let projection: RaceProjection?

    private var weekValue: String {
        weekPlannedKm > 0
            ? "\(weekActualKm.formattedKm)/\(weekPlannedKm.formattedKm) km"
            : "\(weekActualKm.formattedKm) km"
    }

    var body: some View {
        HStack(spacing: 12) {
            QuickStat(title: "Racha", value: "\(weekStreak) sem")
            QuickStat(title: "Semana", value: weekValue)
            QuickStat(title: "Proyección",
                      value: projection.map { $0.timeHalfSeconds.formattedRaceTime } ?? "—")
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
    TodayView()
        .modelContainer(PreviewData.container)
}
