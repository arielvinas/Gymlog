//
//  LiveSessionState.swift
//  Maraton (compartido iOS + watchOS + Widget Extension)
//
//  Modelos serializables del estado de la sesión de gimnasio guiada en vivo y
//  de los comandos para controlarla a distancia. El reloj (autoridad) emite
//  `LiveSessionSnapshot` en cada cambio del engine; el iPhone (espejo) manda
//  `LiveSessionCommand` para avanzar/saltear/corregir. Son Codable puros (solo
//  Foundation) para viajar por WatchConnectivity y por ActivityKit sin arrastrar
//  SwiftData ni UI a la Widget Extension.
//

import Foundation

/// Fase de la sesión, espejo Codable de `GuidedSessionPhase` (que no es Codable
/// para no acoplar el engine a esta capa).
enum LiveSessionPhase: String, Codable, Sendable {
    case logging   // cargando peso/reps de la serie actual
    case resting   // descanso entre series
    case done      // sesión terminada
}

/// Foto del estado de la sesión que el reloj difunde al iPhone. Todo lo que la
/// app y la Live Activity necesitan para dibujar, sin tener que leer SwiftData.
struct LiveSessionSnapshot: Codable, Sendable, Equatable {
    /// Identifica la sesión en curso; descarta snapshots/comandos de otra previa.
    var sessionID: UUID
    /// Fecha del `WorkoutDay` (para mapear al día correcto en cada dispositivo).
    var dayDate: Date

    var phase: LiveSessionPhase

    // Ejercicio / serie actual.
    var exerciseName: String
    var exerciseIndex: Int      // 0-based
    var exerciseCount: Int
    var setNumber: Int          // 1-based (0 si el paso no tiene series)
    var setCount: Int
    var targetReps: String?
    /// Si el ejercicio se carga sin peso (peso corporal/banda/core).
    var isBodyweight: Bool
    /// Si el objetivo se mide en tiempo (segundos) en vez de reps.
    var isTimeBased: Bool

    // Valores cargados de la serie actual (si ya tiene).
    var weight: Double?
    var reps: Int?

    // Descanso: la cuenta regresiva la dibuja cada cliente con `Text(timerInterval:)`
    // a partir de `restEndDate`, así corre sola sin necesidad de updates.
    var restEndDate: Date?
    var restTotal: Int
    var isOvertime: Bool

    // Métricas en vivo / resumen.
    var heartRate: Int?
    var progressFraction: Double
    var loggedSetsCount: Int
    var totalVolume: Double

    /// Marca de tiempo para descartar snapshots fuera de orden.
    var updatedAt: Date

    /// `true` si la sesión sigue activa (no terminó).
    var isActive: Bool { phase != .done }
}

/// Acción remota sobre la sesión, enviada del iPhone al reloj (la autoridad).
enum LiveSessionAction: Codable, Sendable, Equatable {
    case completeCurrent     // "Hecho": marca la serie y avanza
    case skipRest            // "Saltear"/"Empezar serie": corta el descanso
    case goBack              // vuelve a la serie anterior para corregir
    case adjustRest(Int)     // ±segundos al descanso en curso
    case end                 // termina la sesión a distancia
}

/// Comando con su `sessionID` para que el reloj ignore los de sesiones viejas.
struct LiveSessionCommand: Codable, Sendable, Equatable {
    var sessionID: UUID
    var action: LiveSessionAction
    var sentAt: Date

    init(sessionID: UUID, action: LiveSessionAction, sentAt: Date = Date()) {
        self.sessionID = sessionID
        self.action = action
        self.sentAt = sentAt
    }
}

// MARK: - Codificación para WatchConnectivity

/// Claves del diccionario `[String: Any]` que viaja por WCSession. El payload
/// real va como `Data` (JSON) bajo su clave, así no dependemos de que cada tipo
/// sea representable como property-list.
enum LiveSessionWire {
    static let snapshotKey = "liveSnapshot"
    static let commandKey = "liveCommand"

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func payload(for snapshot: LiveSessionSnapshot) -> [String: Any]? {
        guard let data = try? encoder.encode(snapshot) else { return nil }
        return [snapshotKey: data]
    }

    static func payload(for command: LiveSessionCommand) -> [String: Any]? {
        guard let data = try? encoder.encode(command) else { return nil }
        return [commandKey: data]
    }

    static func snapshot(from dict: [String: Any]) -> LiveSessionSnapshot? {
        guard let data = dict[snapshotKey] as? Data else { return nil }
        return try? decoder.decode(LiveSessionSnapshot.self, from: data)
    }

    static func command(from dict: [String: Any]) -> LiveSessionCommand? {
        guard let data = dict[commandKey] as? Data else { return nil }
        return try? decoder.decode(LiveSessionCommand.self, from: data)
    }
}
