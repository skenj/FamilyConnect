import SwiftUI

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
                            Text(event.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(event.startDate, style: .time)
                                .font(.caption)
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
                AddEventSheet(isPresented: $showingAddEvent, cloudKitService: cloudKitService, selectedDate: selectedDate)
            }
        }
    }
}

struct AddEventSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var cloudKitService: CloudKitService
    let selectedDate: Date
    
    @State private var eventTitle = ""
    @State private var eventDescription = ""
    @State private var eventLocation = ""
    @State private var endDate: Date = Date().addingTimeInterval(3600)
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Event Details") {
                    TextField("Title", text: $eventTitle)
                    TextField("Description", text: $eventDescription)
                    TextField("Location", text: $eventLocation)
                }
                
                Section("Time") {
                    DatePicker("Start", selection: .constant(selectedDate))
                    DatePicker("End", selection: $endDate)
                }
                
                Section {
                    Button("Add Event") {
                        let event = CalendarEvent(
                            title: eventTitle,
                            description: eventDescription,
                            startDate: selectedDate,
                            endDate: endDate,
                            familyMemberID: UUID()
                        )
                        cloudKitService.saveCalendarEvent(event)
                        isPresented = false
                    }
                    .disabled(eventTitle.isEmpty)
                }
            }
            .navigationTitle("New Event")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    CalendarView()
        .environmentObject(CloudKitService())
}
