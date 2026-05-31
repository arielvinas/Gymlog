//
//  StreakCalculator.swift
//  Maraton
//
//  Cálculo de rachas de consistencia. Reutilizable para badges y logros.
//

import Foundation

enum StreakCalculator {
    /// Semanas consecutivas (hasta hoy) con al menos un entrenamiento completado.
    /// Enfoque elegido por ser el más sólido frente a los días de descanso del plan.
    static func currentWeekStreak(days: [WorkoutDay], today: Date = Date()) -> Int {
        let cal = PlanConstants.calendar
        let todayStart = cal.startOfDay(for: today)

        // Una entrada por semana del plan: fecha de inicio y si tuvo actividad.
        let weeks = Dictionary(grouping: days, by: { $0.weekTitle }).values
            .map { semana -> (start: Date, completed: Bool) in
                let start = semana.map(\.date).min() ?? .distantPast
                let completed = semana.contains { $0.isCompleted }
                return (start, completed)
            }
            .filter { cal.startOfDay(for: $0.start) <= todayStart }
            .sorted { $0.start < $1.start }

        // Cuenta hacia atrás desde la última semana con actividad. Esto ignora
        // una semana en curso que todavía no tiene entrenamientos cargados.
        guard let lastActive = weeks.lastIndex(where: { $0.completed }) else { return 0 }
        var streak = 0
        var i = lastActive
        while i >= 0 && weeks[i].completed {
            streak += 1
            i -= 1
        }
        return streak
    }

    /// Días consecutivos (hasta hoy) sin saltarse entrenamientos. Los días de
    /// descanso no cuentan ni cortan; un día de hoy aún pendiente no corta.
    /// Disponible para futuros badges basados en días.
    static func currentDayStreak(days: [WorkoutDay], today: Date = Date()) -> Int {
        let cal = PlanConstants.calendar
        let todayStart = cal.startOfDay(for: today)

        let past = days
            .filter { cal.startOfDay(for: $0.date) <= todayStart }
            .sorted { $0.date > $1.date }

        var streak = 0
        for day in past {
            if day.type == .descanso { continue }
            if day.isCompleted {
                streak += 1
            } else if cal.isDate(day.date, inSameDayAs: today) {
                continue // hoy todavía puede completarse
            } else {
                break
            }
        }
        return streak
    }
}
