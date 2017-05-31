//
//  RapidMutateProtocol.swift
//  Rapid
//
//  Created by Jan Schwarz on 16/03/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

import Foundation

protocol RapidExecution {
    var identifier: String { get }
    var fetchRequest: RapidFetchInstance { get }
}

protocol RapidExectuionDelegate: class {
    func sendFetchRequest(_ request: RapidFetchInstance)
    func sendMutationRequest<T: RapidMutationRequest>(_ request: T)
    func executionCompleted(_ execution: RapidExecution)
}

/// Protocol describing concurrency optimistic request
protocol RapidConcOptRequest {
    var etag: Any? { get set }
}

/// Protocol describing mutation request
protocol RapidMutationRequest: RapidTimeoutRequest, RapidSerializable, RapidConcOptRequest {
}
