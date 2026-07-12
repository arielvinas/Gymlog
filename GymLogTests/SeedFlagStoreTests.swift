//
//  SeedFlagStoreTests.swift
//  GymLogTests
//
//  El store de flags de sembrado (P0-4 / P0-5): la costura que hace testeables a los seeds.
//  Vive acá, y no en Shared/, para no dejar código muerto en la app.
//
//  Backlog: TESTING.md · P0-4, P0-5
//

import Foundation
import Testing
@testable import Maraton

@Suite("Flags de sembrado")
struct SeedFlagStoreTests {

    /// Un `UserDefaults` descartable, para no ensuciar el del simulador.
    private func defaultsLimpios(_ nombre: String) throws -> UserDefaults {
        let suite = try #require(UserDefaults(suiteName: "test.seedflags.\(nombre)"))
        suite.removePersistentDomain(forName: "test.seedflags.\(nombre)")
        return suite
    }

    // MARK: - El store en memoria

    @Test("P0-4 · El store en memoria arranca en cero y recuerda lo que se le escribe")
    func theInMemoryStoreRoundTrips() {
        let store = InMemorySeedFlagStore()

        // Sin sembrar: 0 y false. Es el estado de una instalación nueva.
        #expect(store.integer(forKey: "seededPlanVersion") == 0)
        #expect(store.bool(forKey: "cleanedKneeRecoveryV1") == false)

        store.setInteger(7, forKey: "seededPlanVersion")
        store.setBool(true, forKey: "cleanedKneeRecoveryV1")

        #expect(store.integer(forKey: "seededPlanVersion") == 7)
        #expect(store.bool(forKey: "cleanedKneeRecoveryV1"))
    }

    @Test("P0-4 · Se puede arrancar con un estado previo, como una instalación ya sembrada")
    func theInMemoryStoreCanBePreloaded() {
        let store = InMemorySeedFlagStore(["seededPlanVersion": 2, "seededStrengthVersion": 7])

        #expect(store.integer(forKey: "seededPlanVersion") == 2)
        #expect(store.integer(forKey: "seededStrengthVersion") == 7)
        #expect(store.integer(forKey: "otraClave") == 0)
    }

    // MARK: - P0-5 · La rama "sin iCloud", ahora alcanzable

    @Test("P0-5 · Sin iCloud, el store solo usa UserDefaults")
    func withoutICloudItOnlyUsesUserDefaults() throws {
        let defaults = try defaultsLimpios("sin-icloud")

        // `cloud: nil` **es** la rama "sin iCloud". Antes colgaba de `AppData.iCloudSyncEnabled`,
        // que es un `static let`: no había forma de recorrerla desde un test.
        let store = DefaultSeedFlagStore(defaults: defaults, cloud: nil)

        #expect(store.integer(forKey: "seededPlanVersion") == 0)

        store.setInteger(2, forKey: "seededPlanVersion")
        store.setBool(true, forKey: "cleanedKneeRecoveryV1")

        #expect(store.integer(forKey: "seededPlanVersion") == 2)
        #expect(store.bool(forKey: "cleanedKneeRecoveryV1"))

        // Y quedó donde tenía que quedar, no en la nube.
        #expect(defaults.integer(forKey: "seededPlanVersion") == 2)
    }

    /// ⚠️ La rama **con** iCloud no se testea contra el KVS real a propósito: sin entitlement, el
    /// `NSUbiquitousKeyValueStore` devuelve 0/false y **descarta las escrituras en silencio**, así
    /// que un test que lo usara pasaría por la razón equivocada (leyendo el local que acaba de
    /// escribir) y se rompería el día que el bundle sí tenga entitlement. Es exactamente la
    /// fábrica de flakes que este refactor vino a desarmar.
    ///
    /// Lo que sí se puede fijar acá es la mitad verificable de la regla (`max(nube, local)`): la
    /// capa de iCloud, esté disponible o no, **nunca pierde el valor local**. Es justo la
    /// propiedad que hace que la app siga funcionando sin entitlement — que es como corre hoy.
    @Test("P0-5 · Con iCloud activo, la capa de la nube nunca se come el valor local")
    func theCloudLayerNeverLosesTheLocalValue() throws {
        let defaults = try defaultsLimpios("con-icloud")
        let store = DefaultSeedFlagStore(defaults: defaults, cloud: .default)
        let clave = "test.seedflags.planVersion"

        store.setInteger(3, forKey: clave)

        // Con o sin entitlement: si la nube tiene menos (o nada), gana el 3 local; si tuviera más,
        // ganaría ese. Nunca menos que lo local.
        #expect(store.integer(forKey: clave) >= 3)
        #expect(defaults.integer(forKey: clave) == 3, "Lo local se escribió igual")

        defaults.removePersistentDomain(forName: "test.seedflags.con-icloud")
    }

    // MARK: - La inyección en AppData

    @Test("P0-4 · AppData.seedFlags es el punto de inyección, y por defecto es el store real")
    func appDataExposesTheInjectionPoint() {
        // El default de producción sigue siendo el store real: el refactor no cambia lo que hace
        // la app, solo dónde se puede cortar.
        #expect(AppData.seedFlags is DefaultSeedFlagStore)
    }
}
