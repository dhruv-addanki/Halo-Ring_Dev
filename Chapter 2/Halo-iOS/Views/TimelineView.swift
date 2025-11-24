//
//  TimelineView.swift
//  Halo-iOS
//
//  Created by Codex on 3/20/25.
//

import SwiftUI

struct TimelineView: View {
    
    @Environment(RingSessionManager.self) private var ringSessionManager
    
    var body: some View {
        List {
            ForEach(Array(ringSessionManager.events.reversed())) { event in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title(for: event))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(event.timestamp, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(metadataText(for: event))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Timeline")
    }
    
    private func title(for event: TimelineEvent) -> String {
        switch event.kind {
        case .heartRate:
            return "Heart Rate"
        case .spo2:
            return "SpO2"
        case .battery:
            return "Battery"
        case .connection:
            return "Connection"
        case .raw:
            return "Raw Packet"
        }
    }
    
    private func metadataText(for event: TimelineEvent) -> String {
        switch event.kind {
        case .heartRate:
            return "BPM: \(event.metadata["bpm"] ?? "--")"
        case .spo2:
            return "SpO2: \(event.metadata["spo2"] ?? "--")%"
        case .battery:
            let level = event.metadata["level"] ?? "--"
            let charging = event.metadata["charging"] ?? "false"
            return "Battery: \(level)% • Charging: \(charging)"
        case .connection:
            return "State: \(event.metadata["state"] ?? "--")"
        case .raw:
            return event.metadata["packet"] ?? ""
        }
    }
}

#Preview {
    TimelineView()
        .environment(RingSessionManager())
}
