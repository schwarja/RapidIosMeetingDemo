//
//  RapidSubscription.swift
//  Rapid
//
//  Created by Jan on 28/03/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

import Foundation

// MARK: Collection subscription

/// Collection subscription object
class RapidCollectionSub: NSObject {
    
    /// Collection ID
    let collectionID: String
    
    /// Subscription filter
    let filter: RapidFilter?
    
    /// Subscription ordering
    let ordering: [RapidOrdering]?
    
    /// Subscription paging
    let paging: RapidPaging?
    
    /// Default subscription callback
    let callback: RapidColSubCallback?
    
    /// Subscription callback with lists of changes
    let callbackWithChanges: RapidColSubCallbackWithChanges?
    
    /// Block of code to be called when unsubscribing
    fileprivate var unsubscribeCallback: ((RapidSubscriptionInstance) -> Void)?
    
    /// Initialize collection subscription object
    ///
    /// - Parameters:
    ///   - collectionID: Collection ID
    ///   - filter: Subscription filter
    ///   - ordering: Subscription ordering
    ///   - paging: Subscription paging
    ///   - callback: Default subscription callback
    ///   - callbackWithChanges: Subscription callback with lists of changes
    init(collectionID: String, filter: RapidFilter?, ordering: [RapidOrdering]?, paging: RapidPaging?, callback: RapidColSubCallback?, callbackWithChanges: RapidColSubCallbackWithChanges?) {
        self.collectionID = collectionID
        self.filter = filter
        self.ordering = ordering
        self.paging = paging
        self.callback = callback
        self.callbackWithChanges = callbackWithChanges
    }
    
}

extension RapidCollectionSub: RapidSerializable {
    
    func serialize(withIdentifiers identifiers: [AnyHashable : Any]) throws -> String {
        return try RapidSerialization.serialize(subscription: self, withIdentifiers: identifiers)
    }

}

extension RapidCollectionSub: RapidSubscriptionInstance {
    
    /// Subscription identifier
    var subscriptionHash: String {
        return "\(collectionID)#\(filter?.subscriptionHash ?? "")#\(ordering?.map({ $0.subscriptionHash }).joined(separator: "|") ?? "")#\(paging?.subscriptionHash ?? "")"
    }
    
    var subscriptionTake: Int? {
        return paging?.take
    }
    
    var subscriptionOrdering: [RapidOrdering.Ordering]? {
        return ordering?.map({ $0.ordering })
    }
    
    func subscriptionFailed(withError error: RapidError) {
        // Pass error to callbacks
        DispatchQueue.main.async {
            self.callback?(error, [])
            self.callbackWithChanges?(error, [], [], [], [])
        }
    }
    
    /// Assign a block of code that should be called on unsubscribing to `unsubscribeCallback`
    ///
    /// - Parameter callback: Block of code that should be called on unsubscribing
    func registerUnsubscribeCallback(_ callback: @escaping (RapidSubscriptionInstance) -> Void) {
        unsubscribeCallback = callback
    }
    
    func receivedUpdate(_ documents: [RapidDocument], _ added: [RapidDocument], _ updated: [RapidDocument], _ removed: [RapidDocument]) {
        // Pass changes to callbacks
        DispatchQueue.main.async {
            self.callback?(nil, documents)
            self.callbackWithChanges?(nil, documents, added, updated, removed)
        }
    }
    
}

extension RapidCollectionSub: RapidSubscription {
    
    /// Unregister subscription
    func unsubscribe() {
        unsubscribeCallback?(self)
    }
    
}

// MARK: Document subscription

/// Document subscription object
///
/// The class is a wrapper for `RapidCollectionSub`. Internally, it creates collection subscription filtered by `RapidFilterSimple.documentIdKey` = `documentID`
class RapidDocumentSub: NSObject {
    
    /// Collection ID
    let collectionID: String
    
    /// Document ID
    let documentID: String
    
    /// Subscription callback
    let callback: RapidDocSubCallback?
    
    /// Underlying collection subscription object
    fileprivate(set) var subscription: RapidCollectionSub!
    
    /// Block of code to be called when unsubscribing
    fileprivate var unsubscribeCallback: ((RapidSubscriptionInstance) -> Void)?
    
    /// Initialize document subscription object
    ///
    /// - Parameters:
    ///   - collectionID: Collection ID
    ///   - documentID: Document ID
    ///   - callback: Subscription callback
    init(collectionID: String, documentID: String, callback: RapidDocSubCallback?) {
        self.collectionID = collectionID
        self.documentID = documentID
        self.callback = callback
        
        super.init()
        
        self.subscription = RapidCollectionSub(collectionID: collectionID, filter: RapidFilterSimple(keyPath: RapidFilterSimple.docIdKey, relation: .equal, value: documentID), ordering: nil, paging: nil, callback: nil, callbackWithChanges: nil)
    }
}

extension RapidDocumentSub: RapidSerializable {

    func serialize(withIdentifiers identifiers: [AnyHashable : Any]) throws -> String {
        return try subscription.serialize(withIdentifiers: identifiers)
    }
    
}

extension RapidDocumentSub: RapidSubscriptionInstance {
    
    var subscriptionHash: String {
        return subscription.subscriptionHash
    }
    
    var subscriptionTake: Int? {
        return 1
    }
    
    var subscriptionOrdering: [RapidOrdering.Ordering]? {
        return nil
    }
    
    func subscriptionFailed(withError error: RapidError) {
        // Pass error to callback
        DispatchQueue.main.async {
            self.callback?(error, RapidDocument(removedDocId: self.documentID, collectionID: self.collectionID))
        }
    }
    
    func registerUnsubscribeCallback(_ callback: @escaping (RapidSubscriptionInstance) -> Void) {
        unsubscribeCallback = callback
    }
    
    func receivedUpdate(_ documents: [RapidDocument], _ added: [RapidDocument], _ updated: [RapidDocument], _ removed: [RapidDocument]) {
        // Pass changes to callback
        DispatchQueue.main.async {
            self.callback?(nil, documents.last ?? RapidDocument(removedDocId: self.documentID, collectionID: self.collectionID))
        }
    }
    
}

extension RapidDocumentSub: RapidSubscription {
    
    func unsubscribe() {
        unsubscribeCallback?(self)
    }
}
