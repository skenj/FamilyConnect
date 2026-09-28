import SwiftUI
import CoreLocation
import MapKit

struct HomeView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @StateObject private var weather = HomeWeatherController()
    @State private var showingWeatherDetail = false
    @State private var showingSuggest = false
    @State private var showingMap = false

    private var greetingName: String {
        let raw = cloudKitService.currentUser?.displayName
            ?? cloudKitService.currentUser?.nickname
            ?? cloudKitService.currentUser?.name
            ?? "there"
        let first = raw.split(separator: " ").first.map(String.init) ?? raw
        return first.isEmpty ? "there" : first
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return "\(part), \(greetingName)"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                    Text(greeting)
                        .font(.title3.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let invite = cloudKitService.pendingInvites.first {
                        pendingInviteBanner(invite)
                    }

                    weatherTile

                    scheduleSection
                    messagesSection

                    Button {
                        showingSuggest = true
                    } label: {
                        Label("What can we cook tonight?", systemImage: "fork.knife")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    homeMapPreview
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await weather.refresh()
                await cloudKitService.fetchPendingInvites()
            }
            .sheet(isPresented: $showingWeatherDetail) {
                WeatherDetailSheet(weather: weather)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingMap) {
                HomeMapSheet(title: weather.placeName)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingSuggest) {
                MealSuggestView()
                    .environmentObject(cloudKitService)
            }
        }
    }

    private var weatherTile: some View {
        Button {
            showingWeatherDetail = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: weather.symbolName)
                    .font(.system(size: 34))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(weather.placeName.isEmpty ? "Local weather" : weather.placeName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(weather.summary)
                        .font(.subheadline)
                        .opacity(0.9)
                        .lineLimit(1)
                }
                Spacer()
                Text(weather.temperatureText)
                    .font(.title2.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(weatherUsesLightText ? Color.white : Color.primary)
            .padding()
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(weatherBackground)
                    WeatherAtmosphere(code: weather.weatherCode)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func pendingInviteBanner(_ invite: PendingFamilyInvite) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(invite.organizerName) invited you to \(invite.familyName)")
                .font(.subheadline.weight(.semibold))
            HStack {
                Button("Accept") {
                    Task { await cloudKitService.acceptPendingInvite(invite) }
                }
                .buttonStyle(.borderedProminent)
                Button("Not now") {
                    Task { await cloudKitService.declinePendingInvite(invite) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.12)))
    }

    private var weatherUsesLightText: Bool {
        switch weather.weatherCode {
        case 71...77, 1, 2:
            return false
        default:
            return true
        }
    }

    private var weatherBackground: LinearGradient {
        switch weather.weatherCode {
        case 0:
            return LinearGradient(colors: [Color(red: 0.20, green: 0.55, blue: 0.95), Color(red: 0.95, green: 0.75, blue: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case 1, 2:
            return LinearGradient(colors: [Color(red: 0.45, green: 0.70, blue: 0.95), Color(red: 0.85, green: 0.88, blue: 0.95)], startPoint: .top, endPoint: .bottom)
        case 3:
            return LinearGradient(colors: [Color(red: 0.45, green: 0.50, blue: 0.58), Color(red: 0.70, green: 0.74, blue: 0.80)], startPoint: .top, endPoint: .bottom)
        case 45, 48:
            return LinearGradient(colors: [Color(red: 0.55, green: 0.58, blue: 0.62), Color(red: 0.78, green: 0.80, blue: 0.82)], startPoint: .top, endPoint: .bottom)
        case 51...57, 61...67, 80...82:
            return LinearGradient(colors: [Color(red: 0.25, green: 0.38, blue: 0.55), Color(red: 0.40, green: 0.52, blue: 0.68)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case 71...77:
            return LinearGradient(colors: [Color(red: 0.70, green: 0.82, blue: 0.95), Color(red: 0.88, green: 0.92, blue: 0.98)], startPoint: .top, endPoint: .bottom)
        case 95...99:
            return LinearGradient(colors: [Color(red: 0.18, green: 0.20, blue: 0.32), Color(red: 0.35, green: 0.38, blue: 0.55)], startPoint: .top, endPoint: .bottom)
        default:
            return LinearGradient(colors: [Color(red: 0.35, green: 0.55, blue: 0.80), Color(red: 0.55, green: 0.70, blue: 0.88)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var homeMapPreview: some View {
        Button {
            showingMap = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(weather.placeName.isEmpty ? "Your location" : weather.placeName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("Open map")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Map(initialPosition: .userLocation(fallback: .automatic), interactionModes: []) {
                    UserAnnotation()
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
    }

    private var scheduleSection: some View {
        let events = relevantEvents
        return VStack(alignment: .leading, spacing: 8) {
            Text("Your schedule")
                .font(.headline)
            if events.isEmpty {
                Text("No upcoming events for you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events.prefix(2)) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(event.title)
                            Spacer()
                            Text(event.startDate, style: .time)
                                .foregroundStyle(.secondary)
                        }
                        Text(scheduleCaption(event))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private var messagesSection: some View {
        let notes = relevantChats
        return VStack(alignment: .leading, spacing: 8) {
            Text("Your messages")
                .font(.headline)
            if notes.isEmpty {
                Text("No messages just for you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(notes.suffix(2)) { message in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.senderName).font(.caption).foregroundStyle(.secondary)
                        Text(message.content).font(.subheadline)
                    }
                }
            }
        }
    }

    private var isParent: Bool {
        cloudKitService.canAddFamilyMembers
            || cloudKitService.currentUser?.role.caseInsensitiveCompare("Parent") == .orderedSame
    }

    private func scheduleCaption(_ event: CalendarEvent) -> String {
        if event.isFamilyWide { return "All family" }
        let me = cloudKitService.currentUser?.id
        if event.assignedMemberID == me || event.familyMemberID == me { return "For you" }
        if let id = event.assignedMemberID,
           let name = cloudKitService.familyMembers.first(where: { $0.id == id })?.displayName {
            return "For \(name)"
        }
        return "For a child"
    }

    private var relevantEvents: [CalendarEvent] {
        let me = cloudKitService.currentUser?.id
        return cloudKitService.calendarEvents
            .filter { event in
                if event.isFamilyWide { return true }
                if event.assignedMemberID == me || event.familyMemberID == me { return true }
                if isParent { return true }
                return false
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private var relevantChats: [ChatMessage] {
        guard let me = cloudKitService.currentUser else { return [] }
        return cloudKitService.chatMessages.filter { message in
            message.mentionedIDs.contains(me.id) ||
            message.notifyScope.split(separator: ",").map(String.init).contains(me.id.uuidString)
        }
    }
}

struct WeatherDetailSheet: View {
    @ObservedObject var weather: HomeWeatherController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(weather.placeName.isEmpty ? "Weather" : weather.placeName) {
                    labeled("Condition", weather.condition)
                    labeled("Temperature", weather.temperatureText)
                    labeled("Feels like", weather.feelsLikeText)
                    labeled("Humidity", weather.humidityText)
                    labeled("Wind", weather.windText)
                    if !weather.updatedText.isEmpty {
                        labeled("Updated", weather.updatedText)
                    }
                }
                if !weather.daily.isEmpty {
                    Section("Next days") {
                        ForEach(weather.daily) { day in
                            HStack {
                                Text(day.label)
                                Spacer()
                                Image(systemName: day.symbol)
                                Text(day.range)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Weather")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}

@MainActor
final class HomeWeatherController: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var placeName = ""
    @Published var temperatureText = "--°"
    @Published var feelsLikeText = "--"
    @Published var humidityText = "--"
    @Published var windText = "--"
    @Published var condition = "Finding location…"
    @Published var summary = "Finding location…"
    @Published var symbolName = "location"
    @Published var weatherCode = 0
    @Published var updatedText = ""
    @Published var daily: [HomeWeatherDay] = []

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func refresh() async {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            await load(from: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            summary = "Location unavailable"
            condition = "Location unavailable"
        }
    }

    private func load(from location: CLLocation) async {
        await reverseGeocode(location)
        await fetchForecast(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    private func reverseGeocode(_ location: CLLocation) async {
        if let marks = try? await CLGeocoder().reverseGeocodeLocation(location),
           let mark = marks.first {
            placeName = [mark.locality, mark.subLocality, mark.administrativeArea]
                .compactMap { $0 }
                .first { !$0.isEmpty } ?? mark.name ?? ""
        }
    }

    private func fetchForecast(latitude: Double, longitude: Double) async {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "5")
        ]
        guard let url = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            summary = "Weather unavailable"
            return
        }
        if let current = json["current"] as? [String: Any] {
            let temp = current["temperature_2m"] as? Double
            let feel = current["apparent_temperature"] as? Double
            let humidity = current["relative_humidity_2m"] as? Double
            let wind = current["wind_speed_10m"] as? Double
            let code = current["weather_code"] as? Int ?? 0
            temperatureText = temp.map { "\(Int($0.rounded()))°" } ?? "--°"
            feelsLikeText = feel.map { "\(Int($0.rounded()))°" } ?? "--"
            humidityText = humidity.map { "\(Int($0.rounded()))%" } ?? "--"
            windText = wind.map { "\(Int($0.rounded())) km/h" } ?? "--"
            condition = Self.conditionName(code)
            summary = "\(Self.conditionName(code))  \(temperatureText)"
            symbolName = Self.symbol(code)
            weatherCode = code
            updatedText = Date().formatted(date: .omitted, time: .shortened)
        }
        if let dailyJSON = json["daily"] as? [String: Any],
           let dates = dailyJSON["time"] as? [String],
           let maxs = dailyJSON["temperature_2m_max"] as? [Double],
           let mins = dailyJSON["temperature_2m_min"] as? [Double] {
            let codes = dailyJSON["weather_code"] as? [Int] ?? []
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            daily = zip(dates.indices, dates).prefix(5).map { index, dateString in
                let date = formatter.date(from: dateString) ?? Date()
                let label = date.formatted(.dateTime.weekday(.wide))
                let high = Int((maxs[safe: index] ?? 0).rounded())
                let low = Int((mins[safe: index] ?? 0).rounded())
                return HomeWeatherDay(
                    id: dateString,
                    label: label,
                    range: "\(high)° / \(low)°",
                    symbol: Self.symbol(codes[safe: index] ?? 0)
                )
            }
        }
    }

    static func conditionName(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2: return "Mostly clear"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...67: return "Rain"
        case 71...77: return "Snow"
        case 80...82: return "Showers"
        case 95...99: return "Thunderstorm"
        default: return "Weather"
        }
    }

    static func symbol(_ code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...67, 80...82: return "cloud.rain.fill"
        case 71...77: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.sun.fill"
        }
    }
}

struct HomeWeatherDay: Identifiable {
    let id: String
    let label: String
    let range: String
    let symbol: String
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// CalendarEvent.isFamilyWide / assignedMemberID live on the model.

struct WeatherAtmosphere: View {
    let code: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                switch code {
                case 0:
                    drawSun(ctx, size: size, t: t)
                case 1, 2, 3:
                    drawClouds(ctx, size: size, t: t, count: code == 3 ? 6 : 4)
                case 45, 48:
                    drawFog(ctx, size: size, t: t)
                case 51...57, 61...67, 80...82:
                    drawRain(ctx, size: size, t: t, heavy: code >= 61)
                case 71...77:
                    drawSnow(ctx, size: size, t: t)
                case 95...99:
                    drawRain(ctx, size: size, t: t, heavy: true)
                    drawLightning(ctx, size: size, t: t)
                default:
                    drawClouds(ctx, size: size, t: t, count: 3)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawSun(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let pulse = 0.55 + 0.15 * sin(t * 1.6)
        ctx.fill(
            Path(ellipseIn: CGRect(x: size.width - 70, y: -20, width: 90, height: 90)),
            with: .color(.yellow.opacity(pulse))
        )
    }

    private func drawClouds(_ ctx: GraphicsContext, size: CGSize, t: Double, count: Int) {
        for i in 0..<count {
            let speed = 12.0 + Double(i) * 4
            let x = (CGFloat(t * speed) + CGFloat(i) * 70).truncatingRemainder(dividingBy: size.width + 80) - 40
            let y = 8 + CGFloat(i % 3) * 16
            var path = Path(ellipseIn: CGRect(x: x, y: y, width: 70, height: 22))
            path.addEllipse(in: CGRect(x: x + 20, y: y - 8, width: 44, height: 22))
            ctx.fill(path, with: .color(.white.opacity(0.28)))
        }
    }

    private func drawFog(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        for i in 0..<5 {
            let x = (CGFloat(t * 8) + CGFloat(i) * 40).truncatingRemainder(dividingBy: size.width + 60) - 30
            ctx.fill(
                Path(ellipseIn: CGRect(x: x, y: 10 + CGFloat(i) * 12, width: 120, height: 18)),
                with: .color(.white.opacity(0.22))
            )
        }
    }

    private func drawRain(_ ctx: GraphicsContext, size: CGSize, t: Double, heavy: Bool) {
        let drops = heavy ? 28 : 16
        for i in 0..<drops {
            let seed = Double(i) * 17.3
            let x = (CGFloat(seed * 13 + t * 40).truncatingRemainder(dividingBy: size.width))
            let y = (CGFloat(seed * 9 + t * (heavy ? 180 : 120)).truncatingRemainder(dividingBy: size.height))
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + 2, y: y + 10))
            ctx.stroke(path, with: .color(.white.opacity(0.55)), lineWidth: 1.2)
        }
    }

    private func drawSnow(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        for i in 0..<22 {
            let seed = Double(i) * 11.7
            let x = (CGFloat(seed * 19 + sin(t + seed) * 12).truncatingRemainder(dividingBy: size.width + 10))
            let y = (CGFloat(seed * 7 + t * 35).truncatingRemainder(dividingBy: size.height))
            ctx.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: 4, height: 4)),
                with: .color(.white.opacity(0.85))
            )
        }
    }

    private func drawLightning(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let flash = sin(t * 9) > 0.92
        if flash {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.25)))
        }
    }
}

struct HomeMapSheet: View {
    var title: String
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        NavigationStack {
            Map(position: $position, interactionModes: [.pan, .zoom, .pitch]) {
                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(title.isEmpty ? "Your location" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

