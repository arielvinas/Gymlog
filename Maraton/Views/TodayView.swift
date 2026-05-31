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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TodayHeroCard(day: todayWorkout)
                    SupplementsTodayCard()
                }
                .padding()
            }
            .navigationTitle("Hoy")
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - Tarjeta hero "¿Qué hago hoy?"

private struct TodayHeroCard: View {
    let day: WorkoutDay?

    private var accent: Color {
        day?.type.color ?? .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let day {
                Text(day.todayHeadline)
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                objectiveBlock(for: day)

                HStack {
                    StatusBadge(status: day.dailyStatus)
                    Spacer()
                    if day.dailyStatus != .rest {
                        NavigationLink {
                            WorkoutDetailView(day: day)
                        } label: {
                            Label(day.isCompleted ? "Ver detalle" : "Ver entrenamiento",
                                  systemImage: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .labelStyle(.titleAndIcon)
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
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(accent.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(accent.opacity(0.30), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Text(Date().longDate)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
            Label("\(PlanConstants.daysUntilRace()) días", systemImage: "flag.checkered")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func objectiveBlock(for day: WorkoutDay) -> some View {
        HStack(spacing: 10) {
            Image(systemName: day.type.symbolName)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Objetivo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(day.objective)
                    .font(.headline)
            }
        }
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
