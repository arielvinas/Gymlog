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
}

extension String {
    /// Devuelve la cadena con la primera letra en mayúscula.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
