//
//  ContentView.swift
//  Halo-iOS
//
//  Created by Cyril Zakka on 10/21/24.
//

import SwiftUI
import AccessorySetupKit

// All possible navigation paths. Extend here as needed.
enum NavigationPath: String, CaseIterable, Identifiable {
    case heartRate = "Heart Rate"
    case spo2 = "SPO2"
    case timeline = "Timeline"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .heartRate:
            return "heart.fill"
        case .spo2:
            return "drop.circle.fill"
        case .timeline:
            return "clock.arrow.circlepath"
        }
    }
    
    var tintColor: Color {
        switch self {
        case .heartRate:
            return .pink
        case .spo2:
            return .blue
        case .timeline:
            return .teal
        }
    }
}

struct ContentView: View {
    
    @State var ringSessionManager = RingSessionManager()
    @State var batteryInfo: BatteryInfo?
    
    @State private var selection: NavigationPath? = nil
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("MY DEVICE", content: {
                    if ringSessionManager.pickerDismissed, let currentRing = ringSessionManager.currentRing {
                        makeRingView(ring: currentRing)
                    } else {
                        Button {
                            ringSessionManager.presentPicker()
                        } label: {
                            Text("Add Ring")
                                .frame(maxWidth: .infinity)
                                .font(Font.headline.weight(.semibold))
                        }
                    }
                })
                
                Section("Metrics", content: {
                    ForEach(NavigationPath.allCases.filter { $0 != .timeline }) { navPath in
                        NavigationLink(value: navPath) {
                            HStack {
                                Image(systemName: navPath.icon)
                                    .foregroundStyle(navPath.tintColor)
                                Text(navPath.rawValue)
                            }
                        }
                    }
                })
                
                Section("Timeline", content: {
                    NavigationLink(value: NavigationPath.timeline) {
                        HStack {
                            Image(systemName: NavigationPath.timeline.icon)
                                .foregroundStyle(NavigationPath.timeline.tintColor)
                            Text(NavigationPath.timeline.rawValue)
                        }
                    }
                })
                
                if ringSessionManager.peripheralConnected {
                    Button(action: {
                        ringSessionManager.removeRing()
                    }, label: {
                        Text("Delete Ring")
                            .frame(maxWidth: .infinity)
                            .tint(.red)
                    })
                }
                
                Section("Debug", content: {
                    Button {
                        ringSessionManager.rawLoggingEnabled.toggle()
                    } label: {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(ringSessionManager.rawLoggingEnabled ? .green : .secondary)
                            Text(ringSessionManager.rawLoggingEnabled ? "Raw logging: On" : "Raw logging: Off")
                        }
                    }
                })
                
            }.listStyle(.insetGrouped)
        } detail: {
            if let selectedPath = selection {
                detailView(for: selectedPath)
            } else {
                EmptyView()
            }
        }
        .onChange(of: ringSessionManager.peripheralReady) {
            if ringSessionManager.peripheralReady {
                ringSessionManager.getBatteryStatus { info in
                    batteryInfo = info
                }
            }
        }
        
    }
    
    @ViewBuilder
    private func makeRingView(ring: ASAccessory) -> some View {
        HStack {
            Image("colmi")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 60)
            
            VStack(alignment: .leading, spacing: 5) {
                Text(ring.displayName)
                    .font(Font.headline.weight(.semibold))
                HStack(spacing: 5) {
                    if let batteryInfo {
                        BatteryView(isCharging: batteryInfo.charging, batteryLevel: batteryInfo.batteryLevel)
                        Text("\(batteryInfo.batteryLevel)%")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    
                }
            }
        }
    }
    
    @ViewBuilder
    private func detailView(for path: NavigationPath) -> some View {
        switch path {
        case .heartRate:
            HeartRateView()
                .environment(ringSessionManager)
        case .spo2:
            SPO2View()
                .environment(ringSessionManager)
        case .timeline:
            TimelineView()
                .environment(ringSessionManager)
        }
    }
}

#Preview {
    ContentView(ringSessionManager: PreviewRingSessionManager())
}
