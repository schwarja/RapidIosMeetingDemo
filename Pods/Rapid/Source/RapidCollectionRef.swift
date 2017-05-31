//
//  Collection.swift
//  Rapid
//
//  Created by Jan Schwarz on 16/03/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

import Foundation

/// Collection subscription callback which provides a client either with an error or with an array of documents
public typealias RapidColSubCallback = (_ error: Error?, _ value: [RapidDocument]) -> Void

/// Collection subscription callback which provides a client either with an error or with an array of all documents plus with arrays of new, updated and removed documents
public typealias RapidColSubCallbackWithChanges = (_ error: Error?, _ value: [RapidDocument], _ added: [RapidDocument], _ updated: [RapidDocument], _ removed: [RapidDocument]) -> Void

/// Collection read callback which provides a client either with an error or with an array of documents
public typealias RapidColFetchCallback = RapidColSubCallback

/// Class representing Rapid.io collection
public class RapidCollectionRef: NSObject {
    
    fileprivate weak var handler: RapidHandler?
    
    fileprivate var socketManager: RapidSocketManager {
        return try! getSocketManager()
    }
    
    /// Collection identifier
    public let collectionID: String
    
    /// Filters assigned to the collection instance
    public fileprivate(set) var subscriptionFilter: RapidFilter?
    
    /// Order descriptors assigned to the collection instance
    public fileprivate(set) var subscriptionOrdering: [RapidOrdering]?
    
    /// Pagination information assigned to the collection instance
    public fileprivate(set) var subscriptionPaging: RapidPaging?

    init(id: String, handler: RapidHandler!, filter: RapidFilter? = nil, ordering: [RapidOrdering]? = nil, paging: RapidPaging? = nil) {
        self.collectionID = id
        self.handler = handler
        self.subscriptionFilter = filter
        self.subscriptionOrdering = ordering
        self.subscriptionPaging = paging
    }
    
    /// Create an instance of a Rapid document in the collection with a new unique ID
    ///
    /// - Returns: Instance of `RapidDocument` in the collection with a new unique ID
    public func newDocument() -> RapidDocumentRef {
        return document(withID: Rapid.uniqueID)
    }
    
    /// Get an instance of a Rapid document in the collection with a specified ID
    ///
    /// - Parameter id: Document ID
    /// - Returns: Instance of a `RapidDocument` in the collection with a specified ID
    public func document(withID id: String) -> RapidDocumentRef {
        return try! document(id: id)
    }
    
    /// Get a new collection object with a subscription filtering option assigned
    ///
    /// When the collection already contains a filter the new filter is combined with the original one with logical AND
    ///
    /// - Parameter filter: Filter object
    /// - Returns: The collection with the filter assigned
    public func filter(by filter: RapidFilter) -> RapidCollectionRef {
        let collection = RapidCollectionRef(id: collectionID, handler: handler, filter: subscriptionFilter, ordering: subscriptionOrdering, paging: subscriptionPaging)
        collection.filtered(by: filter)
        return collection
    }
    
    /// Assign a subscription filtering option to the collection
    ///
    /// When the collection already contains a filter the new filter is combined with the original one with logical AND
    ///
    /// - Parameter filter: Filter object
    public func filtered(by filter: RapidFilter) {
        if let previousFilter = self.subscriptionFilter {
            let compoundFilter = RapidFilterCompound(compoundOperator: .and, operands: [previousFilter, filter])
            self.subscriptionFilter = compoundFilter
        }
        else {
            self.subscriptionFilter = filter
        }
    }
    
    /// Get a new collection object with a subscription ordering assigned
    ///
    /// An ordering with the array index 0 has the highest priority.
    /// When the collection already contains an ordering the new ordering is appended to the original one
    ///
    /// - Parameter ordering: Ordering object
    /// - Returns: The collection with the ordering assigned
    public func order(by ordering: RapidOrdering) -> RapidCollectionRef {
        let collection = RapidCollectionRef(id: collectionID, handler: handler, filter: subscriptionFilter, ordering: subscriptionOrdering, paging: subscriptionPaging)
        collection.ordered(by: ordering)
        return collection
    }
    
    /// Assign subscription ordering to the collection
    ///
    /// An ordering with the array index 0 has the highest priority.
    /// When the collection already contains an ordering the new ordering is appended to the original one
    ///
    /// - Parameter ordering: Ordering object
    public func ordered(by ordering: RapidOrdering) {
        if self.subscriptionOrdering == nil {
            self.subscriptionOrdering = []
        }
        //FIXME: Append ordering when multiple descriptors are done
        self.subscriptionOrdering = [ordering]
    }

    //TODO: Ordering with multiple descriptors
    
