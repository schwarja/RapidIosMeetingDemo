//
//  RapidSocketParser.swift
//  Rapid
//
//  Created by Jan Schwarz on 17/03/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

import Foundation

class RapidSerialization {
    
    /// Parse JSON received through websocket
    ///
    /// - Parameter json: Received JSON
    /// - Returns: Array of deserialized objects
    class func parse(json: [AnyHashable: Any]?) -> [RapidServerMessage]? {
        guard let json = json else {
            RapidLogger.developerLog(message: "Server event parsing failed - no data")
            
            return nil
        }
        
        // If websocket received a batch of events
        if let batch = json[Batch.name] as? [[AnyHashable: Any]] {
            var events = [RapidServerMessage]()
            var updates = [String: RapidSubscriptionBatch]()
            
            for json in batch {
                let event = parseEvent(json: json)
                
                // If the event is a subscription update treat it specially, otherwise just append it to the response array
                if let event = event as? RapidSubscriptionBatch {
                    
                    // If there was any update for the subscription combine it to one update
                    if let batch = updates[event.subscriptionID] {
                        batch.merge(event: event)
                    }
                    else {
                        updates[event.subscriptionID] = event
                        events.append(event)
                    }
                    
                }
                else if let event = event {
                    events.append(event)
                }
            }
            
            return events
        }
        else if let event = parseEvent(json: json) {
            return [event]
        }

        RapidLogger.developerLog(message: "Server event parsing failed - \(json)")

        return nil
    }
    
    /// Serialize a document mutation into JSON string
    ///
    /// - Parameters:
    ///   - mutation: Mutation object
    ///   - identifiers: Identifiers that are associated with the mutation event
    /// - Returns: JSON string
    /// - Throws: `JSONSerialization` and `RapidError.invalidData` errors
    class func serialize(mutation: RapidDocumentMutation, withIdentifiers identifiers: [AnyHashable: Any]) throws -> String {
        var json = identifiers
        
        var doc = [AnyHashable: Any]()
        doc[Mutation.Document.DocumentID.name] = try Validator.validate(identifier: mutation.documentID)
        doc[Mutation.Document.Etag.name] = mutation.etag
        doc[Mutation.Document.Body.name] = try Validator.validate(document: mutation.value)
        
        json[Mutation.CollectionID.name] = try Validator.validate(identifier: mutation.collectionID)
        
        json[Mutation.Document.name] = doc
        
        let resultDict: [AnyHashable: Any] = [Mutation.name: json]
        return try resultDict.jsonString()
    }
    
    /// Serialize a document merge into JSON string
    ///
    /// - Parameters:
    ///   - merge: Merge object
    ///   - identifiers: Identifiers that are associated with the merge event
    /// - Returns: JSON string
    /// - Throws: `JSONSerialization` and `RapidError.invalidData` errors
    class func serialize(merge: RapidDocumentMerge, withIdentifiers identifiers: [AnyHashable: Any]) throws -> String {
        var json = identifiers
        
        var doc = [AnyHashable: Any]()
        doc[Merge.Document.DocumentID.name] = try Validator.validate(identifier: merge.documentID)
        doc[Merge.Document.Etag.name] = merge.etag
        doc[Merge.Document.Body.name] = try Validator.validate(document: merge.value)
        
        json[Merge.CollectionID.name] = try Validator.validate(identifier: merge.collectionID)
        json[Merge.Document.name] = doc
        
        let resultDict: [AnyHashable: Any] = [Merge.name: json]
        return try resultDict.jsonString()
    }
    
    /// Serialize a document delete into JSON string
    ///
    /// - Parameters:
    ///   - delete: Delete object
    ///   - identifiers: Identifiers that are associated with the merge event
    /// - Returns: JSON string
    /// - Throws: `JSONSerialization` and `RapidError.invalidData` errors
    class func serialize(delete: RapidDocumentDelete, withIdentifiers identifiers: [AnyHashable: Any]) throws -> String {
        var json = identifiers
        
        var doc = [AnyHashable: Any]()
        doc[Delete.Document.DocumentID.name] = try Validator.validate(identifier: delete.documentID)
        doc[Delete.Document.Etag.name] = delete.etag
        
        json[Delete.CollectionID.name] = try Validator.validate(identifier: delete.collectionID)
        json[Delete.Document.name] = doc
        
        let resultDict: [AnyHashable: Any] = [Delete.name: json]
        return try resultDict.jsonString()
    }
    
