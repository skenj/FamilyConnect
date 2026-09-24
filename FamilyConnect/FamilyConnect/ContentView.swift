//
//  ContentView.swift
//  FamilyConnect
//
//  Created by Nick Skewes on 16/9/2026.
//


import SwiftUI

struct ContentView: View {
    @StateObject private var cloudKitService = CloudKitService()
    @State private var selectedTab: String = "calendar"
    
    var body: some View {
        TabView(selection: $selectedTab) {
            CalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag("calendar")
            
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }
                .tag("chat")
            
            LocationView()
                .tabItem {
                    Label("Location", systemImage: "location.fill")
                }
                .tag("location")
            
            FamilyView()
                .tabItem {
                    Label("Family", systemImage: "person.3.fill")
                }
                .tag("family")
        }
        .environmentObject(cloudKitService)
    }
}

#Preview {
    ContentView()
}
