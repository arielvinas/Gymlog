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

    // Muestra la notificación aunque la app esté en primer plano.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
