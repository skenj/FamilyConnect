import SwiftUI
import EventKit

struct CalendarView: View {
    @EnvironmentObject var cloudKitService: CloudKitService
    @State private var showingAddEvent = false
    @State private var selectedDate = Date()

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()

                List {
                    ForEach(cloudKitService.calendarEvents.filter { Calendar.current.isDate($0.startDate, inSameDayAs: selectedDate) }) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title)
                                .font(.headline)
                            if !event.description.isEmpty {
                                Text(event.description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Text(event.startDate, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(event.isFamilyWide ? "All family" : assignedName(event))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Family Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingAddEvent = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAddEvent) {
                AddEventSheet(selectedDate: selectedDate)
                    .environmentObject(cloudKitService)
            }
        }
    }

    private func assignedName(_ event: CalendarEvent) -> String {
        cloudKitService.familyMembers.first { $0.id == event.assignedMemberID }?.displayName
            ?? "One person"
    }
}

struct AddEventSheet: View {
    @EnvironmentObject var cloudKitService: CloudKitService
    @Environment(\.dismiss) private var dismiss
    let selectedDate: Date

    @State private var eventTitle = ""
    @State private var eventDescription = ""
    @State private var eventLocation = ""
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(3600)
    @State private var addToAppleCalendar = true
    @State private var calendarError: String?
    @State private var isFamilyWide = true
    @State private var assignedMemberID: UUID?

    private var isParent: Bool {
        cloudKitService.canAddFamilyMembers
            || cloudKitService.currentUser?.role.caseInsensitiveCompare("Parent") == .orderedSame
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Title", text: $eventTitle)
                    TextField("Notes", text: $eventDescription)
                    TextField("Location", text: $eventLocation)
                }
                Section("Time") {
                    DatePicker("Start", selection: $startDate)
                    DatePicker("End", selection: $endDate)
                }
                Section("Who is this for") {
                    Toggle("All family", isOn: $isFamilyWide)
                    if isParent && !isFamilyWide {
                        Picker("Family member", selection: $assignedMemberID) {
                            Text("Choose").tag(Optional<UUID>.none)
                            ForEach(cloudKitService.familyMembers) { member in
                                Text(member.displayName).tag(Optional(member.id))
                            }
                        }
                    }
                    if !isFamilyWide {
                        Text("Parents still see this on Home and Calendar.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Toggle("Add to Apple Calendar", isOn: $addToAppleCalendar)
                } footer: {
                    Text("Uses a calendar named Family if you already have Apple Family Sharing. Otherwise it creates FamilyConnect on iCloud.")
                }
                if let calendarError {
                    Text(calendarError).foregroundStyle(.red)
                }
            }
            .navigationTitle("New Event")
            .onAppear {
                var components = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
                let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
                components.hour = now.hour
                components.minute = now.minute
                if let merged = Calendar.current.date(from: components) {
                    startDate = merged
                    endDate = merged.addingTimeInterval(3600)
                }
                assignedMemberID = cloudKitService.currentUser?.id
                isFamilyWide = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(eventTitle.trimmingCharacters(in: .whitespaces).isEmpty || (!isFamilyWide && isParent && assignedMemberID == nil))
                }
            }
        }
    }

    private func save() async {
        let mine = cloudKitService.currentUser?.id ?? UUID()
        let event = CalendarEvent(
            title: eventTitle.trimmingCharacters(in: .whitespaces),
            description: eventDescription,
            startDate: startDate,
            endDate: endDate,
            familyMemberID: mine,
            assignedMemberID: isFamilyWide ? nil : (assignedMemberID ?? mine),
            isFamilyWide: isFamilyWide
        )
        await cloudKitService.saveCalendarEvent(event)
        if addToAppleCalendar {
            do {
                try await AppleCalendarService.shared.addEvent(
                    title: eventTitle,
                    notes: [eventDescription, eventLocation].filter { !$0.isEmpty }.joined(separator: "\n"),
                    start: startDate,
                    end: endDate
                )
            } catch {
                calendarError = error.localizedDescription
                return
            }
        }
        dismiss()
    }
}

#Preview {
    CalendarView()
        .environmentObject(CloudKitService())
}

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
        let writable = store.calendars(for: .event).filter(\.allowsContentModifications)
        if let family = writable.first(where: { calendar in
            familyTitles.contains { calendar.title.caseInsensitiveCompare($0) == .orderedSame }
        }) {
            return family
        }
        if let fallback = store.defaultCalendarForNewEvents, fallback.allowsContentModifications {
            return fallback
        }
        if let any = writable.first {
            return any
        }
        throw AppleCalendarError.noCalendar
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

