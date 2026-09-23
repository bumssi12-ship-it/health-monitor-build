import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("상태", systemImage: "heart.text.square")
                }

            SymptomsView()
                .tabItem {
                    Label("증상", systemImage: "exclamationmark.bubble")
                }

            OrthostaticView()
                .tabItem {
                    Label("기립", systemImage: "figure.stand")
                }

            MedicationImpactView()
                .tabItem {
                    Label("비교", systemImage: "chart.xyaxis.line")
                }

            ReportView()
                .tabItem {
                    Label("리포트", systemImage: "doc.text")
                }

            DiagnosticsView()
                .tabItem {
                    Label("관리", systemImage: "wrench.and.screwdriver")
                }

            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape")
                }
        }
    }
}
