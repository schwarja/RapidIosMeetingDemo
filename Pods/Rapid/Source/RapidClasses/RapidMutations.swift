//
//  RapidMutations.swift
//  Rapid
//
//  Created by Jan on 28/03/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

import Foundation

// MARK: Execution

/// Flow controller for a document execution
class RapidDocumentExecution: RapidExecution {
    
    /// Operation identifier
    let identifier = Generator.uniqueID
    
    /// Collection identifier
    let collectionID: String
    
    /// Document identifier
    let documentID: String
    
    /// Flow controller delegate
    weak var delegate: RapidExectuionDelegate?
    
    /// Cache handler
    weak var cacheHandler: RapidCacheHandler?
    
    /// Execution block that returns a client action based on current data
    let executionBlock: RapidExecutionBlock
    
    /// Completion callback
    let completion: RapidExecutionCompletion?
    
    /// Fetch document request
    var fetchRequest: RapidFetchInstance {
        let fetch = RapidDocumentFetch(collectionID: collectionID, documentID: documentID, cache: cacheHandler, callback: { [weak self] (error, document) in
            if let error = error {
                self?.completeExecution(withError: error)
            }
            else {
                self?.resolveValue(forDocument: document)
            }
        })
        
        return fetch
    }
    
    /// Initialize optimistic concurrency flow controller
    ///
    /// - Parameters:
    ///   - collectionID: Collection ID
    ///   - documentID: Document ID
    ///   - delegate: Flow controller delegate
    ///   - block: Execution block that returns a client action based on current data
    ///   - completion: Completion callback
    init(collectionID: String, documentID: String, delegate: RapidExectuionDelegate, block: @escaping RapidExecutionBlock, completion: RapidExecutionCompletion?) {
        self.collectionID = collectionID
        self.documentID = documentID
        self.executionBlock = block
        self.completion = completion
        self.delegate = delegate
    }
    
    /// Send fetch document request
    fileprivate func sendFetchRequest() {
        delegate?.sendFetchRequest(fetchRequest)
    }
    
    /// Pass current value to `RapidExecutionBlock` and perform an action based on a result
    ///
    /// - Parameter document: `RapidDocument` returned from fetch
    fileprivate func resolveValue(forDocument document: RapidDocument) {
        DispatchQueue.main.async { [weak self] in
            // Get developer action
            guard let result = self?.executionBlock(document.value) else {
                return
            }
            
            switch result {
            case .write(let value):
                self?.write(value: value, forDocument: document)
                
            case .delete:
                self?.delete(document: document)
                
            case .abort:
                self?.completeExecution(withError: RapidError.executionFailed(reason: .aborted))
            }
        }
    }
    
    /// Decide what to do after the server responds to a write trial
    ///
    /// - Parameter error: Optional resulting error
    fileprivate func resolveWriteResponse(withError error: Error?) {
        // If the error is a write-conflict error start over the whole flow
        // Otherwise, finish the optimistic concurrency flow
        if let error = error as? RapidError,
            case RapidError.executionFailed(let reason) = error,
            case RapidError.ExecutionError.writeConflict = reason {
            
            sendFetchRequest()
        }
        else {
            completeExecution(withError: error)
        }
    }
    
    /// Finish the optimistic concurrency flow
    ///
    /// - Parameter error: Optional resulting error
    fileprivate func completeExecution(withError error: Error?) {
        // Inform the delegate so that it can release the flow controller
        delegate?.executionCompleted(self)
        
        DispatchQueue.main.async {
            self.completion?(error)
        }
    }
    
    /// Process a write action returned from `RapidConcurrencyOptimisticBlock`
    ///
    /// - Parameters:
    ///   - value: Value to be written
    ///   - document: `RapidDocument` returned from fetch
    fileprivate func write(value: [AnyHashable: Any], forDocument document: RapidDocument) {
        let request = RapidDocumentMutation(collectionID: collectionID, documentID: documentID, value: value, cache: cacheHandler, completion: { [weak self] error in
            self?.resolveWriteResponse(withError: error)
        })
        request.etag = document.etag ?? Rapid.nilValue
        delegate?.sendMutationRequest(request)
    }
    
