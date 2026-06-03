//
//  MaratonWatchApp.swift
//  MaratonWatch Watch App
//
//  App companion de Apple Watch para hacer las sesiones de gimnasio desde la
//  muñeca. Comparte el schema, el contenedor y el sembrado del plan con la app
//  del iPhone vía `AppData` (en el código compartido). Hoy cada dispositivo
//  tiene su store local sembrado con el mismo plan; la sync real reloj↔iPhone
//  se enciende al activar iCloud (mismo interruptor que la app del teléfono).
//

import SwiftUI
import SwiftData

@main
struct MaratonWatchApp: App {
    let container: ModelContainer

    init() {
        container = AppData.makeContainer()
        AppData.seed(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
        .modelContainer(container)
    }
}
