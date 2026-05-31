//
//  WeeklyVolume.swift
//  Maraton
//
//  Volumen semanal: km planificados (leídos del texto del plan) vs km reales.
//

import Foundation

extension WorkoutDay {
    /// Kilómetros planificados, extraídos del texto del plan (título + detalle).
    /// Ej. "Fondo largo 12 km" → 12; "Fondo 13-14 km" → 13,5; sin km → nil.
    var plannedKm: Double? {
        PlannedDistance.parse("\(title) \(detail)")
    }
}

/// Extrae los kilómetros planificados del texto libre del plan (es-AR).
enum PlannedDistance {
    /// Un número (con coma o punto decimal), opcionalmente como rango, seguido de "km".
    private static let regex = try! NSRegularExpression(
        pattern: #"(\d+(?:[.,]\d+)?)(?:\s*[-–]\s*(\d+(?:[.,]\d+)?))?\s*km"#,
        options: [.caseInsensitive]
    )

    static func parse(_ text: String) -> Double? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let low = number(at: 1, in: match, text: text) else { return nil }

        // Si viene como rango ("13-14 km"), usa el promedio como objetivo.
        if let high = number(at: 2, in: match, text: text) {
            return (low + high) / 2
        }
        return low
    }

    private static func number(at index: Int, in match: NSTextCheckingResult, text: String) -> Double? {
        guard let r = Range(match.range(at: index), in: text) else { return nil }
        return Double(text[r].replacingOccurrences(of: ",", with: "."))
    }
}

/// Suma de kilómetros por semana calendario (lunes a domingo).
enum WeeklyVolume {
    /// Km planificados de todos los días de la semana que contiene `date`.
    static func plannedKm(for date: Date = Date(), among days: [WorkoutDay]) -> Double {
        daysInWeek(of: date, among: days).compactMap(\.plannedKm).reduce(0, +)
    }

    /// Km reales registrados en los días completados de esa semana.
    static func actualKm(for date: Date = Date(), among days: [WorkoutDay]) -> Double {
        daysInWeek(of: date, among: days)
            .compactMap { $0.isCompleted ? $0.actualKm : nil }
            .reduce(0, +)
    }

    private static func daysInWeek(of date: Date, among days: [WorkoutDay]) -> [WorkoutDay] {
        let cal = PlanConstants.calendar
        return days.filter { cal.isDate($0.date, equalTo: date, toGranularity: .weekOfYear) }
    }
}
