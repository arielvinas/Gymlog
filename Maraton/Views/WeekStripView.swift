//
//  WeekStripView.swift
//  Maraton
//
//  Tira de la semana (lunes a domingo) con el estado de cada día.
//

import SwiftUI

struct WeekStripView: View {
    let days: [WorkoutDay]
    var today: Date = Date()

    private static let letters = ["L", "M", "M", "J", "V", "S", "D"]

    /// Las siete fechas de la semana calendario que contiene hoy (lunes primero).
    private var weekDates: [Date] {
        let cal = PlanConstants.calendar
        guard let start = cal.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekDates.enumerated()), id: \.offset) { index, date in
                VStack(spacing: 6) {
                    Text(Self.letters[index])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    DayBubble(
                        date: date,
                        workout: DailyPlanInfo.workout(in: days, on: date),
                        isToday: PlanConstants.calendar.isDate(date, inSameDayAs: today)
                    )
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Burbuja de cada día

private struct DayBubble: View {
    let date: Date
    let workout: WorkoutDay?
    let isToday: Bool

    private var isRest: Bool { workout == nil || workout?.type == .descanso }
    private var isCompleted: Bool { workout?.isCompleted == true }

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
                .frame(width: 38, height: 38)
                .overlay(
                    Circle().strokeBorder(Color.accentColor, lineWidth: isToday ? 2 : 0)
                )
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if isToday {
            Text("\(PlanConstants.calendar.component(.day, from: date))")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.accentColor)
        } else if isCompleted {
            Image(systemName: "checkmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.green)
        } else {
            Image(systemName: isRest ? "moon.zzz.fill" : (workout?.type.symbolName ?? "figure.run"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var fill: Color {
        if isToday { return Color.accentColor.opacity(0.15) }
        if isCompleted { return .green.opacity(0.22) }
        return Color(.tertiarySystemFill)
    }
}

#Preview {
    WeekStripView(days: [])
        .padding()
}