    /// Process a delete action returned from `RapidConcurrencyOptimisticBlock`
    ///
    /// - Parameter document: `RapidDocument` returned from fetch
    fileprivate func delete(document: RapidDocument) {
        let request = RapidDocumentDelete(collectionID: collectionID, documentID: documentID, cache: cacheHandler, completion: { [weak self] (error) in
            self?.resolveWriteResponse(withError: error)
        })
        request.etag = document.etag ?? Rapid.nilValue
        delegate?.sendMutationRequest(request)
    }
}

// MARK: Document mutation

/// Document mutation request
class RapidDocumentMutation: NSObject, RapidMutationRequest {
    
    /// Request should timeout only if `Rapid.timeout` is set
    let alwaysTimeout = false
    
    /// Document JSON
    let value: [AnyHashable: Any]
    
    /// Collection ID
    let collectionID: String
    
    /// Document ID
    let documentID: String
    
    /// Mutation completion
    let completion: RapidMutationCompletion?
    
    /// Timout delegate
    internal weak var timoutDelegate: RapidTimeoutRequestDelegate?
    
    internal var requestTimeoutTimer: Timer?
    
    /// Cache handler
    internal weak var cacheHandler: RapidCacheHandler?
    
    /// Etag for concurrency optimistic mutation
    var etag: Any?
    
    /// Initialize mutation request
    ///
    /// - Parameters:
    ///   - collectionID: Collection ID
    ///   - documentID: Document ID
    ///   - value: Document JSON
    ///   - completion: Mutation completion
    init(collectionID: String, documentID: String, value: [AnyHashable: Any], cache: RapidCacheHandler?, completion: RapidMutationCompletion?) {
        self.value = value
        self.collectionID = collectionID
        self.documentID = documentID
        self.completion = completion
        self.cacheHandler = cache
    }
    
}

extension RapidDocumentMutation: RapidSerializable {
    
    func serialize(withIdentifiers identifiers: [AnyHashable: Any]) throws -> String {
        return try RapidSerialization.serialize(mutation: self, withIdentifiers: identifiers)
    }
}

extension RapidDocumentMutation: RapidTimeoutRequest {
    
    func eventAcknowledged(_ acknowledgement: RapidServerAcknowledgement) {
        invalidateTimer()
        
        DispatchQueue.main.async {
            RapidLogger.log(message: "Rapid document \(self.documentID) in collection \(self.collectionID) mutated", level: .info)
            
            self.cacheHandler?.loadObject(withGroupID: self.collectionID, objectID: self.documentID, completion: { (object) in
                if let oldDoc = object as? RapidDocument,
                    let document = RapidDocument(document: oldDoc, newValue: self.value) {
                    
                    self.cacheHandler?.storeObject(document)
                }
            })
            
            self.completion?(nil)
        }
    }
    
    func eventFailed(withError error: RapidErrorInstance) {
        invalidateTimer()
        
        DispatchQueue.main.async {
            RapidLogger.log(message: "Rapid mutation failed - document \(self.documentID) in collection \(self.collectionID)", level: .info)
            
            self.completion?(error.error)
        }
    }
}

// MARK: Document merge

/// Document merge request
class RapidDocumentMerge: NSObject, RapidMutationRequest {
    
    /// Request should timeout only if `Rapid.timeout` is set
    let alwaysTimeout = false

    /// JSON with values to be merged
    let value: [AnyHashable: Any]
    
    /// Collection ID
    let collectionID: String
    
    /// Document ID
    let documentID: String
    
    /// Merge completion
    let completion: RapidMergeCompletion?
    
    /// Timeout delegate
    internal weak var timoutDelegate: RapidTimeoutRequestDelegate?
    
    internal var requestTimeoutTimer: Timer?
    
    /// Cache handler
    internal weak var cacheHandler: RapidCacheHandler?
    
    /// Etag for concurrency optimistic mutation
    var etag: Any?
    
