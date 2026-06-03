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

extension Int {
    /// Formatea segundos como descanso legible (ej. 45 → "45 s", 90 → "1:30 min",
    /// 120 → "2 min").
    var restLabel: String {
        if self < 60 { return "\(self) s" }
        if self % 60 == 0 { return "\(self / 60) min" }
        return String(format: "%d:%02d min", self / 60, self % 60)
    }

    /// Formatea segundos como cuenta regresiva (ej. 90 → "1:30", 5 → "0:05").
    var countdownLabel: String {
        String(format: "%d:%02d", self / 60, self % 60)
    }
}
