//
//  RootView.swift
//  FamilyConnect
//
//  Created by Nick Skewes on 1/10/2026.
//


struct RootView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService

    var body: some View {
        Group {
            if !cloudKitService.isSignedIn {
                AuthView()
            } else if !cloudKitService.pendingInvites.isEmpty && !cloudKitService.belongsToSomeoneElsesFamily {
                InviteDecisionView()
            } else {
                ContentView()
            }
        }
    }
}