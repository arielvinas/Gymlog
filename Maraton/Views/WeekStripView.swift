//
//  WeekStripView.swift
//  Maraton
//
//  Tira de la semana (lunes a domingo) del día seleccionado. Resalta el día
//  elegido y permite saltar a otro día del plan tocándolo. Un puntito turquesa
//  marca los días en que se tomó la creatina.
//

import SwiftUI
import SwiftData

struct WeekStripView: View {
    let days: [WorkoutDay]
    let selectedDate: Date
    var today: Date = Date()
    var onSelect: (Date) -> Void

    @Query(sort: \SupplementLog.date) private var logs: [SupplementLog]

    private static let letters = ["L", "M", "M", "J", "V", "S", "D"]

    /// Las siete fechas de la semana calendario que contiene el día seleccionado.
    private var weekDates: [Date] {
        let cal = PlanConstants.calendar
        guard let start = cal.dateInterval(of: .weekOfYear, for: selectedDate)?.start else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        let cal = PlanConstants.calendar
        HStack(spacing: 0) {
            ForEach(Array(weekDates.enumerated()), id: \.offset) { index, date in
                let workout = DailyPlanInfo.workout(in: days, on: date)
                VStack(spacing: 6) {
                    Text(Self.letters[index])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    DayBubble(
                        date: date,
                        workout: workout,
                        isSelected: cal.isDate(date, inSameDayAs: selectedDate),
                        isToday: cal.isDate(date, inSameDayAs: today),
                        creatineTaken: SupplementTracker.isTaken(.creatina, on: date, logs: logs)
                    )
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .opacity(workout == nil ? 0.4 : 1)
                .onTapGesture {
                    if let workout { onSelect(workout.date) }
                }
            }
        }
    }
}

// MARK: - Burbuja de cada día

private struct DayBubble: View {
    let date: Date
    let workout: WorkoutDay?
    let isSelected: Bool
    let isToday: Bool
    var creatineTaken: Bool = false

    private var isRest: Bool { workout == nil || workout?.type == .descanso }
    private var isCompleted: Bool { workout?.isCompleted == true }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Circle().strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
                    )
                content
            }
            // Punto de creatina: visible solo si se tomó ese día (reserva el
            // espacio siempre para que la fila no salte).
            Circle()
                .fill(SupplementKind.creatina.color)
                .frame(width: 5, height: 5)
                .opacity(creatineTaken ? 1 : 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isCompleted {
            Image(systemName: "checkmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.green)
        } else if isSelected || isToday {
            Text("\(PlanConstants.calendar.component(.day, from: date))")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.accentColor)
        } else {
            Image(systemName: isRest ? "moon.zzz.fill" : (workout?.type.symbolName ?? "figure.run"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var fill: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if isCompleted { return .green.opacity(0.22) }
        if isToday { return Color.accentColor.opacity(0.08) }
        return Color(.tertiarySystemFill)
    }
}

#Preview {
    WeekStripView(days: [], selectedDate: Date()) { _ in }
        .padding()
        .modelContainer(PreviewData.container)
}
