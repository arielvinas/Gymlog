//
//  AppData.swift
//  Maraton (compartido iOS + watchOS)
//
//  Fuente única del schema SwiftData, la creación del contenedor y el sembrado
//  del plan. Lo usan tanto la app del iPhone (MaratonApp) como la del reloj
//  (MaratonWatchApp), para no duplicar la lógica ni que se desincronicen.
//

import Foundation
import SwiftData
import OSLog

enum AppData {

    /// Activar cuando haya Apple Developer Program (de pago) + las capabilities
    /// de iCloud/CloudKit/Push reactivadas. Los equipos personales (cuenta
    /// gratuita) no admiten CloudKit, así que por ahora el almacenamiento es
    /// local en cada dispositivo (iPhone y reloj siembran el mismo plan).
    static let iCloudSyncEnabled = true

    /// Entidades del modelo. Debe ser idéntico en todos los targets para que
    /// CloudKit no encuentre discrepancias el día que se active la sync.
    static var schema: Schema {
        Schema([
            WorkoutDay.self, Exercise.self, ExerciseSet.self,
            SupplementLog.self, SupplementReminder.self,
        ])
    }

    static let log = Logger(subsystem: "ariel.Maraton", category: "AppData")

    /// Crea el contenedor. Con `iCloudSyncEnabled` usa CloudKit (con respaldo
    /// local si no está disponible); si no, almacenamiento local — offline-first.
    static func makeContainer() -> ModelContainer {
        let schema = self.schema

        if iCloudSyncEnabled {
            let cloudConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            do {
                let container = try ModelContainer(for: schema, configurations: cloudConfig)
                log.notice("ModelContainer creado con CloudKit (sync activa)")
                return container
            } catch {
                // Si CloudKit falla NO lo silenciamos: el motivo (modelo
                // incompatible, cuenta, entitlement…) queda en el log del sistema
                // bajo el subsistema "ariel.Maraton". Caemos a local para no
                // dejar la app inutilizable.
                log.error("CloudKit NO disponible, se usa store local. Error: \(error, privacy: .public)")
            }
        }

        // Almacenamiento local (la app funciona igual sin iCloud).
        let localConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: localConfig) {
            log.notice("ModelContainer creado con store local")
            return container
        }

        fatalError("No se pudo crear el ModelContainer")
    }

    /// Pre-carga el plan en el primer arranque y aplica las novedades del plan
    /// (una vez por versión), respetando los días editados o borrados, y carga
    /// la rutina de fuerza (DÍA A / DÍA B) en los días de fuerza sin ejercicios.
    @MainActor
    static func seed(context: ModelContext) {
        WorkoutSeed.seedIfNeeded(context: context)
        WorkoutSeed.applyPlanUpdates(context: context)
        StrengthSeed.populateIfNeeded(context: context)

        // Limpia días duplicados (doble sembrado iPhone/reloj antes de sincronizar)
        // y los días vacíos que dejó la etapa de recuperación de rodilla. Solo el
        // iPhone: un único ejecutor evita altas/bajas de registros en paralelo; los
        // cambios se propagan por CloudKit al reloj y la Mac.
        #if os(iOS) && !targetEnvironment(macCatalyst)
        WorkoutSeed.deduplicateDays(context: context)
        WorkoutSeed.cleanupKneeRecoveryIfNeeded(context: context)
        #endif
    }
}
