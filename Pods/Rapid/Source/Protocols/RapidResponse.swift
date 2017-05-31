//
//  RapidResponse.swift
//  Rapid
//
//  Created by Jan Schwarz on 17/03/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

import Foundation

/// Protocol for events received from the server
protocol RapidServerMessage {}

protocol RapidServerResponse: RapidServerMessage {
    var eventID: String { get }
}

protocol RapidServerEvent: RapidServerMessage {
    var eventIDsToAcknowledge: [String] { get }
}
