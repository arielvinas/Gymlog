//
//  LiveSessionIntents.swift
//  Maraton (compartido app iOS + Widget Extension)
//
//  Intents interactivos de los botones de la Live Activity (pantalla bloqueada
//  y Dynamic Island). Su `perform()` corre en el proceso de la app del iPhone
//  (por ser `LiveActivityIntent`), así que puede mandar el comando al reloj por
//  WatchConnectivity aunque el teléfono esté bloqueado. Solo se compila donde
//  existe ActivityKit.
//

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import AppIntents
import Foundation

/// Avanza a la próxima serie ("Hecho") desde la Live Activity.
struct AdvanceSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Hecho"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Sesión")
    var sessionID: String

    init() {}
    init(sessionID: UUID) { self.sessionID = sessionID.uuidString }

    func perform() async throws -> some IntentResult {
        await LiveSessionCommandDispatcher.send(.completeCurrent, sessionID: sessionID)
        return .result()
    }
}

/// Corta el descanso / empieza la próxima serie ("Saltear") desde la Live Activity.
struct SkipRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Saltear descanso"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Sesión")
    var sessionID: String

    init() {}
    init(sessionID: UUID) { self.sessionID = sessionID.uuidString }

    func perform() async throws -> some IntentResult {
        await LiveSessionCommandDispatcher.send(.skipRest, sessionID: sessionID)
        return .result()
    }
}

/// Centraliza el envío del comando al reloj desde un intent (en MainActor).
enum LiveSessionCommandDispatcher {
    static func send(_ action: LiveSessionAction, sessionID: String) async {
        await MainActor.run {
            guard let id = UUID(uuidString: sessionID) else { return }
            LiveSessionConnectivity.shared.send(command: LiveSessionCommand(sessionID: id, action: action))
        }
    }
}
#endif
