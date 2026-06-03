//
//  NotificationManager.swift
//  Maraton
//
//  Notificaciones locales para los recordatorios de suplementos.
//

import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    /// Pide permiso para enviar notificaciones. Devuelve si fue concedido.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Reprograma el recordatorio: lo cancela y lo vuelve a crear si está activo.
    func reschedule(_ reminder: SupplementReminder) {
        cancel(reminder.kind)
        guard reminder.enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = reminder.kind.notificationTitle
        content.body = reminder.kind.notificationBody
        content.sound = .default

        var components = DateComponents()
        components.hour = reminder.hour
        components.minute = reminder.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(
            identifier: identifier(for: reminder.kind),
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    /// Reprograma todos los recordatorios (p. ej. al iniciar la app).
    func rescheduleAll(_ reminders: [SupplementReminder]) {
        for reminder in reminders {
            reschedule(reminder)
        }
    }

    /// Cancela el recordatorio de un suplemento.
    func cancel(_ kind: SupplementKind) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: kind)])
    }

    private func identifier(for kind: SupplementKind) -> String {
        "supplement-reminder-\(kind.rawValue)"
    }

    // MARK: - Cronómetro de descanso (sesión guiada de gimnasio)

    /// Identificador de la notificación de fin de descanso. Es única: cada
    /// descanso reemplaza a la anterior.
    nonisolated private static let restTimerIdentifier = "gym-rest-timer-end"

    /// Agenda una notificación local para avisar el fin del descanso, de modo
    /// que el aviso (sonido + vibración del sistema) llegue aunque la pantalla
    /// esté bloqueada o la app en segundo plano. En primer plano el aviso lo da
    /// la propia vista, así que acá se suprime el sonido (ver `willPresent`).
    func scheduleRestEnd(after seconds: Int) {
        cancelRestEnd()
        guard seconds > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Descanso terminado"
        content.body = "Dale con la próxima serie."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(seconds),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: Self.restTimerIdentifier,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    /// Cancela la notificación de fin de descanso pendiente (al saltear el
    /// descanso, volver atrás o cerrar la sesión).
    func cancelRestEnd() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.restTimerIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.restTimerIdentifier])
    }

    // Muestra la notificación aunque la app esté en primer plano.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // El fin de descanso, en primer plano, ya lo anuncia la vista con sonido
        // y vibración: mostramos solo el banner para no duplicar el sonido.
        if notification.request.identifier == Self.restTimerIdentifier {
            completionHandler([.banner])
        } else {
            completionHandler([.banner, .sound])
        }
    }
}
