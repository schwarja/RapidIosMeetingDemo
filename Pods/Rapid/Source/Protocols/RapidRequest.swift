//
//  RapidRequest.swift
//  Rapid
//
//  Created by Jan Schwarz on 17/03/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

import Foundation

/// Protocol ensuring serialization to JSON string
protocol RapidSerializable {
    func serialize(withIdentifiers identifiers: [AnyHashable: Any]) throws -> String
}

/// Protocol describing events that can be sent to the server
protocol RapidClientMessage {}

/// Protocol describing socket events that wait for a server response
protocol RapidClientRequest: class, RapidClientMessage {
    func eventAcknowledged(_ acknowledgement: RapidServerAcknowledgement)
    func eventFailed(withError error: RapidErrorInstance)
}

/// Protocol describing socket events that inform server and do not wait for a server response
protocol RapidClientEvent: RapidClientMessage {}

/// `RapidRequest` that implements timeout
protocol RapidTimeoutRequest: RapidClientRequest {
    /// Request should timeout even if `Rapid.timeout` is `nil`
    var alwaysTimeout: Bool { get }
    
    /// Timout delegate
    weak var timoutDelegate: RapidTimeoutRequestDelegate? { get set }
    
    /// Timer for triggering timeout
    var requestTimeoutTimer: Timer? { get set }
}

extension RapidTimeoutRequest {
    
    /// Request was enqued an timeout countdown should begin
    ///
    /// - Parameters:
    ///   - timeout: Number of seconds before timeout occurs
    ///   - delegate: Timeout delegate
    func requestSent(withTimeout timeout: TimeInterval, delegate: RapidTimeoutRequestDelegate) {
        // Start timeout
        self.timoutDelegate = delegate
        
        DispatchQueue.main.async { [weak self] in
            self?.requestTimeoutTimer = Timer.scheduledTimer(timeInterval: timeout, userInfo: nil, repeats: false, block: { [weak self] (_) in
                self?.requestTimeout()
            })
        }
    }
    
    func requestTimeout() {
        requestTimeoutTimer = nil
        
        timoutDelegate?.requestTimeout(self)
    }
    
    /// Stop countdown because request is no more valid
    func invalidateTimer() {
        DispatchQueue.main.async {
            self.requestTimeoutTimer?.invalidate()
            self.requestTimeoutTimer = nil
        }
    }
    
}

/// Delegate for informing about timout
protocol RapidTimeoutRequestDelegate: class {
    func requestTimeout(_ request: RapidTimeoutRequest)
}

enum RapidRequestPriority: Int {
    case high
    case medium
    case low
}

protocol RapidPriorityRequest {
    var priority: RapidRequestPriority { get }
}
