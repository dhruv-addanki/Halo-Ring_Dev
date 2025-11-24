//
//  SPO2View.swift
//  Halo-iOS
//
//  Created by Cyril Zakka on 3/17/25.
//

import SwiftUI

struct SPO2View: View {
    
    @Environment(RingSessionManager.self) private var ringSessionManager
    @State private var isStreaming = false
    
    private var spo2Text: String {
        if let latest = ringSessionManager.latestSpO2 {
            return "\(latest)"
        }
        return "--"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Blood Oxygen", systemImage: "drop.fill")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(spo2Text)
                            .font(.largeTitle)
                            .fontWeight(.semibold)
                            .contentTransition(.numericText())
                        
                        Text("%")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical)
                    
                    Button(action: {
                        isStreaming.toggle()
                        if isStreaming {
                            ringSessionManager.startRealTimeStreaming(type: .spo2)
                        } else {
                            ringSessionManager.stopRealTimeStreaming(type: .spo2)
                        }
                    }, label: {
                        Group {
                            if isStreaming {
                                Text("Stop Spot Check")
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                Text("Start Spot Check")
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .frame(height: 50)
                        .foregroundStyle(.white)
                        .buttonStyle(.plain)
                        .background {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(Color(.systemBlue))
                        }
                    })
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color(.systemGray6))
                }
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    SPO2View()
        .environment(RingSessionManager())
}
