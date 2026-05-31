//
//  SupplementReminder.swift
//  Maraton
//
//  Configuración del recordatorio local de un suplemento.
//

import Foundation
import SwiftData

@Model
final class SupplementReminder {
    /// Suplemento al que aplica (uno por tipo).
    var kind: SupplementKind = SupplementKind.creatina

    /// Si el recordatorio está activo.
    var enabled: Bool = false

    /// Hora del recordatorio (0-23).
    var hour: Int = 9

    /// Minuto del recordatorio (0-59).
    var minute: Int = 0

    init(kind: SupplementKind, enabled: Bool = false, hour: Int, minute: Int = 0) {
        self.kind = kind
        self.enabled = enabled
        self.hour = hour
        self.minute = minute
    }
}
