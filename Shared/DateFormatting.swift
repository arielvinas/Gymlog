//
//  DateFormatting.swift
//  Maraton
//
//  Helpers de formato de fecha en español (es-AR).
//

import Foundation

extension Date {
    private static let esAR = Locale(identifier: "es_AR")

    /// Ej. "Vie 30 may".
    var weekdayAndDay: String {
        let formatter = DateFormatter()
        formatter.locale = Date.esAR
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: self).capitalizedFirst
    }

    /// Ej. "30 may".
    var dayMonth: String {
        let formatter = DateFormatter()
        formatter.locale = Date.esAR
        formatter.dateFormat = "d MMM"
        return formatter.string(from: self)
    }

    /// Ej. "Viernes 30 de mayo de 2026".
    var longDate: String {
        let formatter = DateFormatter()
        formatter.locale = Date.esAR
        formatter.dateFormat = "EEEE d 'de' MMMM 'de' yyyy"
        return formatter.string(from: self).capitalizedFirst
    }

    /// Ej. "Sábado 31 de mayo" (sin año, para el encabezado de Hoy).
    var weekdayDayMonth: String {
        let formatter = DateFormatter()
        formatter.locale = Date.esAR
        formatter.dateFormat = "EEEE d 'de' MMMM"
        return formatter.string(from: self).capitalizedFirst
    }

    /// Ej. "jueves" (día de la semana, en minúscula para usar dentro de una frase).
    var weekdayName: String {
        let formatter = DateFormatter()
        formatter.locale = Date.esAR
        formatter.dateFormat = "EEEE"
        return formatter.string(from: self)
    }
}

extension String {
    /// Devuelve la cadena con la primera letra en mayúscula.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
