//
//  SupplementLog.swift
//  Maraton
//
//  Registro de toma de un suplemento en un día. Su presencia indica
//  que el suplemento fue tomado esa jornada.
//

import Foundation
import SwiftData

@Model
final class SupplementLog {
    /// Día de la toma (normalizado a las 00:00).
    var date: Date = Date()

    /// Suplemento tomado.
    var kind: SupplementKind = SupplementKind.creatina

    init(date: Date, kind: SupplementKind) {
        self.date = date
        self.kind = kind
    }
}
