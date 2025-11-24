//
//  RingSessionManager.swift
//  Halo-iOS
//
//  Created by Cyril Zakka on 10/21/24.
//

import Foundation
import AccessorySetupKit
import CoreBluetooth
import SwiftUI

struct TimelineEvent: Identifiable, Hashable {
    enum Kind: Hashable {
        case heartRate
        case battery
        case connection
    }
    
    let id = UUID()
    let timestamp: Date
    let kind: Kind
    let metadata: [String: String]
}

extension TimelineEvent {
    static func heartRate(bpm: Int, source: String = "ring") -> TimelineEvent {
        TimelineEvent(
            timestamp: Date(),
            kind: .heartRate,
            metadata: [
                "bpm": "\(bpm)",
                "source": source
            ]
        )
    }
    
    static func battery(level: Int, charging: Bool) -> TimelineEvent {
        TimelineEvent(
            timestamp: Date(),
            kind: .battery,
            metadata: [
                "level": "\(level)",
                "charging": "\(charging)"
            ]
        )
    }
    
    static func connection(state: String) -> TimelineEvent {
        TimelineEvent(
            timestamp: Date(),
            kind: .connection,
            metadata: ["state": state]
        )
    }
}

@Observable
class RingSessionManager: NSObject {
    
    var peripheralConnected = false
    var peripheralReady = false
    var pickerDismissed = true
    var latestHeartRate: Int?
    var events: [TimelineEvent] = []
    
    var currentRing: ASAccessory?
    private var session = ASAccessorySession()
    private var manager: CBCentralManager?
    private var peripheral: CBPeripheral?
    
    private var uartRxCharacteristic: CBCharacteristic?
    private var uartTxCharacteristic: CBCharacteristic?
    
    private static let mainServiceUUID = "DE5BF728-D711-4E47-AF26-65E3012A5DC7"
    private static let mainWriteCharacteristicUUID = "DE5BF72A-D711-4E47-AF26-65E3012A5DC7"
    private static let mainNotifyCharacteristicUUID = "DE5BF729-D711-4E47-AF26-65E3012A5DC7"
    
    private static let ringServiceUUID = "6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E"
    private static let uartRxCharacteristicUUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    private static let uartTxCharacteristicUUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
    
    private static let deviceInfoServiceUUID = "0000180A-0000-1000-8000-00805F9B34FB"
    private static let deviceHardwareUUID = "00002A27-0000-1000-8000-00805F9B34FB"
    private static let deviceFirmwareUUID = "00002A26-0000-1000-8000-00805F9B34FB"
    
    // Realtime
    private static let CMD_START_REAL_TIME: UInt8 = 105
    private static let CMD_STOP_REAL_TIME: UInt8 = 106
    
    // Battery
    private static let CMD_BATTERY: UInt8 = 3
    var batteryStatusCallback: ((BatteryInfo) -> Void)?
    private var scanInProgress = false
    
    private static let ring: ASPickerDisplayItem = {
        let descriptor = ASDiscoveryDescriptor()
        descriptor.bluetoothCompanyIdentifier = ASBluetoothCompanyIdentifier(4660)
        
        return ASPickerDisplayItem(
            name: "COLMI R02 Ring",
            productImage: UIImage(named: "colmi")!,
            descriptor: descriptor
        )
    }()
    
    override init() {
        super.init()
        self.session.activate(on: DispatchQueue.main, eventHandler: handleSessionEvent(event:))
    }
    
    // MARK: - RingSessionManager actions
    func presentPicker() {
        session.showPicker(for: [Self.ring]) { error in
            if let error {
                print("Failed to show picker due to: \(error.localizedDescription)")
            }
        }
    }
    
    func removeRing() {
        guard let currentRing else { return }
        
        if peripheralConnected {
            disconnect()
        }
        
        session.removeAccessory(currentRing) { _ in
            self.currentRing = nil
            self.manager = nil
        }
    }
    
    func connect() {
        guard
            let manager, manager.state == .poweredOn,
            let peripheral
        else {
            return
        }
        let options: [String: Any] = [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionStartDelayKey: 1
        ]
        manager.connect(peripheral, options: options)
    }
    
    func disconnect() {
        guard let peripheral, let manager else { return }
        manager.cancelPeripheralConnection(peripheral)
        stopScanIfNeeded()
    }
    
