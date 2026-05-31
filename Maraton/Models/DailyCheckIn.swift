//
//  DailyCheckIn.swift
//  Maraton
//
//  Registro subjetivo diario de recuperación (energía, dolor, motivación).
//

import Foundation
import SwiftData

@Model
final class DailyCheckIn {
    /// Día del check-in (normalizado a las 00:00 para ser único por jornada).
    /// Nota: al activar CloudKit hay que quitar `.unique` (no lo admite).
    @Attribute(.unique) var date: Date = Date()

    /// Nivel de energía (1-5).
    var energy: Int = 3

    /// Dolor muscular percibido (1-5, mayor = más dolor).
    var soreness: Int = 3

    /// Motivación (1-5).
    var motivation: Int = 3

    init(date: Date, energy: Int, soreness: Int, motivation: Int) {
        self.date = date
        self.energy = energy
        self.soreness = soreness
        self.motivation = motivation
    }
}