    /// Get a new collection object with a subscription ordering options assigned
    ///
    /// When the collection already contains an ordering the new ordering is appended to the original one
    ///
    /// - Parameter ordering: Array of ordering objects
    /// - Returns: The collection with the ordering array assigned
    func order(by ordering: [RapidOrdering]) -> RapidCollectionRef {
        let collection = RapidCollectionRef(id: collectionID, handler: handler, filter: subscriptionFilter, ordering: subscriptionOrdering, paging: subscriptionPaging)
        collection.ordered(by: ordering)
        return collection
    }
    
    /// Assign subscription ordering options to the collection
    ///
    /// When the collection already contains an ordering the new ordering is appended to the original one
    ///
    /// - Parameter ordering: Array of ordering objects
    func ordered(by ordering: [RapidOrdering]) {
        if self.subscriptionOrdering == nil {
            self.subscriptionOrdering = []
        }
        self.subscriptionOrdering?.append(contentsOf: ordering)
    }
    
    /// Get a new collection object with a subscription limit options assigned
    ///
    /// When the collection already contains a limit the original limit is replaced by the new one
    ///
    /// - Parameters:
    ///   - take: Maximum number of documents to be returned
    ///   - skip: Number of documents to be skipped
    /// - Returns: The collection with the limit assigned
    public func limit(to take: Int, skip: Int? = nil) -> RapidCollectionRef {
        let collection = RapidCollectionRef(id: collectionID, handler: handler, filter: subscriptionFilter, ordering: subscriptionOrdering, paging: subscriptionPaging)
        collection.limited(to: take, skip: skip)
        return collection
    }

    /// Assing a subscription limit options to the collection
    ///
    /// When the collection already contains a limit the original limit is replaced by the new one
    ///
    /// - Parameters:
    ///   - take: Maximum number of documents to be returned
    ///   - skip: Number of documents to be skipped
    public func limited(to take: Int, skip: Int? = nil) {
        self.subscriptionPaging = RapidPaging(skip: skip, take: take)
    }

    /// Subscribe for listening to the collection changes
    ///
    /// Only filters, orderings and limits that are assigned to the collection by the time of creating a subscription are applied
    ///
    /// - Parameter completion: Subscription callback which provides a client either with an error or with an array of documents
    /// - Returns: Subscription object which can be used for unsubscribing
    @discardableResult
    public func subscribe(completion: @escaping RapidColSubCallback) -> RapidSubscription {
        let subscription = RapidCollectionSub(collectionID: collectionID, filter: subscriptionFilter, ordering: subscriptionOrdering, paging: subscriptionPaging, callback: completion, callbackWithChanges: nil)
        
        socketManager.subscribe(subscription)
        
        return subscription
    }
    
    /// Subscribe for listening to the collection changes
    ///
    /// Only filters, orderings and limits that are assigned to the collection by the time of creating a subscription are applied
    ///
    /// - Parameter completion: Subscription callback which provides a client either with an error or with an array of all documents plus with arrays of new, updated and removed documents
    /// - Returns: Subscription object which can be used for unsubscribing
    @discardableResult
    public func subscribe(completionWithChanges completion: @escaping RapidColSubCallbackWithChanges) -> RapidSubscription {
        let subscription = RapidCollectionSub(collectionID: collectionID, filter: subscriptionFilter, ordering: subscriptionOrdering, paging: subscriptionPaging, callback: nil, callbackWithChanges: completion)
        
        socketManager.subscribe(subscription)
        
        return subscription
    }
    
    /// Fetch collection
    ///
    /// Only documents that match filters, orderings and limits that are assigned to the collection by the time of calling the function, are retured
    ///
    /// - Parameter completion: Fetch callback which provides a client either with an error or with an array of documents
    public func readOnce(completion: @escaping RapidColFetchCallback) {
        let fetch = RapidCollectionFetch(collectionID: collectionID, filter: subscriptionFilter, ordering: subscriptionOrdering, paging: subscriptionPaging, cache: handler, callback: completion)
        
        socketManager.fetch(fetch)
    }
}

extension RapidCollectionRef {
    
    func document(id: String) throws -> RapidDocumentRef {
        if let handler = handler {
            return RapidDocumentRef(id: id, inCollection: collectionID, handler: handler)
        }

        RapidLogger.log(message: RapidInternalError.rapidInstanceNotInitialized.message, level: .critical)
        throw RapidInternalError.rapidInstanceNotInitialized
    }
    
    func getSocketManager() throws -> RapidSocketManager {
        if let manager = handler?.socketManager {
            return manager
        }

        RapidLogger.log(message: RapidInternalError.rapidInstanceNotInitialized.message, level: .critical)
        throw RapidInternalError.rapidInstanceNotInitialized
    }

}
