//
//  SupplementTracker.swift
//  Maraton
//
//  Lógica de seguimiento de suplementos: toma diaria, adherencia y rachas.
//

import Foundation
import SwiftData

enum SupplementTracker {
    private static var cal: Calendar { PlanConstants.calendar }

    /// Indica si el suplemento fue tomado en la fecha dada.
    static func isTaken(_ kind: SupplementKind, on date: Date, logs: [SupplementLog]) -> Bool {
        logs.contains { $0.kind == kind && cal.isDate($0.date, inSameDayAs: date) }
    }

    /// Alterna la toma del suplemento para la fecha: la registra o la quita.
    static func toggle(_ kind: SupplementKind, on date: Date, logs: [SupplementLog], context: ModelContext) {
        let dayStart = cal.startOfDay(for: date)
        if let existente = logs.first(where: { $0.kind == kind && cal.isDate($0.date, inSameDayAs: dayStart) }) {
            context.delete(existente)
        } else {
            context.insert(SupplementLog(date: dayStart, kind: kind))
        }
        try? context.save()
    }

    /// Adherencia (0..1) en una ventana de los últimos `days` días, incluyendo hoy.
    static func adherence(_ kind: SupplementKind, lastDays days: Int, logs: [SupplementLog], today: Date = Date()) -> Double {
        guard days > 0 else { return 0 }
        let todayStart = cal.startOfDay(for: today)
        var tomados = 0
        for offset in 0..<days {
            guard let day = cal.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            if isTaken(kind, on: day, logs: logs) { tomados += 1 }
        }
        return Double(tomados) / Double(days)
    }

    /// Racha de días consecutivos tomando el suplemento hasta hoy.
    /// Si hoy todavía no se tomó, la racha se cuenta hasta ayer (no se corta).
    static func currentStreak(_ kind: SupplementKind, logs: [SupplementLog], today: Date = Date()) -> Int {
        let todayStart = cal.startOfDay(for: today)
        var streak = 0
        var day = todayStart

        if !isTaken(kind, on: day, logs: logs) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }

        while isTaken(kind, on: day, logs: logs) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    /// Busca el recordatorio del suplemento o lo crea con valores por defecto.
    static func reminder(for kind: SupplementKind, in reminders: [SupplementReminder], context: ModelContext) -> SupplementReminder {
        if let existente = reminders.first(where: { $0.kind == kind }) {
            return existente
        }
        let nuevo = SupplementReminder(kind: kind, enabled: false, hour: kind.defaultReminderHour)
        context.insert(nuevo)
        try? context.save()
        return nuevo
    }
}
