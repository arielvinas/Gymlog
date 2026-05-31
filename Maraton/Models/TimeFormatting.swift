//
//  TimeFormatting.swift
//  Maraton
//
//  Formato de duraciones a partir de segundos.
//

import Foundation

extension Double {
    /// Interpreta el valor como segundos y lo formatea como duración de carrera
    /// (ej. 3360 → "56 min", 7320 → "2h 02 min").
    var formattedRaceTime: String {
        let total = Int(rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return String(format: "%dh %02d min", hours, minutes)
        }
        return "\(minutes) min"
    }
}
