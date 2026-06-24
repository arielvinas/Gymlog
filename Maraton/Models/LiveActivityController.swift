//
//  LiveActivityController.swift
//  Maraton (solo iOS; no-op en Mac Catalyst)
//
//  Arranca / actualiza / termina la Live Activity de la sesión de gimnasio a
//  partir de los snapshots que llegan del reloj. Vive en la app del iPhone (no en
//  la extensión): la extensión solo dibuja. ActivityKit no existe en Catalyst, así
//  que ahí queda como no-op para no romper la versión Mac.
//

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
import Foundation
import OSLog

@MainActor
enum LiveActivityController {
    private static var activity: Activity<GuidedSessionActivityAttributes>?
    private static let log = Logger(subsystem: "ariel.Maraton", category: "LiveActivity")

    /// Reacciona a un snapshot: arranca la Live Activity si empieza una sesión,
    /// la actualiza mientras corre, y la cierra cuando termina.
    static func handle(_ snapshot: LiveSessionSnapshot) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(
            state: GuidedSessionActivityAttributes.ContentState(snapshot: snapshot),
            staleDate: nil
        )

        if snapshot.isActive {
            if let current = activity {
                Task { await current.update(content) }
            } else {
                do {
                    activity = try Activity.request(
                        attributes: GuidedSessionActivityAttributes(),
                        content: content,
                        pushType: nil
                    )
                    log.notice("Live Activity iniciada")
                } catch {
                    log.error("No se pudo iniciar la Live Activity: \(error, privacy: .public)")
                }
            }
        } else {
            let finished = activity
            activity = nil
            Task { await finished?.end(content, dismissalPolicy: .immediate) }
        }
    }

    /// Cierra cualquier Live Activity en curso (al cerrar la app, por seguridad).
    static func endAll() {
        let finished = activity
        activity = nil
        Task {
            await finished?.end(nil, dismissalPolicy: .immediate)
            for activity in Activity<GuidedSessionActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}

#else
import Foundation

/// Stub no-op para Mac Catalyst (sin ActivityKit).
enum LiveActivityController {
    @MainActor static func handle(_ snapshot: LiveSessionSnapshot) {}
    @MainActor static func endAll() {}
}
#endif
