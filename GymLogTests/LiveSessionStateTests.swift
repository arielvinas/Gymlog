//
//  LiveSessionStateTests.swift
//  GymLogTests
//
//  El contrato de serialización entre el reloj (autoridad) y el iPhone (espejo).
//  Es lo único que sostiene la sesión en vivo: si un rename rompe el Codable, la
//  sesión deja de reflejarse y nadie se entera hasta usarlo en el gimnasio.
//
//  Backlog: TESTING.md · U-12..U-17
//

import Foundation
import Testing
@testable import Maraton

@Suite("Sesión en vivo · serialización")
struct LiveSessionStateTests {

    /// Snapshot con **todos** los campos poblados, incluidos los opcionales.
    /// Las fechas salen de `date(...)` (mediodía, segundos enteros) para que el
    /// round-trip por JSON sea exacto y el test no dependa de la precisión de
    /// `Date()`.
    private func fullSnapshot() -> LiveSessionSnapshot {
        LiveSessionSnapshot(
            sessionID: UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!,
            dayDate: date(2026, 7, 1),
            phase: .resting,
            exerciseName: "Press banca",
            exerciseIndex: 2,
            exerciseCount: 8,
            setNumber: 3,
            setCount: 4,
            targetReps: "6-8",
            isBodyweight: false,
            isTimeBased: false,
            weight: 42.5,
            reps: 8,
            restEndDate: date(2026, 7, 2),
            restTotal: 90,
            isOvertime: true,
            heartRate: 131,
            progressFraction: 0.375,
            loggedSetsCount: 11,
            totalVolume: 1234.5,
            updatedAt: date(2026, 7, 3)
        )
    }

    /// Snapshot con **todos los opcionales en `nil`**: el estado real de una serie
    /// de peso corporal recién empezada, sin nada cargado y sin reloj puesto.
    private func snapshotWithNoOptionals() -> LiveSessionSnapshot {
        LiveSessionSnapshot(
            sessionID: UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!,
            dayDate: date(2026, 7, 1),
            phase: .logging,
            exerciseName: "Plancha",
            exerciseIndex: 0,
            exerciseCount: 5,
            setNumber: 0,
            setCount: 0,
            targetReps: nil,
            isBodyweight: true,
            isTimeBased: true,
            weight: nil,
            reps: nil,
            restEndDate: nil,
            restTotal: 0,
            isOvertime: false,
            heartRate: nil,
            progressFraction: 0,
            loggedSetsCount: 0,
            totalVolume: 0,
            updatedAt: date(2026, 7, 3)
        )
    }

    // MARK: - U-12

    @Test("U-12 · Round-trip de un snapshot completo")
    func snapshotRoundTripsWithAllFieldsSet() throws {
        let original = fullSnapshot()

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LiveSessionSnapshot.self, from: data)

        #expect(decoded == original)
    }

    // MARK: - U-13

    @Test("U-13 · Round-trip con todos los opcionales en nil")
    func snapshotRoundTripsWithAllOptionalsNil() throws {
        let original = snapshotWithNoOptionals()

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LiveSessionSnapshot.self, from: data)

        #expect(decoded == original)

        // Los opcionales tienen que volver como `nil`, no como valores por defecto:
        // un `weight` que vuelva en 0 haría que el iPhone dibuje "0 kg" donde el
        // reloj no mostraba nada.
        #expect(decoded.targetReps == nil)
        #expect(decoded.weight == nil)
        #expect(decoded.reps == nil)
        #expect(decoded.restEndDate == nil)
        #expect(decoded.heartRate == nil)
    }

    // MARK: - U-14

    /// Cada acción que el iPhone puede mandarle al reloj. `adjustRest` es el único
    /// `case` con valor asociado, así que su `Codable` sintetizado usa un contenedor
    /// anidado: es lo primero que se rompe ante un rename, y lo que menos se nota
    /// (los botones ±15 de la Live Activity dejarían de hacer efecto, en silencio).
    @Test(
        "U-14 · Round-trip de cada acción",
        arguments: [
            LiveSessionAction.completeCurrent,
            .skipRest,
            .goBack,
            .adjustRest(15),
            .adjustRest(-15),
            .end,
        ]
    )
    func actionRoundTrips(action: LiveSessionAction) throws {
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(LiveSessionAction.self, from: data)

        #expect(decoded == action)
    }

    @Test("U-14 · El delta de adjustRest sobrevive con su signo")
    func adjustRestPreservesDelta() throws {
        // No alcanza con que el `case` sea el correcto: si el valor asociado se
        // perdiera o cambiara de signo, "±15" ajustaría para el lado equivocado.
        for delta in [-30, -15, 0, 15, 30] {
            let data = try JSONEncoder().encode(LiveSessionAction.adjustRest(delta))
            let decoded = try JSONDecoder().decode(LiveSessionAction.self, from: data)

            guard case .adjustRest(let recovered) = decoded else {
                Issue.record("adjustRest(\(delta)) volvió como otro case: \(decoded)")
                return
            }
            #expect(recovered == delta)
        }
    }
}
