//
//  PlanConstants.swift
//  Maraton
//
//  Constantes y utilidades de fecha del plan de entrenamiento.
//

import Foundation

enum PlanConstants {
    /// Calendario configurado para es-AR (la semana empieza el lunes).
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "es_AR")
        cal.firstWeekday = 2 // lunes
        return cal
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
