//
//  RapidDocument.swift
//  Rapid
//
//  Created by Jan Schwarz on 16/03/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

import Foundation

/// Document subscription callback which provides a client either with an error or with a document
public typealias RapidDocSubCallback = (_ error: Error?, _ value: RapidDocument) -> Void

/// Document fetch callback which provides a client either with an error or with a document
public typealias RapidDocFetchCallback = RapidDocSubCallback

/// Document mutation completion callback which informs a client about the operation result
public typealias RapidMutationCompletion = (_ error: Error?) -> Void

/// Document deletion completion callback which informs a client about the operation result
public typealias RapidDeletionCompletion = RapidMutationCompletion

/// Document mutation callback which informs a client about the operation result
public typealias RapidMergeCompletion = RapidMutationCompletion

/// Block of code which is called on optimistic concurrency write
public typealias RapidExecutionBlock = (_ currentValue: [AnyHashable: Any]?) -> RapidExecutionResult

/// Execution completion callback which informs a client about the operation result
public typealias RapidExecutionCompletion = RapidMutationCompletion

/// Return type for `RapidExecutionBlock`
///
/// `RapidExecutionResult` represents an action that should be performed based on a current value
/// that is provided as an input parameter of `RapidExecutionBlock`
///
/// - write: Write new data
/// - delete: Delete a document
/// - abort: Abort process
public enum RapidExecutionResult {
    case write(value: [AnyHashable: Any])
    case delete
    case abort
}

/// Class representing Rapid.io document
public class RapidDocumentRef: NSObject {
    
    fileprivate weak var handler: RapidHandler?
    fileprivate var socketManager: RapidSocketManager {
        return try! getSocketManager()
    }
    
    /// ID of a collection to which the document belongs
    public let collectionID: String
    
    /// Document ID
    public let documentID: String
    
    init(id: String, inCollection collectionID: String, handler: RapidHandler!) {
        self.documentID = id
        self.collectionID = collectionID
        self.handler = handler
    }
    
    /// Mutate the document
    ///
    /// All values in the document are deleted and replaced by values in the provided dictionary
    ///
    /// - Parameters:
    ///   - value: Dictionary with new values that the document should contain
    ///   - completion: Mutation completion callback which provides a client with an error if any error occurs
    public func mutate(value: [AnyHashable: Any], completion: RapidMutationCompletion? = nil) {
        let mutation = RapidDocumentMutation(collectionID: collectionID, documentID: documentID, value: value, cache: handler, completion: completion)
        socketManager.mutate(mutationRequest: mutation)
    }
    
    /// Mutate the document with regard to a current document content
    /// Provided etag is compared to an etag of the document stored in a database
    /// When provided etag is `nil` it means that the document shouldn't be stored in a database yet
    /// If provided etag equals to an etag stored in database all values in the document are deleted and replaced by values in the provided dictionary
    /// If provided etag differs from an etag stored in a database the mutation fails with `RapidError.executionFailed`
    ///
    /// - Parameters:
    ///   - value: Dictionary with new values that the document should contain
    ///   - etag: `RapidDocument` etag
    ///   - completion: Mutation completion callback which provides a client with an error if any error occurs
    public func mutate(value: [AnyHashable: Any], etag: String?, completion: RapidMutationCompletion? = nil) {
        let mutation = RapidDocumentMutation(collectionID: collectionID, documentID: documentID, value: value, cache: handler, completion: completion)
        mutation.etag = etag ?? Rapid.nilValue
        socketManager.mutate(mutationRequest: mutation)
    }
    
    /// Update the document with regard to a current document content
    ///
    /// Block of code that receives current document content and returns `RapidExecutionResult` based on the received value
    ///
    /// If block returns `RapidExecutionResult.abort` the execution is aborted and the completion callback receives `RapidError.executionFailed(RapidError.ExecutionError.aborted)`
    ///
    /// If block returns `RapidExecutionResult.delete` it means that the document should be deleted, but only if it wasn't updated in a database in the meanwhile
    /// If the document was updated in the meanwhile the block is called again with a new document content
    ///
    /// If block returns `RapidExecutionResult.write(value)` it means that the document should be mutated with `value`, but only if it wasn't updated in a database in the meanwhile
    /// If the document was updated in the meanwhile the block is called again with a new document content
    ///
    /// - Parameters:
    ///   - block: Block of code that receives current document content updates it and decides what to do next
    ///   - completion: Execuction completion callback which provides a client with an error if any error occurs
    public func execute(block: @escaping RapidExecutionBlock, completion: RapidExecutionCompletion? = nil) {
        let concurrencyMutation = RapidDocumentExecution(collectionID: collectionID, documentID: documentID, delegate: socketManager, block: block, completion: completion)
        concurrencyMutation.cacheHandler = handler
        socketManager.execute(execution: concurrencyMutation)
    }
    
