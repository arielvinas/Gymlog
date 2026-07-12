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

/// Lo que `LiveSessionConnectivity` necesita del canal, y nada más.
///
/// Existe para poder testear la **política de entrega** —qué sale por dónde según si el
/// contraparte está accesible— sin un `WCSession` real, que no se puede instanciar ni simular:
/// es un singleton del sistema que necesita dos dispositivos emparejados.
@MainActor
protocol LiveSessionTransport: AnyObject {
    var isActivated: Bool { get }
    var isReachable: Bool { get }
    /// Último estado durable: reemplaza al anterior en vez de encolarse.
    func updateApplicationContext(_ payload: [String: Any])
    /// Baja latencia; requiere que el contraparte esté accesible.
    func sendMessage(_ payload: [String: Any])
    /// Entrega durable que **despierta la app en background**.
    func transferUserInfo(_ payload: [String: Any])
}

@MainActor
@Observable
final class LiveSessionConnectivity: NSObject {
    static let shared = LiveSessionConnectivity()

    /// El canal por donde sale todo. Lo pone `activate()`; en Mac Catalyst queda `nil` (no hay
    /// WatchConnectivity) y todos los envíos se vuelven no-op. Los tests le enchufan un doble.
    var transport: LiveSessionTransport?

    /// Último snapshot recibido (lo observa la UI del iPhone).
    private(set) var latestSnapshot: LiveSessionSnapshot?

    /// `true` si el último snapshot corresponde a una sesión todavía activa.
    var hasActiveSession: Bool { latestSnapshot?.isActive ?? false }

    /// Llamado al recibir un snapshot (lado iPhone: refresca app + Live Activity).
    var onSnapshot: ((LiveSessionSnapshot) -> Void)?
    /// Llamado al recibir un comando (lado reloj: lo aplica al engine).
    var onCommand: ((LiveSessionCommand) -> Void)?

    /// La app usa siempre `shared`. El `init` no es privado para que los tests puedan crear
    /// instancias **aisladas** en vez de mutar el singleton (que corren en paralelo y se pisarían).
    override init() { super.init() }

    /// Activa la sesión de WatchConnectivity. Idempotente.
    func activate() {
        #if !targetEnvironment(macCatalyst)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
        transport = WCSessionTransport(session: session)
        #endif
    }

    /// `true` si el contraparte está accesible en este momento.
    var isReachable: Bool {
        guard let transport else { return false }
        return transport.isActivated && transport.isReachable
    }

    // MARK: - Emitir

    /// Difunde un snapshot del estado de la sesión (reloj → iPhone).
    ///
    /// El snapshot va **siempre** por `updateApplicationContext` —el último estado, para cuando la
    /// app del iPhone reabra— *además* del envío en vivo. El comando no: un comando viejo reentregado
    /// al reabrir la app sería una orden fantasma.
    func send(snapshot: LiveSessionSnapshot) {
        guard let transport, transport.isActivated,
              let payload = LiveSessionWire.payload(for: snapshot) else { return }

        transport.updateApplicationContext(payload)
        deliver(payload, over: transport)
    }

    /// Manda un comando para controlar la sesión a distancia (iPhone → reloj).
    func send(command: LiveSessionCommand) {
        guard let transport, transport.isActivated,
              let payload = LiveSessionWire.payload(for: command) else { return }

        deliver(payload, over: transport)
    }

    /// Accesible → `sendMessage` (baja latencia, en vivo). No accesible → `transferUserInfo`, que
    /// es durable y **despierta la app en background**: es lo que mantiene viva la Live Activity
    /// con la pantalla bloqueada.
    private func deliver(_ payload: [String: Any], over transport: LiveSessionTransport) {
        if transport.isReachable {
            transport.sendMessage(payload)
        } else {
            transport.transferUserInfo(payload)
        }
    }

    // MARK: - Recibir

    /// ¿Vale la pena quedarse con `nuevo`, teniendo `actual`?
    ///
    /// El canal entrega **desordenado**: un `sendMessage` de baja latencia puede llegar después de
    /// un `transferUserInfo` que salió antes, y el `applicationContext` se reentrega al reabrir la
    /// app. Sin esta regla, el espejo del iPhone retrocedería a un estado viejo.
    ///
    /// Solo se descarta lo viejo **de la misma sesión**: un `sessionID` distinto es una sesión
    /// nueva, y sus tiempos no son comparables con los de la anterior.
    ///
    /// Es lógica pura, separada del transporte, para poder testearla sin `WCSession`.
    static func shouldAccept(
        _ nuevo: LiveSessionSnapshot,
        over actual: LiveSessionSnapshot?
    ) -> Bool {
        guard let actual, actual.sessionID == nuevo.sessionID else { return true }
        return nuevo.updatedAt > actual.updatedAt
    }

    /// Procesa un diccionario recibido (venga por mensaje, userInfo o contexto).
    func handle(_ dict: [String: Any]) {
        if let snapshot = LiveSessionWire.snapshot(from: dict),
           Self.shouldAccept(snapshot, over: latestSnapshot) {
            latestSnapshot = snapshot
            onSnapshot?(snapshot)
        }
        if let command = LiveSessionWire.command(from: dict) {
            onCommand?(command)
        }
    }
}

// MARK: - El transporte real

#if !targetEnvironment(macCatalyst)
/// El `WCSession` de verdad, detrás del protocolo. No tiene lógica: solo traduce.
@MainActor
final class WCSessionTransport: LiveSessionTransport {
    private let session: WCSession

    init(session: WCSession) { self.session = session }

    var isActivated: Bool { session.activationState == .activated }
    var isReachable: Bool { session.isReachable }

    func updateApplicationContext(_ payload: [String: Any]) {
        try? session.updateApplicationContext(payload)
    }

    func sendMessage(_ payload: [String: Any]) {
        session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }

    func transferUserInfo(_ payload: [String: Any]) {
        session.transferUserInfo(payload)
    }
}
#endif

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
