//
//  LiveSessionConnectivity.swift
//  Maraton (compartido iOS + watchOS)
//
//  Canal en vivo reloj ↔ iPhone vía WatchConnectivity. El reloj (autoridad)
//  difunde `LiveSessionSnapshot`; el iPhone (espejo) manda `LiveSessionCommand`.
//
//  Estrategia de entrega:
//  - `sendMessage` cuando el contraparte está reachable → baja latencia (en vivo).
//  - `transferUserInfo` cuando NO está reachable → entrega durable que DESPIERTA
//    a la app en background (clave para refrescar la Live Activity bloqueada).
//  - `updateApplicationContext` con cada snapshot → último estado, para cuando la
//    app reabre (reemplaza al anterior, no se encola).
//
//  Mac Catalyst no tiene WatchConnectivity: el tipo existe igual pero queda
//  como no-op para que la app de Mac compile.
//

import Foundation
import Observation
#if !targetEnvironment(macCatalyst)
import WatchConnectivity
#endif

@MainActor
@Observable
final class LiveSessionConnectivity: NSObject {
    static let shared = LiveSessionConnectivity()

    /// Último snapshot recibido (lo observa la UI del iPhone).
    private(set) var latestSnapshot: LiveSessionSnapshot?

    /// `true` si el último snapshot corresponde a una sesión todavía activa.
    var hasActiveSession: Bool { latestSnapshot?.isActive ?? false }

    /// Llamado al recibir un snapshot (lado iPhone: refresca app + Live Activity).
    var onSnapshot: ((LiveSessionSnapshot) -> Void)?
    /// Llamado al recibir un comando (lado reloj: lo aplica al engine).
    var onCommand: ((LiveSessionCommand) -> Void)?

    private override init() { super.init() }

    /// Activa la sesión de WatchConnectivity. Idempotente.
    func activate() {
        #if !targetEnvironment(macCatalyst)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
        #endif
    }

    /// `true` si el contraparte está accesible en este momento.
    var isReachable: Bool {
        #if !targetEnvironment(macCatalyst)
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated && session.isReachable
        #else
        return false
        #endif
    }

    // MARK: - Emitir

    /// Difunde un snapshot del estado de la sesión (reloj → iPhone).
    func send(snapshot: LiveSessionSnapshot) {
        #if !targetEnvironment(macCatalyst)
        guard WCSession.isSupported(),
              let payload = LiveSessionWire.payload(for: snapshot) else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        // Último estado durable, para cuando la app del iPhone reabra.
        try? session.updateApplicationContext(payload)

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            // Despierta la app del iPhone en background para refrescar la Live Activity.
            session.transferUserInfo(payload)
        }
        #endif
    }

    /// Manda un comando para controlar la sesión a distancia (iPhone → reloj).
    func send(command: LiveSessionCommand) {
        #if !targetEnvironment(macCatalyst)
        guard WCSession.isSupported(),
              let payload = LiveSessionWire.payload(for: command) else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(payload)
        }
        #endif
    }

    // MARK: - Recibir

    /// Procesa un diccionario recibido (venga por mensaje, userInfo o contexto).
    private func handle(_ dict: [String: Any]) {
        if let snapshot = LiveSessionWire.snapshot(from: dict) {
            // Descarta snapshots iguales o más viejos de la misma sesión.
            if let current = latestSnapshot,
               current.sessionID == snapshot.sessionID,
               snapshot.updatedAt <= current.updatedAt {
                return
            }
            latestSnapshot = snapshot
            onSnapshot?(snapshot)
        }
        if let command = LiveSessionWire.command(from: dict) {
            onCommand?(command)
        }
    }
}

// MARK: - WCSessionDelegate

#if !targetEnvironment(macCatalyst)
extension LiveSessionConnectivity: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.handle(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in self.handle(userInfo) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.handle(applicationContext) }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Reactivar para seguir disponible (p. ej. al cambiar de reloj emparejado).
        WCSession.default.activate()
    }
    #endif
}
#endif