    /// Serialize a collection fetch into JSON string
    ///
    /// - Parameters:
    ///   - subscription: Fetch object
    ///   - identifiers: Identifiers that are associated with the subscription event
    /// - Returns: JSON string
    /// - Throws: `JSONSerialization` and `RapidError.invalidData` errors
    class func serialize(fetch: RapidCollectionFetch, withIdentifiers identifiers: [AnyHashable: Any]) throws -> String {
        var json = identifiers
        
        if let paging = fetch.paging, paging.take > RapidPaging.takeLimit {
            throw RapidError.invalidData(reason: .invalidLimit)
        }
        
        json[Fetch.CollectionID.name] = try Validator.validate(identifier: fetch.collectionID)
        json[Fetch.Filter.name] = try serialize(filter: fetch.filter)
        json[Fetch.Ordering.name] = try serialize(ordering: fetch.ordering)
        json[Fetch.Limit.name] = fetch.paging?.take
        json[Fetch.Skip.name] = fetch.paging?.skip
        
        let resultDict: [AnyHashable: Any] = [Fetch.name: json]
        return try resultDict.jsonString()
    }
    
    /// Serialize a collection subscription into JSON string
    ///
    /// - Parameters:
    ///   - subscription: Subscription object
    ///   - identifiers: Identifiers that are associated with the subscription event
    /// - Returns: JSON string
    /// - Throws: `JSONSerialization` and `RapidError.invalidData` errors
    class func serialize(subscription: RapidCollectionSub, withIdentifiers identifiers: [AnyHashable: Any]) throws -> String {
        var json = identifiers
        
        if let paging = subscription.paging, paging.take > RapidPaging.takeLimit {
            throw RapidError.invalidData(reason: .invalidLimit)
        }
        
        json[Subscription.CollectionID.name] = try Validator.validate(identifier: subscription.collectionID)
        json[Subscription.Filter.name] = try serialize(filter: subscription.filter)
        json[Subscription.Ordering.name] = try serialize(ordering: subscription.ordering)
        json[Subscription.Limit.name] = subscription.paging?.take
        json[Subscription.Skip.name] = subscription.paging?.skip
        
        let resultDict: [AnyHashable: Any] = [Subscription.name: json]
        return try resultDict.jsonString()
    }
    
    /// Serialize a subscription filter into JSON
    ///
    /// - Parameter filter: Filter object
    /// - Returns: JSON dictionary
    class func serialize(filter: RapidFilter?) throws -> [AnyHashable: Any]? {
        if let filter = filter {
            switch filter {
            case let filter as RapidFilterSimple:
                return try serialize(simpleFilter: filter)
                
            case let filter as RapidFilterCompound:
                return try serialize(compoundFilter: filter)
                
            default:
                throw RapidError.invalidData(reason: .invalidFilter(filter: filter))
            }
        }
        else {
            return nil
        }
    }
    
    /// Serialize a simple subscription filter into JSON
    ///
    /// - Parameter simpleFilter: Simple filter object
    /// - Returns: JSON dictionary
    class func serialize(simpleFilter: RapidFilterSimple) throws -> [AnyHashable: Any] {
        guard Validator.isValid(keyPath: simpleFilter.keyPath) else {
            throw RapidError.invalidData(reason: .invalidKeyPath(keyPath: simpleFilter.keyPath))
        }
        
        if simpleFilter.keyPath == RapidFilter.docIdKey {
            if let value = simpleFilter.value as? String {
                try Validator.validate(identifier: value)
            }
            else {
                throw RapidError.invalidData(reason: .invalidIdentifierFormat(identifier: simpleFilter.value))
            }
        }
        
        switch simpleFilter.relation {
        case .equal:
            return [simpleFilter.keyPath: simpleFilter.value ?? NSNull()]
            
        case .greaterThanOrEqual where simpleFilter.value != nil:
            return [simpleFilter.keyPath: ["gte": simpleFilter.value]]
            
        case .lessThanOrEqual where simpleFilter.value != nil:
            return [simpleFilter.keyPath: ["lte": simpleFilter.value]]
            
        case .greaterThan where simpleFilter.value != nil:
            return [simpleFilter.keyPath: ["gt": simpleFilter.value]]
            
        case .lessThan where simpleFilter.value != nil:
            return [simpleFilter.keyPath: ["lt": simpleFilter.value]]
            
        case .contains where simpleFilter.value != nil && simpleFilter.value is String:
            return [simpleFilter.keyPath: ["cnt": simpleFilter.value]]
            
        case .startsWith where simpleFilter.value != nil && simpleFilter.value is String:
            return [simpleFilter.keyPath: ["pref": simpleFilter.value]]
            
        case .endsWith where simpleFilter.value != nil && simpleFilter.value is String:
            return [simpleFilter.keyPath: ["suf": simpleFilter.value]]
            
        case .arrayContains where simpleFilter.value != nil:
            return [simpleFilter.keyPath: ["arr-cnt": simpleFilter.value]]
            
        default:
            throw RapidError.invalidData(reason: .invalidFilter(filter: simpleFilter))
        }
    }
    