    // MARK: - ASAccessorySession functions
    private func saveRing(ring: ASAccessory) {
        currentRing = ring
        
        if manager == nil {
            manager = CBCentralManager(delegate: self, queue: nil)
        }
    }
    
    private func startScanForRingIfNeeded() {
        guard let manager, manager.state == .poweredOn, !scanInProgress, peripheral == nil else { return }
        print("Starting scan for ring...")
        manager.scanForPeripherals(
            withServices: [CBUUID(string: Self.ringServiceUUID)],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        scanInProgress = true
    }
    
    private func stopScanIfNeeded() {
        guard let manager, scanInProgress else { return }
        manager.stopScan()
        scanInProgress = false
    }
    
    private func handleSessionEvent(event: ASAccessoryEvent) {
        print(event)
        switch event.eventType {
        case .accessoryAdded, .accessoryChanged:
            guard let ring = event.accessory else { return }
            saveRing(ring: ring)
        case .activated:
            guard let ring = session.accessories.first else { return }
            saveRing(ring: ring)
        case .accessoryRemoved:
            self.currentRing = nil
            self.manager = nil
        case .pickerDidPresent:
            pickerDismissed = false
        case .pickerDidDismiss:
            pickerDismissed = true
        default:
            print("Received event type \(event.eventType)")
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension RingSessionManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("Central manager state: \(central.state)")
        switch central.state {
        case .poweredOn:
            if let peripheralUUID = currentRing?.bluetoothIdentifier,
               let knownPeripheral = central.retrievePeripherals(withIdentifiers: [peripheralUUID]).first {
                print("Found previously connected peripheral")
                peripheral = knownPeripheral
                peripheral?.delegate = self
                connect()
            } else {
                print("Known peripheral not found, starting scan")
                startScanForRingIfNeeded()
            }
        default:
            peripheral = nil
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Discovered peripheral: \(peripheral)")
        stopScanIfNeeded()
        self.peripheral = peripheral
        self.peripheral?.delegate = self
        connect()
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("DEBUG: Connected to peripheral: \(peripheral)")
        stopScanIfNeeded()
        peripheral.delegate = self
        print("DEBUG: Discovering services...")
        peripheral.discoverServices([
            CBUUID(string: Self.ringServiceUUID),
            CBUUID(string: Self.deviceInfoServiceUUID),
            CBUUID(string: Self.mainServiceUUID)
        ])
        
        peripheralConnected = true
        recordEvent(.connection(state: "connected"))
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        print("Disconnected from peripheral: \(peripheral)")
        peripheralConnected = false
        peripheralReady = false
        self.peripheral = nil
        recordEvent(.connection(state: "disconnected"))
        startScanForRingIfNeeded()
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        print("Failed to connect to peripheral: \(peripheral), error: \(error.debugDescription)")
        self.peripheral = nil
        startScanForRingIfNeeded()
    }
}

// MARK: - CBPeripheralDelegate
extension RingSessionManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        print("DEBUG: Services discovery callback, error: \(String(describing: error))")
        guard error == nil, let services = peripheral.services else {
            print("DEBUG: No services found or error occurred")
            return
        }
        
        print("DEBUG: Found \(services.count) services")
        for service in services {
            switch service.uuid {
            case CBUUID(string: Self.ringServiceUUID):
                print("DEBUG: Found ring service, discovering characteristics...")
                peripheral.discoverCharacteristics([
                    CBUUID(string: Self.uartRxCharacteristicUUID),
                    CBUUID(string: Self.uartTxCharacteristicUUID)
                ], for: service)
            case CBUUID(string: Self.deviceInfoServiceUUID):
                print("DEBUG: Found device info service")
            default:
                break
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        print("DEBUG: Characteristics discovery callback, error: \(String(describing: error))")
        guard error == nil, let characteristics = service.characteristics else {
            print("DEBUG: No characteristics found or error occurred")
            return
        }
        
        print("DEBUG: Found \(characteristics.count) characteristics")
        for characteristic in characteristics {
            switch characteristic.uuid {
            case CBUUID(string: Self.uartRxCharacteristicUUID):
                print("DEBUG: Found UART RX characteristic")
                self.uartRxCharacteristic = characteristic
            case CBUUID(string: Self.uartTxCharacteristicUUID):
                print("DEBUG: Found UART TX characteristic")
                self.uartTxCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                print("DEBUG: Found other characteristic: \(characteristic.uuid)")
            }
        }
        
        let rxDiscovered = uartRxCharacteristic != nil
        let txDiscovered = uartTxCharacteristic != nil
        peripheralReady = rxDiscovered && txDiscovered
        
        if peripheralReady {
            recordEvent(.connection(state: "ready"))
            print("Peripheral ready for UART communication")
        } else {
            print("Peripheral not ready, missing UART characteristics")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else {
            print("Failed to read characteristic value: \(String(describing: error))")
            return
        }
        
        let packet = [UInt8](value)
        guard let command = packet.first else {
            print("Received empty packet")
            return
        }
        
        switch command {
        case RingSessionManager.CMD_BATTERY:
            guard packet.count >= 3 else {
                print("Battery packet too short: \(packet)")
                return
            }
            handleBatteryResponse(packet: packet)
        case RingSessionManager.CMD_START_REAL_TIME:
            guard packet.count >= 4 else {
                print("Realtime packet too short: \(packet)")
                return
            }
            let readingType = RealTimeReading(rawValue: packet[1]) ?? .heartRate
            let errorCode = packet[2]
            
            if errorCode == 0 {
                let readingValue = Int(packet[3])
                print("Real-Time Reading - Type: \(readingType), Value: \(readingValue)")
                if readingType == .heartRate {
                    DispatchQueue.main.async {
                        self.latestHeartRate = readingValue
                        self.recordEvent(.heartRate(bpm: readingValue))
                    }
                }
            } else {
                print("Error in reading - Type: \(readingType), Error Code: \(errorCode)")
            }
        default:
            print("Unhandled packet: \(packet)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Write to characteristic failed: \(error.localizedDescription)")
        } else {
            print("Write to characteristic successful")
        }
    }
}

// MARK: - RealTime Streaming
extension RingSessionManager {
    func startRealTimeStreaming(type: RealTimeReading) {
        sendRealTimeCommand(command: RingSessionManager.CMD_START_REAL_TIME, type: type, action: .start)
    }
    
    func continueRealTimeStreaming(type: RealTimeReading) {
        sendRealTimeCommand(command: RingSessionManager.CMD_START_REAL_TIME, type: type, action: .continue)
    }
    
    func stopRealTimeStreaming(type: RealTimeReading) {
        sendRealTimeCommand(command: RingSessionManager.CMD_STOP_REAL_TIME, type: type, action: .stop)
    }
    
    private func sendRealTimeCommand(command: UInt8, type: RealTimeReading, action: Action?) {
        guard let uartRxCharacteristic, let peripheral else {
            print("Cannot send real-time command. Peripheral or characteristic not ready.")
            return
        }
        
        var packetData: [UInt8] = [type.rawValue]
        if let action = action {
            packetData.append(action.rawValue)
        } else {
            packetData.append(contentsOf: [0, 0])
        }
        
        do {
            let packet = try makePacket(command: command, subData: packetData)
            let data = Data(packet)
            peripheral.writeValue(data, for: uartRxCharacteristic, type: .withResponse)
        } catch {
            print("Failed to create packet: \(error)")
        }
    }
}


// MARK: - Battery Status
extension RingSessionManager {
    func getBatteryStatus(completion: @escaping (BatteryInfo) -> Void) {
        guard let uartRxCharacteristic, let peripheral else {
            print("Cannot send battery request. Peripheral or characteristic not ready.")
            return
        }
        
        do {
            let packet = try makePacket(command: RingSessionManager.CMD_BATTERY)
            let data = Data(packet)
            peripheral.writeValue(data, for: uartRxCharacteristic, type: .withResponse)
            self.batteryStatusCallback = completion
        } catch {
            print("Failed to create battery packet: \(error)")
        }
    }
    
    private func handleBatteryResponse(packet: [UInt8]) {
        guard packet[0] == RingSessionManager.CMD_BATTERY else {
            print("Invalid battery packet received.")
            return
        }
        
        let batteryLevel = Int(packet[1])
        let charging = packet[2] != 0
        let batteryInfo = BatteryInfo(batteryLevel: batteryLevel, charging: charging)
        print(batteryInfo)
        recordEvent(.battery(level: batteryLevel, charging: charging))
        
        // Trigger stored callback with battery info
        batteryStatusCallback?(batteryInfo)
        batteryStatusCallback = nil
    }
}

// MARK: - Event Logging
extension RingSessionManager {
    fileprivate func recordEvent(_ event: TimelineEvent) {
        events.append(event)
    }
}
