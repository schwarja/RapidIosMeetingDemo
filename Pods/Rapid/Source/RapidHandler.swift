//
//  RapidHandler.swift
//  Rapid
//
//  Created by Jan Schwarz on 17/03/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

import Foundation

/// Handler for accessing `RapidCache`
protocol RapidCacheHandler: class {
    /// Load data associated with a given subscription
    ///
    /// - Parameters:
    ///   - subscription: Subscription handler object
    ///   - completion: Completion handler. If there are any cached data for the subscription they are passed to the completion handler parameter
    func loadSubscriptionValue(forSubscription subscription: RapidSubscriptionHandler, completion: @escaping (_ dataset: [RapidCachableObject]?) -> Void)
    
    /// Store data associated with a given subscription
    ///
    /// - Parameters:
    ///   - value: Data to be stored
    ///   - subscription: Subscription handler object
    func storeDataset(_ dataset: [RapidCachableObject], forSubscription subscription: RapidSubscriptionHashable)
    
    /// Store single `RapidCachableObject`
    ///
    /// - Parameter object: Object that should be stored
    func storeObject(_ object: RapidCachableObject)
    
    /// Load single `RapidCachableObject` with given group ID and object ID
    ///
    /// - Parameters:
    ///   - groupID: `RapidCachableObject` group ID
    ///   - objectID: `RapidCachableObject` object ID
    ///   - completion: Completion handler. If there is any cached object with given IDs it is passed to the completion handler parameter
    func loadObject(withGroupID groupID: String, objectID: String, completion: @escaping (_ object: RapidCachableObject?) -> Void)
    
    /// Remove single `RapidCachableObject` from a cache
    ///
    /// - Parameters:
    ///   - groupID: `RapidCachableObject` group ID
    ///   - objectID: `RapidCachableObject` object ID
    func removeObject(withGroupID groupID: String, objectID: String)
}

/// General dependency object containing managers
class RapidHandler: NSObject {
    
    let apiKey: String
    
    let socketManager: RapidSocketManager!
    var state: Rapid.ConnectionState {
        return socketManager.networkHandler.state
    }
    
    var onConnectionStateChanged: ((Rapid.ConnectionState) -> Void)? {
        get {
            return socketManager.networkHandler.onConnectionStateChanged
        }
        
        set {
            socketManager.networkHandler.onConnectionStateChanged = newValue
        }
    }
    
    var authorization: RapidAuthorization? {
        return socketManager.auth
    }
    
    fileprivate(set) var cache: RapidCache?
    var cacheEnabled: Bool = false {
        didSet {
            RapidLogger.log(message: "Rapid cache enabled \(cacheEnabled)", level: .debug)
            
            // If caching was enbaled and there is no cache instance create it
            if cacheEnabled && cache == nil {
                self.cache = RapidCache(apiKey: apiKey)
            }
            // If caching was disabled release a cache instance and remove cached data
            else if !cacheEnabled {
                cache = nil
                RapidCache.clearCache(forApiKey: apiKey)
            }
        }
    }
    
    init?(apiKey: String) {
        // Decode connection information from API key
        if let url = Decoder.decode(apiKey: apiKey) {
            let networkHandler = RapidNetworkHandler(socketURL: url)
            
            socketManager = RapidSocketManager(networkHandler: networkHandler)
        }
        else {
            return nil
        }
        
        self.apiKey = apiKey
        
        super.init()
        
        socketManager.cacheHandler = self
    }

}

extension RapidHandler: RapidCacheHandler {
    
    func loadSubscriptionValue(forSubscription subscription: RapidSubscriptionHandler, completion: @escaping ([RapidCachableObject]?) -> Void) {
        cache?.loadDataset(forKey: subscription.subscriptionHash, secret: socketManager.auth?.token, completion: completion)
    }

    func storeDataset(_ dataset: [RapidCachableObject], forSubscription subscription: RapidSubscriptionHashable) {
        cache?.save(dataset: dataset, forKey: subscription.subscriptionHash, secret: socketManager.auth?.token)
    }
    
    func storeObject(_ object: RapidCachableObject) {
        cache?.save(object: object, withSecret: socketManager.auth?.token)
    }
    
    func loadObject(withGroupID groupID: String, objectID: String, completion: @escaping (RapidCachableObject?) -> Void) {
        cache?.loadObject(withGroupID: groupID, objectID: objectID, secret: socketManager.auth?.token, completion: completion)
    }
    
    func removeObject(withGroupID groupID: String, objectID: String) {
        cache?.removeObject(withGroupID: groupID, objectID: objectID)
    }
}
