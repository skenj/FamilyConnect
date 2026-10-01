import SwiftUI
import EventKit

enum CalendarScope: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"
    var id: String { rawValue }
}

struct CalendarView: View {
    @EnvironmentObject var cloudKitService: CloudKitService
    @State private var showingAddEvent = false
    @State private var selectedDate = Date()
    @State private var scope: CalendarScope = .month

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $scope) {
                    ForEach(CalendarScope.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                headerBar
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                switch scope {
                case .day:
                    dayTimeline
                case .week:
                    weekView
                case .month:
                    monthView
                case .year:
                    yearView
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") { selectedDate = Date() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddEvent = true } label: {
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

    private var navigationTitle: String {
        switch scope {
        case .day:
            return selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        case .week:
            return "Week of \(weekStart.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return selectedDate.formatted(.dateTime.month(.wide).year())
        case .year:
            return selectedDate.formatted(.dateTime.year())
        }
    }

    private var headerBar: some View {
        HStack {
            Button {
                shift(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(navigationTitle)
                .font(.headline)
            Spacer()
            Button {
                shift(1)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
    }

    private func shift(_ step: Int) {
        switch scope {
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: step, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = calendar.date(byAdding: .weekOfYear, value: step, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: step, to: selectedDate) ?? selectedDate
        case .year:
            selectedDate = calendar.date(byAdding: .year, value: step, to: selectedDate) ?? selectedDate
        }
    }

    private var visibleEvents: [CalendarEvent] {
        cloudKitService.calendarEvents.filter { event in
            let me = cloudKitService.currentUser?.id
            if event.isFamilyWide { return true }
            if event.assignedMemberID == me || event.familyMemberID == me { return true }
            let isParent = cloudKitService.canAddFamilyMembers
            return isParent
        }
    }

    private func events(on day: Date) -> [CalendarEvent] {
        visibleEvents
            .filter { calendar.isDate($0.startDate, inSameDayAs: day) }
            .sorted { $0.startDate < $1.startDate }
    }

    private func assignedName(_ event: CalendarEvent) -> String {
        if event.isFamilyWide { return "All family" }
        return cloudKitService.familyMembers.first { $0.id == event.assignedMemberID }?.displayName
            ?? "One person"
    }

    // MARK: Day

    private var dayTimeline: some View {
        let dayEvents = events(on: selectedDate)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    let slot = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: selectedDate) ?? selectedDate
                    let hourEvents = dayEvents.filter { calendar.component(.hour, from: $0.startDate) == hour }
                    HStack(alignment: .top, spacing: 10) {
                        Text(slot.formatted(.dateTime.hour().minute()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 6) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 1)
                            ForEach(hourEvents) { event in
                                eventCard(event)
                            }
                            if hourEvents.isEmpty {
                                Color.clear.frame(height: 28)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 2)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func eventCard(_ event: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.title)
                .font(.subheadline.weight(.semibold))
            Text("\(event.startDate.formatted(date: .omitted, time: .shortened)) · \(assignedName(event))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
    }

    // MARK: Week

    private var weekStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var weekView: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach(weekDays, id: \.self) { day in
                    Button {
                        selectedDate = day
                        scope = .day
                    } label: {
                        VStack(spacing: 4) {
                            Text(day.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption2)
                            Text("\(calendar.component(.day, from: day))")
                                .font(.headline)
                            Circle()
                                .fill(events(on: day).isEmpty ? Color.clear : Color.accentColor)
                                .frame(width: 6, height: 6)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(calendar.isDate(day, inSameDayAs: selectedDate) ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            List {
                ForEach(weekDays, id: \.self) { day in
                    Section(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) {
                        let items = events(on: day)
                        if items.isEmpty {
                            Text("No events")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(items) { event in
                                eventRow(event)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: Month

    private var monthView: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(weekdaySymbols, id: \.self) { label in
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 6)

            let days = monthGridDays
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(days, id: \.self) { day in
                    let inMonth = calendar.isDate(day, equalTo: selectedDate, toGranularity: .month)
                    Button {
                        selectedDate = day
                        scope = .day
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(calendar.component(.day, from: day))")
                                .font(.body.weight(calendar.isDateInToday(day) ? .bold : .regular))
                                .foregroundStyle(inMonth ? .primary : .tertiary)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle().fill(calendar.isDate(day, inSameDayAs: selectedDate) ? Color.accentColor.opacity(0.2) : Color.clear)
                                )
                            Circle()
                                .fill(events(on: day).isEmpty ? Color.clear : Color.accentColor)
                                .frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            List {
                let items = events(on: selectedDate)
                Section(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day())) {
                    if items.isEmpty {
                        Text("No events. Tap a date for the 24-hour day.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { event in
                            eventRow(event)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private var monthGridDays: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate),
              let gridStart = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start)?.start else {
            return []
        }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    // MARK: Year

    private var yearView: some View {
        let year = calendar.component(.year, from: selectedDate)
        return ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(1...12, id: \.self) { month in
                    let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? selectedDate
                    Button {
                        selectedDate = date
                        scope = .month
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(date.formatted(.dateTime.month(.abbreviated)))
                                .font(.headline)
                            miniMonth(date)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    private func miniMonth(_ monthDate: Date) -> some View {
        let days = miniMonthDays(monthDate)
        return VStack(spacing: 2) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 2) {
                ForEach(days, id: \.self) { day in
                    let inMonth = calendar.isDate(day, equalTo: monthDate, toGranularity: .month)
                    Circle()
                        .fill(events(on: day).isEmpty || !inMonth ? Color.clear : Color.accentColor)
                        .frame(width: 6, height: 6)
                        .overlay {
                            if inMonth {
                                Text("\(calendar.component(.day, from: day))")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 10)
                }
            }
        }
    }

    private func miniMonthDays(_ monthDate: Date) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthDate),
              let gridStart = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start)?.start else {
            return []
        }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title).font(.headline)
            if !event.description.isEmpty {
                Text(event.description).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(event.startDate, style: .time).font(.caption).foregroundStyle(.secondary)
            Text(assignedName(event)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
                    Text("Uses a calendar named Family if you already have Apple Family Sharing. Otherwise it writes to your default calendar.")
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