    /// Initialize merge request
    ///
    /// - Parameters:
    ///   - collectionID: Collection ID
    ///   - documentID: Document ID
    ///   - value: JSON with values to be merged
    ///   - completion: Merge completion
    init(collectionID: String, documentID: String, value: [AnyHashable: Any], cache: RapidCacheHandler?, completion: RapidMergeCompletion?) {
        self.value = value
        self.collectionID = collectionID
        self.documentID = documentID
        self.completion = completion
        self.cacheHandler = cache
    }
    
}

extension RapidDocumentMerge: RapidSerializable {
    
    func serialize(withIdentifiers identifiers: [AnyHashable: Any]) throws -> String {
        return try RapidSerialization.serialize(merge: self, withIdentifiers: identifiers)
    }
}

extension RapidDocumentMerge: RapidTimeoutRequest {
    
    func eventAcknowledged(_ acknowledgement: RapidServerAcknowledgement) {
        invalidateTimer()
        
        DispatchQueue.main.async {
            RapidLogger.log(message: "Rapid document \(self.documentID) in collection \(self.collectionID) merged", level: .info)
            
            self.cacheHandler?.loadObject(withGroupID: self.collectionID, objectID: self.documentID, completion: { (object) in
                if let oldDoc = object as? RapidDocument, var value = oldDoc.value {
                    value.merge(with: self.value)
                    if let document = RapidDocument(document: oldDoc, newValue: value) {
                        self.cacheHandler?.storeObject(document)
                    }
                }
            })
            self.completion?(nil)
        }
    }
    
    func eventFailed(withError error: RapidErrorInstance) {
        invalidateTimer()
        
        DispatchQueue.main.async {
            RapidLogger.log(message: "Rapid merge failed - document \(self.documentID) in collection \(self.collectionID)", level: .info)
            
            self.completion?(error.error)
        }
    }
}

// MARK: Document delete

/// Document merge request
class RapidDocumentDelete: NSObject, RapidMutationRequest {
    
    /// Request should timeout only if `Rapid.timeout` is set
    let alwaysTimeout = false
    
    /// Collection ID
    let collectionID: String
    
    /// Document ID
    let documentID: String
    
    /// Deletion completion
    let completion: RapidDeletionCompletion?
    
    /// Timeout delegate
    internal weak var timoutDelegate: RapidTimeoutRequestDelegate?
    
    internal var requestTimeoutTimer: Timer?
    
    /// Cache handler
    internal weak var cacheHandler: RapidCacheHandler?
    
    /// Etag for concurrency optimistic mutation
    var etag: Any?
    
    /// Initialize merge request
    ///
    /// - Parameters:
    ///   - collectionID: Collection ID
    ///   - documentID: Document ID
    ///   - callback: Delete callback
    init(collectionID: String, documentID: String, cache: RapidCacheHandler?, completion: RapidDeletionCompletion?) {
        self.collectionID = collectionID
        self.documentID = documentID
        self.completion = completion
        self.cacheHandler = cache
    }
    
}

extension RapidDocumentDelete: RapidSerializable {
    
    func serialize(withIdentifiers identifiers: [AnyHashable: Any]) throws -> String {
        return try RapidSerialization.serialize(delete: self, withIdentifiers: identifiers)
    }
}

extension RapidDocumentDelete: RapidTimeoutRequest {
    
    func eventAcknowledged(_ acknowledgement: RapidServerAcknowledgement) {
        invalidateTimer()
        
        DispatchQueue.main.async {
            RapidLogger.log(message: "Rapid document \(self.documentID) in collection \(self.collectionID) deleted", level: .info)
            
            self.cacheHandler?.removeObject(withGroupID: self.collectionID, objectID: self.documentID)
            
            self.completion?(nil)
        }
    }
    
    func eventFailed(withError error: RapidErrorInstance) {
        invalidateTimer()
        
        DispatchQueue.main.async {
            RapidLogger.log(message: "Rapid delete failed - document \(self.documentID) in collection \(self.collectionID)", level: .info)
            
            self.completion?(error.error)
        }
    }
}
