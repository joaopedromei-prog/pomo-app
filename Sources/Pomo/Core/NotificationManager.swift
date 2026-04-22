import Foundation
import UserNotifications
import AppKit

final class NotificationManager: @unchecked Sendable {
    static let shared = NotificationManager()
    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func playSound() {
        NSSound(named: "Glass")?.play()
    }

    private var alarmSound: NSSound?

    func startAlarm() {
        alarmSound?.stop()
        let sound = NSSound(named: "Submarine") ?? NSSound(named: "Funk") ?? NSSound(named: "Glass")
        sound?.loops = true
        sound?.play()
        alarmSound = sound
    }

    func stopAlarm() {
        alarmSound?.stop()
        alarmSound = nil
    }
}
