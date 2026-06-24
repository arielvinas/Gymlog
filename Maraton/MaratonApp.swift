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
        container = AppData.makeContainer()

        // Pre-carga el plan, aplica novedades por versión y siembra la rutina
        // de fuerza (lógica compartida con la app del reloj, en `AppData`).
        AppData.seed(context: container.mainContext)

        // Canal en vivo con el Apple Watch: recibe los snapshots de la sesión y
        // los refleja en la Live Activity (pantalla bloqueada / Dynamic Island).
        let link = LiveSessionConnectivity.shared
        link.onSnapshot = { LiveActivityController.handle($0) }
        link.activate()
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
