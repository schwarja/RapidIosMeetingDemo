//
//  RapidSubscription.swift
//  Rapid
//
//  Created by Jan Schwarz on 17/03/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

import Foundation

protocol RapidSubscriptionHashable {
    var subscriptionHash: String { get }
}

/// Protocol describing subscription objects
protocol RapidSubscriptionInstance: class, RapidSerializable, RapidSubscriptionHashable, RapidSubscription {
    /// Hash identifying the subscription
    var subscriptionHash: String { get }
    
    /// Maximum number of documents in subscription
    var subscriptionTake: Int? { get }
    
    var subscriptionOrdering: [RapidOrdering.Ordering]? { get }
    
    /// Subscription dataset changed
    ///
    /// - Parameters:
    ///   - documents: All documents that meet subscription definition
    ///   - added: Documents that have been added since last call
    ///   - updated: Documents that have been modified since last call
    ///   - removed: Documents that have been removed since last call
    func receivedUpdate(_ documents: [RapidDocument], _ added: [RapidDocument], _ updated: [RapidDocument], _ removed: [RapidDocument])
    
    /// Subscription failed to be registered
    ///
    /// - Parameter error: Failure reason
    func subscriptionFailed(withError error: RapidError)
    
    /// Pass a block of code that should be called when the subscription should be unregistered
    ///
    /// - Parameter callback: Block of code that should be called when the subscription should be unregistered
    func registerUnsubscribeCallback(_ callback: @escaping (RapidSubscriptionInstance) -> Void)
}

protocol RapidFetchInstance: class, RapidSerializable, RapidTimeoutRequest, RapidSubscriptionHashable {
    var fetchID: String { get }
    
    func receivedData(_ documents: [RapidDocument])
    func fetchFailed(withError error: RapidError)
}

extension RapidFetchInstance {
    
    func eventAcknowledged(_ acknowledgement: RapidServerAcknowledgement) {}
    
    func eventFailed(withError error: RapidErrorInstance) {
        fetchFailed(withError: error.error)
    }

}
