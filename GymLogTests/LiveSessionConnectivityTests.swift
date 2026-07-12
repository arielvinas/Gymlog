//
//  LiveSessionConnectivityTests.swift
//  GymLogTests
//
//  La regla de descarte del canal reloj↔iPhone (P0-7). El canal entrega **desordenado**: un
//  `sendMessage` de baja latencia puede llegar después de un `transferUserInfo` que salió antes, y
//  el `applicationContext` se reentrega entero cada vez que la app reabre. Sin esta regla, el
//  espejo del iPhone retrocedería a un estado viejo en medio de la sesión.
//
//  Backlog: TESTING.md · I-33, I-34
//

import Foundation
import Testing
@testable import Maraton

@Suite("Canal en vivo · descarte y despacho")
@MainActor
struct LiveSessionConnectivityTests {

    private let sesiónA = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
    private let sesiónB = UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000002")!

    /// Un snapshot mínimo, parametrizado por lo único que la regla mira: sesión y fecha.
    private func snap(_ id: UUID, _ updatedAt: Date, exerciseName: String = "Press banca")
        -> LiveSessionSnapshot
    {
        LiveSessionSnapshot(
            sessionID: id,
            dayDate: date(2026, 7, 1),
            phase: .logging,
            exerciseName: exerciseName,
            exerciseIndex: 0,
            exerciseCount: 5,
            setNumber: 1,
            setCount: 3,
            targetReps: "8",
            isBodyweight: false,
            isTimeBased: false,
            weight: nil,
            reps: nil,
            restEndDate: nil,
            restTotal: 90,
            isOvertime: false,
            heartRate: nil,
            progressFraction: 0,
            loggedSetsCount: 0,
            totalVolume: 0,
            updatedAt: updatedAt
        )
    }

    // MARK: - I-33 · La regla de descarte

