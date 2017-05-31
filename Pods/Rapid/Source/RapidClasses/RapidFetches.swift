//
//  RapidReads.swift
//  Rapid
//
//  Created by Jan Schwarz on 17/05/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

import Foundation

/// Collection fetch object
class RapidCollectionFetch: NSObject {
    
    /// Collection ID
    let collectionID: String
    
    /// Fetch filter
    let filter: RapidFilter?
    
    /// Fetch ordering
    let ordering: [RapidOrdering]?
    
    /// Fetch paging
    let paging: RapidPaging?
    
    /// Completion callback
    let callback: RapidColFetchCallback?
    
    /// Cache handler
    internal weak var cacheHandler: RapidCacheHandler?
    
    /// Request should timeout only if `Rapid.timeout` is set
    let alwaysTimeout = false
    
    /// Timout delegate
    internal weak var timoutDelegate: RapidTimeoutRequestDelegate?
    internal var requestTimeoutTimer: Timer?
    
    /// Fetch identifier
    let fetchID = Generator.uniqueID
    
    /// Initialize collection fetch object
    ///
    /// - Parameters:
    ///   - collectionID: Collection ID
    ///   - filter: Subscription filter
    ///   - ordering: Subscription ordering
    ///   - paging: Subscription paging
    ///   - Cache handler
    ///   - callback: Completion callback
    init(collectionID: String, filter: RapidFilter?, ordering: [RapidOrdering]?, paging: RapidPaging?, cache: RapidCacheHandler?, callback: RapidColFetchCallback?) {
        self.collectionID = collectionID
        self.filter = filter
        self.ordering = ordering
        self.paging = paging
        self.callback = callback
        self.cacheHandler = cache
    }
    
}

extension RapidCollectionFetch: RapidSerializable {
    
    func serialize(withIdentifiers identifiers: [AnyHashable : Any]) throws -> String {
        var dict = identifiers
        dict[RapidSerialization.Fetch.FetchID.name] = fetchID
        return try RapidSerialization.serialize(fetch: self, withIdentifiers: dict)
    }
}

extension RapidCollectionFetch: RapidFetchInstance {
    
    /// Subscription identifier
    var subscriptionHash: String {
        return "\(collectionID)#\(filter?.subscriptionHash ?? "")#\(ordering?.map({ $0.subscriptionHash }).joined(separator: "|") ?? "")#\(paging?.subscriptionHash ?? "")"
    }

    func receivedData(_ documents: [RapidDocument]) {
        invalidateTimer()
        
        DispatchQueue.main.async {
            RapidLogger.log(message: "Rapid fetched collection \(self.collectionID)", level: .info)
            
            self.cacheHandler?.storeDataset(documents, forSubscription: self)
            
            self.callback?(nil, documents)
        }
    }
    
    func fetchFailed(withError error: RapidError) {
        invalidateTimer()
        
        DispatchQueue.main.async {
            RapidLogger.log(message: "Rapid fetch collection \(self.collectionID) failed", level: .info)
            
            self.callback?(error, [])
        }
    }
}

// MARK: Document fetch

/// Document fetch object
class RapidDocumentFetch: NSObject {
    
    /// Document identifier
    let documentID: String
    
    /// Collection identifier
    var collectionID: String {
        return collectionFetch.collectionID
    }
    
    /// Collection fetch
    let collectionFetch: RapidCollectionFetch
    
    /// Default subscription callback
    let callback: RapidDocFetchCallback?
    
    /// Cache handler
    internal weak var cacheHandler: RapidCacheHandler?
    
    /// Request should timeout only if `Rapid.timeout` is set
    let alwaysTimeout = false
    
    /// Timout delegate
    internal weak var timoutDelegate: RapidTimeoutRequestDelegate?
    internal var requestTimeoutTimer: Timer?
    
    /// Fetch identifier
    var fetchID: String {
        return collectionFetch.fetchID
    }
    
    /// Initialize document fetch object
    ///
    /// - Parameters:
    ///   - collectionID: Collection ID
    ///   - documentID: Document ID
    ///   - cache: Cache handler
    ///   - callback: Completion callback
    init(collectionID: String, documentID: String, cache: RapidCacheHandler?, callback: RapidDocFetchCallback?) {
        let filter = RapidFilterSimple(keyPath: RapidFilter.docIdKey, relation: .equal, value: documentID)
        self.collectionFetch = RapidCollectionFetch(collectionID: collectionID, filter: filter, ordering: nil, paging: nil, cache: nil, callback: nil)
        
        self.documentID = documentID
        self.callback = callback
        self.cacheHandler = cache
    }

}

extension RapidDocumentFetch: RapidSerializable {
    
    func serialize(withIdentifiers identifiers: [AnyHashable : Any]) throws -> String {
        return try collectionFetch.serialize(withIdentifiers: identifiers)
    }
}

extension RapidDocumentFetch: RapidFetchInstance {
    
    /// Subscription identifier
    var subscriptionHash: String {
        return collectionFetch.subscriptionHash
    }
    
    func receivedData(_ documents: [RapidDocument]) {
        invalidateTimer()
        
        DispatchQueue.main.async {
            RapidLogger.log(message: "Rapid fetched document \(self.documentID) in collection \(self.collectionID)", level: .info)
            
            self.cacheHandler?.storeDataset(documents, forSubscription: self)
            
            let document = documents.first ?? RapidDocument(removedDocId: self.documentID, collectionID: self.collectionID)
            self.callback?(nil, document)
        }
    }
    
    func fetchFailed(withError error: RapidError) {
        invalidateTimer()
        
        DispatchQueue.main.async {
            RapidLogger.log(message: "Rapid document fetch failed - document \(self.documentID) collection \(self.collectionID)", level: .info)
            
            self.callback?(error, RapidDocument(removedDocId: self.documentID, collectionID: self.collectionID))
        }
    }
}
