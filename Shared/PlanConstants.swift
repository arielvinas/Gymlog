//
//  PlanConstants.swift
//  Maraton
//
//  Constantes y utilidades de fecha del plan de entrenamiento.
//

import Foundation

enum PlanConstants {
    /// Fecha de la carrera: Media Maratón Córdoba, 5 de julio de 2026.
    static let raceDate: Date = DateComponents.makeDate(year: 2026, month: 7, day: 5)

    /// Distancia de la carrera en kilómetros.
    static let raceDistanceKm: Double = 21.1

    /// Calendario configurado para es-AR (la semana empieza el lunes).
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "es_AR")
        cal.firstWeekday = 2 // lunes
        return cal
    }

    /// Días restantes hasta la carrera (nunca negativo).
    static func daysUntilRace(from date: Date = Date()) -> Int {
        let cal = calendar
        let today = cal.startOfDay(for: date)
        let race = cal.startOfDay(for: raceDate)
        let diff = cal.dateComponents([.day], from: today, to: race).day ?? 0
        return max(diff, 0)
    }
}

extension DateComponents {
    /// Crea una fecha a mediodía para evitar problemas de zona horaria.
    static func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return PlanConstants.calendar.date(from: components) ?? Date()
    }
}