    @Test("I-33 · El primer snapshot siempre se acepta")
    func theFirstSnapshotIsAlwaysAccepted() {
        #expect(
            LiveSessionConnectivity.shouldAccept(snap(sesiónA, date(2026, 7, 1)), over: nil)
        )
    }

    @Test("I-33 · Uno más nuevo de la misma sesión se acepta")
    func aNewerSnapshotOfTheSameSessionIsAccepted() {
        let actual = snap(sesiónA, date(2026, 7, 1))
        let nuevo = snap(sesiónA, date(2026, 7, 2))

        #expect(LiveSessionConnectivity.shouldAccept(nuevo, over: actual))
    }

    @Test("I-33 · Uno más viejo de la misma sesión se descarta")
    func anOlderSnapshotOfTheSameSessionIsRejected() {
        let actual = snap(sesiónA, date(2026, 7, 2))
        let viejo = snap(sesiónA, date(2026, 7, 1))

        // Es el caso real: el `transferUserInfo` que salió primero llega después del `sendMessage`.
        // Sin la regla, el espejo del iPhone volvería a la serie anterior.
        #expect(!LiveSessionConnectivity.shouldAccept(viejo, over: actual))
    }

    @Test("I-33 · Uno con la misma fecha se descarta: la comparación es estricta")
    func aSnapshotWithTheSameTimestampIsRejected() {
        let cuando = date(2026, 7, 2)
        let actual = snap(sesiónA, cuando)
        let repetido = snap(sesiónA, cuando, exerciseName: "Otro")

        // `>` estricto, no `>=`. Es lo que hace idempotente la reentrega del `applicationContext`:
        // al reabrir la app llega de nuevo el mismo snapshot y no dispara nada.
        #expect(!LiveSessionConnectivity.shouldAccept(repetido, over: actual))
    }

    @Test("I-33 · Un snapshot de OTRA sesión se acepta, aunque sea más viejo")
    func aSnapshotFromAnotherSessionIsAlwaysAccepted() {
        let actual = snap(sesiónA, date(2026, 7, 5))
        let otraSesión = snap(sesiónB, date(2026, 7, 1))   // más viejo en el reloj de pared

        // Deliberado: los tiempos de dos sesiones distintas **no son comparables**. Si el reloj se
        // reinicia y arranca una sesión nueva, el iPhone tiene que seguirla aunque su `updatedAt`
        // quede atrás del último de la sesión anterior.
        #expect(LiveSessionConnectivity.shouldAccept(otraSesión, over: actual))
    }

    // MARK: - I-34 · El despacho

    @Test("I-34 · Un snapshot aceptado actualiza el estado y avisa")
    func anAcceptedSnapshotUpdatesTheStateAndNotifies() throws {
        let canal = LiveSessionConnectivity()
        var recibidos: [LiveSessionSnapshot] = []
        canal.onSnapshot = { recibidos.append($0) }

        let payload = try #require(LiveSessionWire.payload(for: snap(sesiónA, date(2026, 7, 1))))
        canal.handle(payload)

        #expect(recibidos.count == 1)
        #expect(canal.latestSnapshot?.sessionID == sesiónA)
        #expect(canal.hasActiveSession, "La fase `.logging` es una sesión viva")
    }

    @Test("I-34 · Un snapshot descartado no avisa ni pisa el estado")
    func aRejectedSnapshotDoesNotNotify() throws {
        let canal = LiveSessionConnectivity()
        var avisos = 0
        canal.onSnapshot = { _ in avisos += 1 }

        let nuevo = try #require(LiveSessionWire.payload(for: snap(sesiónA, date(2026, 7, 2))))
        let viejo = try #require(
            LiveSessionWire.payload(for: snap(sesiónA, date(2026, 7, 1), exerciseName: "Viejo"))
        )

        canal.handle(nuevo)
        canal.handle(viejo)

        #expect(avisos == 1, "El viejo no disparó el callback")
        #expect(canal.latestSnapshot?.exerciseName == "Press banca", "Ni pisó el estado")
    }

    @Test("I-34 · Un comando dispara onCommand y no toca el snapshot")
    func aCommandFiresOnCommandOnly() throws {
        let canal = LiveSessionConnectivity()
        var comandos: [LiveSessionCommand] = []
        var snapshots = 0
        canal.onCommand = { comandos.append($0) }
        canal.onSnapshot = { _ in snapshots += 1 }

        let comando = LiveSessionCommand(
            sessionID: sesiónA, action: .completeCurrent, sentAt: date(2026, 7, 1)
        )
        let payload = try #require(LiveSessionWire.payload(for: comando))
        canal.handle(payload)

        #expect(comandos == [comando])
        #expect(snapshots == 0)
        #expect(canal.latestSnapshot == nil)
    }

    @Test("I-34 · Un diccionario que no es ninguna de las dos cosas no hace nada")
    func anUnknownPayloadIsIgnored() {
        let canal = LiveSessionConnectivity()
        var algo = false
        canal.onSnapshot = { _ in algo = true }
        canal.onCommand = { _ in algo = true }

        canal.handle(["cualquier": "cosa"])

        #expect(!algo)
        #expect(canal.latestSnapshot == nil)
    }

    // MARK: - I-35 · La política de entrega

    /// Un `WCSession` de mentira: anota por dónde salió cada cosa.
    @MainActor
    private final class TransporteEspía: LiveSessionTransport {
        var isActivated = true
        var isReachable = false

        private(set) var contextos: [[String: Any]] = []
        private(set) var mensajes: [[String: Any]] = []
        private(set) var userInfos: [[String: Any]] = []

        func updateApplicationContext(_ payload: [String: Any]) { contextos.append(payload) }
        func sendMessage(_ payload: [String: Any]) { mensajes.append(payload) }
        func transferUserInfo(_ payload: [String: Any]) { userInfos.append(payload) }
    }

    @Test("I-35 · Con el contraparte accesible, el snapshot va por mensaje (baja latencia)")
    func aReachableSnapshotGoesByMessage() {
        let canal = LiveSessionConnectivity()
        let espía = TransporteEspía()
        espía.isReachable = true
        canal.transport = espía

        canal.send(snapshot: snap(sesiónA, date(2026, 7, 1)))

        #expect(espía.mensajes.count == 1)
        #expect(espía.userInfos.isEmpty)
        // Y **además** por contexto: es el último estado, para cuando el iPhone reabra.
        #expect(espía.contextos.count == 1)
    }

    @Test("I-35 · Sin el contraparte accesible, el snapshot va por userInfo (despierta la app)")
    func anUnreachableSnapshotGoesByUserInfo() {
        let canal = LiveSessionConnectivity()
        let espía = TransporteEspía()
        espía.isReachable = false
        canal.transport = espía

        canal.send(snapshot: snap(sesiónA, date(2026, 7, 1)))

        // `transferUserInfo` es durable y **despierta la app en background**: es lo único que
        // mantiene viva la Live Activity con la pantalla bloqueada. Si esto se rompiera, el
        // cronómetro de la pantalla de bloqueo se congelaría y nadie se daría cuenta en un test
        // de UI.
        #expect(espía.userInfos.count == 1)
        #expect(espía.mensajes.isEmpty)
        #expect(espía.contextos.count == 1, "El contexto sale igual, accesible o no")
    }

    @Test("I-35 · El comando NO va por contexto: sería una orden fantasma al reabrir")
    func aCommandNeverGoesByApplicationContext() {
        let canal = LiveSessionConnectivity()
        let espía = TransporteEspía()
        espía.isReachable = true
        canal.transport = espía

        canal.send(
            command: LiveSessionCommand(
                sessionID: sesiónA, action: .completeCurrent, sentAt: date(2026, 7, 1)
            )
        )

        #expect(espía.mensajes.count == 1)
        // El `applicationContext` se **reentrega** cada vez que la app reabre. Un snapshot
        // reentregado es inofensivo (la regla de I-33 lo descarta); un comando reentregado sería
        // un "Hecho" fantasma que marca una serie que nadie hizo.
        #expect(espía.contextos.isEmpty)
    }

    @Test("I-35 · El comando también cae a userInfo si el contraparte no está accesible")
    func anUnreachableCommandFallsBackToUserInfo() {
        let canal = LiveSessionConnectivity()
        let espía = TransporteEspía()
        espía.isReachable = false
        canal.transport = espía

        canal.send(
            command: LiveSessionCommand(
                sessionID: sesiónA, action: .end, sentAt: date(2026, 7, 1)
            )
        )

        #expect(espía.userInfos.count == 1)
        #expect(espía.mensajes.isEmpty)
        #expect(espía.contextos.isEmpty)
    }

    @Test("I-35 · Sin la sesión activada no sale nada")
    func nothingIsSentBeforeActivation() {
        let canal = LiveSessionConnectivity()
        let espía = TransporteEspía()
        espía.isActivated = false
        espía.isReachable = true
        canal.transport = espía

        canal.send(snapshot: snap(sesiónA, date(2026, 7, 1)))
        canal.send(
            command: LiveSessionCommand(
                sessionID: sesiónA, action: .end, sentAt: date(2026, 7, 1)
            )
        )

        #expect(espía.mensajes.isEmpty)
        #expect(espía.userInfos.isEmpty)
        #expect(espía.contextos.isEmpty)
        #expect(!canal.isReachable, "Activada manda sobre accesible")
    }

    @Test("I-35 · Sin transporte (Mac Catalyst) los envíos son no-op, no un crash")
    func withoutATransportSendingIsANoOp() {
        let canal = LiveSessionConnectivity()   // `transport` en nil: es el caso de Mac Catalyst

        canal.send(snapshot: snap(sesiónA, date(2026, 7, 1)))
        canal.send(
            command: LiveSessionCommand(
                sessionID: sesiónA, action: .end, sentAt: date(2026, 7, 1)
            )
        )

        #expect(!canal.isReachable)
    }
}