    /// Merge values in the document content with values in the provided dictionary
    ///
    /// Values that are not mentioned in the provided dictionary remains as they are.
    /// Values that are mentioned in the provided dictionary are either replaced or added to the document.
    /// Values that contains `Rapid.nilValue` are deleted from the document
    ///
    /// - Parameters:
    ///   - value: Dictionary with new values that should be merged with the document content
    ///   - completion: Merge completion callback which provides a client with an error if any error occurs
    public func merge(value: [AnyHashable: Any], completion: RapidMergeCompletion? = nil) {
        let merge = RapidDocumentMerge(collectionID: collectionID, documentID: documentID, value: value, cache: handler, completion: completion)
        socketManager.mutate(mutationRequest: merge)
    }
    
    /// Merge values in the document content with values in the provided dictionary
    /// Provided etag is compared to an etag of the document stored in a database
    /// When provided etag is `nil` it means that the document shouldn't be stored in a database yet
    /// If provided etag equals to an etag stored in a database the merge takes place
    /// If provided etag differs from an etag stored in a database the merge fails with `RapidError.executionFailed`
    ///
    /// Values that are not mentioned in the provided dictionary remains as they are.
    /// Values that are mentioned in the provided dictionary are either replaced or added to the document.
    /// Values that contains `Rapid.nilValue` are deleted from the document
    ///
    /// - Parameters:
    ///   - value: Dictionary with new values that should be merged with the document content
    ///   - etag: `RapidDocument` etag
    ///   - completion: Merge completion callback which provides a client with an error if any error occurs
    public func merge(value: [AnyHashable: Any], etag: String?, completion: RapidMergeCompletion? = nil) {
        let merge = RapidDocumentMerge(collectionID: collectionID, documentID: documentID, value: value, cache: handler, completion: completion)
        merge.etag = etag ?? Rapid.nilValue
        socketManager.mutate(mutationRequest: merge)
    }
    
    /// Delete the document
    ///
    /// - Parameter completion: Deletion completion callback which provides a client with an error if any error occurs
    public func delete(completion: RapidDeletionCompletion? = nil) {
        let deletion = RapidDocumentDelete(collectionID: collectionID, documentID: documentID, cache: handler, completion: completion)
        socketManager.mutate(mutationRequest: deletion)
    }
    
    /// Delete the document
    /// Provided etag is compared to an etag of the document stored in a database
    /// If provided etag equals to an etag stored in a database the merge takes place
    /// If provided etag differs from an etag stored in a database the merge fails with `RapidError.executionFailed`
    ///
    /// - Parameters:
    ///   - etag: `RapidDocument` etag
    ///   - completion: Deletion completion callback which provides a client with an error if any error occurs
    public func delete(etag: String, completion: RapidDeletionCompletion? = nil) {
        let deletion = RapidDocumentDelete(collectionID: collectionID, documentID: documentID, cache: handler, completion: completion)
        deletion.etag = etag
        socketManager.mutate(mutationRequest: deletion)
    }
    
    /// Subscribe for listening to the document changes
    ///
    /// - Parameter completion: subscription callback which provides a client either with an error or with a document
    /// - Returns: Subscription object which can be used for unsubscribing
    @discardableResult
    public func subscribe(completion: @escaping RapidDocSubCallback) -> RapidSubscription {
        let subscription = RapidDocumentSub(collectionID: collectionID, documentID: documentID, callback: completion)
        
        socketManager.subscribe(subscription)
        
        return subscription
    }
    
    /// Fetch document
    ///
    /// - Parameter completion: Fetch callback which provides a client either with an error or with an array of documents
    public func readOnce(completion: @escaping RapidDocFetchCallback) {
        let fetch = RapidDocumentFetch(collectionID: collectionID, documentID: documentID, cache: handler, callback: completion)
        
        socketManager.fetch(fetch)
    }
    
}

extension RapidDocumentRef {
    
    func getSocketManager() throws -> RapidSocketManager {
        if let manager = handler?.socketManager {
            return manager
        }

        RapidLogger.log(message: RapidInternalError.rapidInstanceNotInitialized.message, level: .critical)
        throw RapidInternalError.rapidInstanceNotInitialized
    }
}
