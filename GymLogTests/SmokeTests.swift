//
//  SmokeTests.swift
//  GymLogTests
//
//  Prueba de humo: confirma que el target de tests está bien cableado
//  (`@testable import` alcanza el módulo de la app, Swift Testing corre).
//  Los tests de verdad están enumerados en TESTING.md.
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Humo")
struct SmokeTests {
    @Test("El módulo de la app es alcanzable desde los tests")
    func appModuleIsReachable() {
        #expect(WorkoutType.allCases.count == 6)
        #expect(SupplementKind.allCases.count == 2)
    }

    @Test("El código de Shared/ también entra por el módulo de la app")
    func sharedCodeIsReachable() {
        #expect(90.restLabel == "1:30 min")
    }

    @Test("Hostear los tests no arranca la app de verdad")
    func hostAppIsInert() {
        // De esto dependen todos los tests de seed: si la app hosteadora sembrara,
        // escribiría los flags (UserDefaults + KVS) que esos tests controlan.
        #expect(AppData.isHostingUnitTests)
    }

    @Test("La base de test arranca vacía")
    func testDatabaseStartsEmpty() throws {
        let db = TestDB()
        let days = try db.context.fetch(FetchDescriptor<WorkoutDay>())
        #expect(days.isEmpty, "El plan no debería estar sembrado en una base de test")
    }

    @Test("Dos bases de test no comparten estado")
    func testDatabasesAreIsolated() throws {
        let a = TestDB()
        makeDay(date(2026, 7, 1), in: a.context)
        try a.context.save()

        let b = TestDB()
        let daysInB = try b.context.fetch(FetchDescriptor<WorkoutDay>())
        #expect(daysInB.isEmpty, "La base B vio datos de la base A")
    }
}
