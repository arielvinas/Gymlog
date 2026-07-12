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

    /// Dónde guardan los seeds sus flags ("¿qué versión ya sembré?"). Es el **único** punto de
    /// inyección: los tests lo reemplazan por un store en memoria para no depender de
    /// `UserDefaults` ni del Key-Value Store de iCloud (que sin entitlement descarta las
    /// escrituras en silencio). Ver `SeedFlagStore`.
    static var seedFlags: SeedFlagStore = DefaultSeedFlagStore()

    /// `true` cuando el proceso es la app hosteando el bundle de tests unitarios.
    /// XCTest sólo define esta variable en el proceso que hostea los unitarios: en
    /// los tests de UI la app corre como proceso aparte y arranca normal.
    ///
    /// Sirve para que hostear los tests no tenga efectos: sin esto, el `init()` de
    /// la app siembra el plan en cada corrida y escribe los flags de sembrado
    /// (`UserDefaults` + KVS) que los tests de seed necesitan controlar.
    static var isHostingUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// `true` cuando la app fue lanzada por un test de UI (con el argumento `-uitesting`).
    ///
    /// A diferencia de los unitarios, acá la app corre como **proceso aparte** y arranca de
    /// verdad: hay que hacerla determinística. Con este flag, el contenedor es **en memoria** y los
    /// flags de sembrado también, así que **cada test arranca con el plan recién sembrado**, sin
    /// arrastrar lo que dejó la corrida anterior en el simulador. Sin esto, el primer test siembra
    /// y el segundo encuentra el flag ya puesto: dos estados distintos, y los E2E salen flaky.
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitesting")
    }

    /// Crea el contenedor. Con `iCloudSyncEnabled` usa CloudKit (con respaldo
    /// local si no está disponible); si no, almacenamiento local — offline-first.
    ///
    /// - Parameter inMemory: contenedor efímero, sin tocar el disco ni CloudKit.
    ///   Para tests y para hostear el bundle de tests.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = self.schema

        if inMemory {
            // `cloudKitDatabase` es `.automatic` por defecto: sin el `.none`
            // explícito, SwiftData intenta montar CloudKit hasta sobre un store
            // en memoria.
            let memoryConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            // Sin respaldo: si esto falla, el test tiene que fallar ruidosamente.
            return try! ModelContainer(for: schema, configurations: memoryConfig)
        }

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