    /// Serialize a compound subscription filter into JSON
    ///
    /// - Parameter compoundFilter: Compound filter object
    /// - Returns: JSON dictionary
    class func serialize(compoundFilter: RapidFilterCompound) throws -> [AnyHashable: Any] {
        switch compoundFilter.compoundOperator {
        case .and where compoundFilter.operands.count > 0:
            return ["and": try compoundFilter.operands.map({ try serialize(filter: $0) })]
            
        case .or where compoundFilter.operands.count > 0:
            return ["or": try compoundFilter.operands.map({ try serialize(filter: $0) })]
            
        case .not where compoundFilter.operands.count == 1:
            if let filter = compoundFilter.operands.first, let serializedFilter = try serialize(filter: filter) {
                return ["not": serializedFilter]
            }
            else {
                throw RapidError.invalidData(reason: .invalidFilter(filter: compoundFilter))
            }
            
        default:
            throw RapidError.invalidData(reason: .invalidFilter(filter: compoundFilter))
        }
    }
    
    /// Serialize an array of subscription orderings into JSON
    ///
    /// - Parameter ordering: Array of ordering objects
    /// - Returns: JSON dictionary
    class func serialize(ordering: [RapidOrdering]?) throws -> [[AnyHashable: Any]]? {
        if let ordering = ordering {
            let orderingArray = try ordering.map({ order -> [AnyHashable: Any] in
                guard Validator.isValid(keyPath: order.keyPath) else {
                    throw RapidError.invalidData(reason: .invalidKeyPath(keyPath: order.keyPath))
                }
                
                switch order.ordering {
                case .ascending:
                    return [order.keyPath: "asc"]
                    
                case .descending:
                    return [order.keyPath: "desc"]

                }
            })
            
            return orderingArray
        }

        return nil
    }
    
    /// Serialize an unsubscription request into JSON string
    ///
    /// - Parameters:
    ///   - unsubscription: Unsubscription object
    ///   - identifiers: Identifiers that are associated with the unsubscription event
    /// - Returns: JSON string
    /// - Throws: `JSONSerialization` and `RapidError.invalidData` errors
    class func serialize(unsubscription: RapidUnsubscriptionHandler, withIdentifiers identifiers: [AnyHashable: Any]) throws -> String {
        var json = identifiers
        
        json[Unsubscribe.SubscriptionID.name] = unsubscription.subscription.subscriptionID
        
        let resultDict: [AnyHashable: Any] = [Unsubscribe.name: json]
        return try resultDict.jsonString()
    }
    
    /// Serialize an event acknowledgement into JSON string
    ///
    /// - Parameters:
    ///   - acknowledgement: Acknowledgement object
    /// - Returns: JSON string
    /// - Throws: `JSONSerialization` and `RapidError.invalidData` errors
    class func serialize(acknowledgement: RapidClientAcknowledgement) throws -> String {
        let resultDict = [Acknowledgement.name: [EventID.name: acknowledgement.eventID]]
        return try resultDict.jsonString()
    }
    
    /// Serialize an event acknowledgement into JSON string
    ///
    /// - Parameters:
    ///   - acknowledgement: Acknowledgement object
    /// - Returns: JSON string
    /// - Throws: `JSONSerialization` and `RapidError.invalidData` errors
    class func serialize(acknowledgement: RapidServerAcknowledgement) throws -> String {
        let resultDict = [Acknowledgement.name: [EventID.name: acknowledgement.eventID]]
        return try resultDict.jsonString()
    }
    
    /// Serialize a connection request into JSON string
    ///
    /// - Parameters:
    ///   - connection: Connection request object
    ///   - identifiers: Identifiers that are associated with the connection request event
    /// - Returns: JSON string
    /// - Throws: `JSONSerialization` and `RapidError.invalidData` errors
    class func serialize(connection: RapidConnectionRequest, withIdentifiers identifiers: [AnyHashable: Any]) throws -> String {
        var json = identifiers
        
