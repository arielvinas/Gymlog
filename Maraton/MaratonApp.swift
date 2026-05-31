//
//  MaratonApp.swift
//  Maraton
//
//  Created by Ariel Viñas on 30/05/2026.
//

import SwiftUI
import SwiftData

@main
struct MaratonApp: App {
    let container: ModelContainer
    @State private var navigator = Navigator()

    init() {
        container = MaratonApp.makeContainer()

        // Pre-carga el plan en el primer arranque y aplica las novedades del
        // plan (una vez por versión), respetando los días editados o borrados.
        // El flag de sembrado vive en iCloud para no duplicar datos al
        // reinstalar o estrenar un dispositivo nuevo.
        WorkoutSeed.seedIfNeeded(context: container.mainContext)
        WorkoutSeed.applyPlanUpdates(context: container.mainContext)
    }

    /// Activar cuando haya Apple Developer Program (de pago) + las capabilities
    /// de iCloud/CloudKit/Push reactivadas. Los equipos personales (cuenta
    /// gratuita) no admiten CloudKit, así que por ahora el almacenamiento es local.
    static let iCloudSyncEnabled = false

    /// Crea el contenedor. Con `iCloudSyncEnabled` usa CloudKit (con respaldo
    /// local si no está disponible); si no, almacenamiento local — offline-first.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            WorkoutDay.self, Exercise.self, ExerciseSet.self,
            SupplementLog.self, SupplementReminder.self,
        ])

        if iCloudSyncEnabled {
            let cloudConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            if let container = try? ModelContainer(for: schema, configurations: cloudConfig) {
                return container
            }
        }

        // Almacenamiento local (la app funciona igual sin iCloud).
        let localConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: localConfig) {
            return container
        }

        fatalError("No se pudo crear el ModelContainer")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(navigator)
        }
        .modelContainer(container)
        .defaultSize(width: 1100, height: 760)
        .commands {
            SectionCommands(navigator: navigator)
        }
    }
}
