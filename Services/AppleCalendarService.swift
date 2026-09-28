import EventKit
import Foundation

@MainActor
final class AppleCalendarService {
    static let shared = AppleCalendarService()
    private let store = EKEventStore()
    private let familyConnectTitle = "FamilyConnect"
    private let familyTitles = ["Family", "FamilyConnect"]

    func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .writeOnly:
            return true
        case .denied, .restricted:
            return false
        default:
            return (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        }
    }

    func addEvent(title: String, notes: String, start: Date, end: Date) async throws {
        guard await requestAccess() else {
            throw AppleCalendarError.noAccess
        }
        let calendar = try familyCalendar()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = notes
        event.startDate = start
        event.endDate = end > start ? end : start.addingTimeInterval(3600)
        event.calendar = calendar
        try store.save(event, span: .thisEvent)
    }

    private func familyCalendar() throws -> EKCalendar {
        let existing = store.calendars(for: .event).first { calendar in
            familyTitles.contains { calendar.title.caseInsensitiveCompare($0) == .orderedSame }
        }
        if let existing { return existing }

        let source = store.sources.first { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("iCloud") }
            ?? store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .local }

        guard let source else { throw AppleCalendarError.noCalendar }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = familyConnectTitle
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }
}

enum AppleCalendarError: LocalizedError {
    case noAccess
    case noCalendar
    var errorDescription: String? {
        switch self {
        case .noAccess:
            return "Calendar access is off. Enable it in Settings → FamilyConnect → Calendars."
        case .noCalendar:
            return "Could not create an iCloud calendar."
        }
    }
}