        json[Connect.ConnectionID.name] = connection.connectionID
        
        let resultDict = [Connect.name: json]
        return try resultDict.jsonString()
    }
    
    /// Serialize a reconnection request into JSON string
    ///
    /// - Parameters:
    ///   - reconnection: Reconnection request object
    ///   - identifiers: Identifiers that are associated with the connection request event
    /// - Returns: JSON string
    /// - Throws: `JSONSerialization` and `RapidError.invalidData` errors
    class func serialize(reconnection: RapidReconnectionRequest, withIdentifiers identifiers: [AnyHashable: Any]) throws -> String {
        var json = identifiers
        
        json[Reconnect.ConnectionID.name] = reconnection.connectionID
        
        let resultDict = [Reconnect.name: json]
        return try resultDict.jsonString()
    }
    
    /// Serialize an disconnection request into JSON string
    ///
    /// - Parameters:
    ///   - disconnection: Disconnection request object
    /// - Returns: JSON string
    /// - Throws: `JSONSerialization` and `RapidError.invalidData` errors
    class func serialize(disconnection: RapidDisconnectionRequest) throws -> String {
        let resultDict = [Disconnect.name: NSNull()]
        return try resultDict.jsonString()
    }
    
    /// Serialize an empty request into JSON string
    ///
    /// - Parameters:
    ///   - emptyRequest: Request object
    /// - Returns: JSON string
    /// - Throws: `JSONSerialization` and `RapidError.invalidData` errors
    class func serialize(emptyRequest: RapidEmptyRequest) throws -> String {
        let resultDict = [NoOperation.name: NSNull()]
        return try resultDict.jsonString()
    }
    
    class func serialize(authRequest: RapidAuthRequest, withIdentifiers identifiers: [AnyHashable: Any]) throws -> String {
        var json = identifiers
        
        json[Authorization.Token.name] = authRequest.auth.token
        
        let resultDict = [Authorization.name: json]
        return try resultDict.jsonString()
    }
    
    class func serialize(authRequest: RapidDeauthRequest, withIdentifiers identifiers: [AnyHashable: Any]) throws -> String {
        let resultDict = [Deauthorization.name: identifiers]
        return try resultDict.jsonString()
    }
}

// MARK: Fileprivate methods
fileprivate extension RapidSerialization {
    
    /// Parse single event received from websocket
    ///
    /// - Parameter json: Event JSON
    /// - Returns: Deserialized object
    class func parseEvent(json: [AnyHashable: Any]) -> RapidServerMessage? {
        if let ack = json[Acknowledgement.name] as? [AnyHashable: Any] {
            return RapidServerAcknowledgement(json: ack)
        }
        else if let err = json[Error.name] as? [AnyHashable: Any] {
            return RapidErrorInstance(json: err)
        }
        else if let val = json[SubscriptionValue.name] as? [AnyHashable: Any] {
            return RapidSubscriptionBatch(withCollectionJSON: val)
        }
        else if let upd = json[SubscriptionUpdate.name] as? [AnyHashable: Any] {
            return RapidSubscriptionBatch(withUpdateJSON: upd, docRemoved: false)
        }
        else if let rm = json[SubscriptionDocRemoved.name] as? [AnyHashable: Any] {
            return RapidSubscriptionBatch(withUpdateJSON: rm, docRemoved: true)
        }
        else if let ca = json[Cancel.name] as? [AnyHashable: Any] {
            return RapidSubscriptionCancel(json: ca)
        }
        else if let res = json[FetchValue.name] as? [AnyHashable: Any] {
            return RapidFetchResponse(withJSON: res)
        }

        return nil
    }
    
}

// MARK: Name constants

//swiftlint:disable nesting
extension RapidSerialization {
    
    struct Batch {
        static let name = "batch"
    }
    
    struct EventID {
        static let name = "evt-id"
    }
    
    struct Acknowledgement {
        static let name = "ack"
    }
    
    struct Error {
        static let name = "err"
        
        struct ErrorType {
            static let name = "err-type"
            
            struct Internal {
                static let name = "internal-error"
            }
            
            struct PermissionDenied {
                static let name = "permission-denied"
            }
            
            struct ConnectionTerminated {
                static let name = "connection-terminated"
            }
            
            struct InvalidAuthToken {
                static let name = "invalid-auth-token"
            }
            
            struct ClientSide {
                static let name = "client-error"
            }
            
            struct WriteConflict {
                static let name = "etag-conflict"
            }
        }
        
        struct ErrorMessage {
            static let name = "err-msg"
        }
    }
    
    struct Mutation {
        static let name = "mut"
        
        struct CollectionID {
            static let name = "col-id"
        }
        
        struct Document {
            static let name = "doc"
            
            struct DocumentID {
                static let name = "id"
            }
            
            struct Etag {
                static let name = "etag"
            }
            
            struct Body {
                static let name = "body"
            }
        }
    }
    
    struct Merge {
        static let name = "mer"
        
        struct CollectionID {
            static let name = "col-id"
        }
        
        struct Document {
            static let name = "doc"
            
            struct DocumentID {
                static let name = "id"
            }
            
            struct Etag {
                static let name = "etag"
            }
            
            struct Body {
                static let name = "body"
            }
        }
    }
    
    struct Delete {
        static let name = "del"
        
        struct CollectionID {
            static let name = "col-id"
        }
        
        struct Document {
            static let name = "doc"
            
            struct DocumentID {
                static let name = "id"
            }
            
            struct Etag {
                static let name = "etag"
            }
        }
    }
    
    struct Fetch {
        static let name = "ftc"
        
        struct FetchID {
            static let name = "ftc-id"
        }
        
        struct CollectionID {
            static let name = "col-id"
        }
        
        struct Filter {
            static let name = "filter"
        }
        
        struct Ordering {
            static let name = "order"
        }
        
        struct Limit {
            static let name = "limit"
        }
        
        struct Skip {
            static let name = "skip"
        }
    }
    
    struct Subscription {
        static let name = "sub"
        
        struct SubscriptionID {
            static let name = "sub-id"
        }
        
        struct CollectionID {
            static let name = "col-id"
        }
        
        struct Filter {
            static let name = "filter"
        }
        
        struct Ordering {
            static let name = "order"
        }
        
        struct Limit {
            static let name = "limit"
        }
        
        struct Skip {
            static let name = "skip"
        }
    }
    
    struct FetchValue {
        static let name = "res"
        
        struct FetchID {
            static let name = "ftc-id"
        }
        
        struct CollectionID {
            static let name = "col-id"
        }
        
        struct Documents {
            static let name = "docs"
        }
    }
    
    struct SubscriptionValue {
        static let name = "val"
        
        struct SubscriptionID {
            static let name = "sub-id"
        }
        
        struct CollectionID {
            static let name = "col-id"
        }
        
        struct Documents {
            static let name = "docs"
        }
    }
    
    struct SubscriptionUpdate {
        static let name = "upd"
        
        struct SubscriptionID {
            static let name = "sub-id"
        }
        
        struct CollectionID {
            static let name = "col-id"
        }
        
        struct Document {
            static let name = "doc"
        }
    }
    
    struct SubscriptionDocRemoved {
        static let name = "rm"
    }
    
    struct Document {
        
        struct DocumentID {
            static let name = "id"
        }
        
        struct Modified {
            static let name = "ts"
        }
        
        struct SortValue {
            static let name = "crt"
        }
        
        struct CreatedAt {
            static let name = "crt-ts"
        }
        
        struct ModifiedAt {
            static let name = "mod-ts"
        }
        
        struct Body {
            static let name = "body"
        }
        
        struct Etag {
            static let name = "etag"
        }
        
        struct SortKeys {
            static let name = "skey"
        }
    }
    
    struct Unsubscribe {
        static let name = "uns"
        
        struct SubscriptionID {
            static let name = "sub-id"
        }
    }
    
    struct Connect {
        static let name = "con"
        
        struct ConnectionID {
            static let name = "con-id"
        }
    }
    
    struct Reconnect {
        static let name = "rec"
        
        struct ConnectionID {
            static let name = "con-id"
        }
    }
    
    struct Disconnect {
        static let name = "dis"
    }
    
    struct NoOperation {
        static let name = "nop"
    }
    
    struct Authorization {
        static let name = "auth"
        
        struct Token {
            static let name = "token"
        }
    }
    
    struct Deauthorization {
        static let name = "deauth"
    }
    
    struct Cancel {
        static let name = "ca"
        
        struct CollectionID {
            static let name = "col-id"
        }
        
        struct SubscriptionID {
            static let name = "sub-id"
        }
    }
}
