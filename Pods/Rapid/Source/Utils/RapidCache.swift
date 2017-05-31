//
//  RapidCache.swift
//  Rapid
//
//  Created by Jan Schwarz on 16/04/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

protocol RapidCachableObject: NSCoding {
    var objectID: String { get }
    var groupID: String { get }
}

/// Class for handling data cache
class RapidCache: NSObject {
    
    /// URL of a file with info about cached data
    fileprivate var cacheInfoURL: URL {
        return cacheDir.appendingPathComponent("00.dat")
    }

    /// URL of a file with info about data reference counts
    fileprivate var referenceCountInfoURL: URL {
        return cacheDir.appendingPathComponent("01.dat")
    }

    /// Shared file manager
    fileprivate let fileManager: FileManager
    
    /// URL of a directory with cached data
    fileprivate let cacheDir: URL
    
    /// Dedicated queue for I/O operations
    fileprivate let diskQueue: DispatchQueue
    
    /// Maximum size of a cache directory
    ///
    /// Default value is 100 MB
    fileprivate let maxSize: Float?
    
    /// Maximum Time To Live of a single piece of data
    ///
    /// Default value is nil e.i. no expiration
    fileprivate let timeToLive: TimeInterval?
    
    /// Dictionary with info about cached data
    ///
    /// It stores modification time for every piece of data
    fileprivate var cacheInfo: [String: [String: TimeInterval]]
    
    /// Dictionary with info about data reference counts
    fileprivate var referenceCountInfo: [String: [String: Int]]
    
    /// Initialize `RapidCache`
    ///
    /// - Parameters:
    ///   - apiKey: API key of Rapid database
    ///   - timeToLive: Maximum Time To Live of a single piece of data in seconds. Default value is nil e.i. no expiration
    ///   - maxSize: Maximum size of a cache directory in MB. Default value is 100 MB
    init?(apiKey: String, timeToLive: TimeInterval? = nil, maxSize: Float? = 100) {
        guard !apiKey.isEmpty, let cacheURL = RapidCache.cacheURL(forApiKey: apiKey) else {
            RapidLogger.log(message: "Cache not initialized", level: .debug)
            return nil
        }
        
        guard (timeToLive ?? 1) > 0 && (maxSize ?? 1) > 0 else {
            RapidLogger.log(message: "Cache not initialized", level: .debug)
            return nil
        }
        
        self.fileManager = FileManager()
        self.cacheDir = cacheURL
        
        self.maxSize = maxSize
        self.timeToLive = timeToLive
        
        var isDir: ObjCBool = false
        
        // If the URL exists but it is a file replace the file with a directory
        // Otherwise create a directory at the URL
        if fileManager.fileExists(atPath: cacheDir.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                do {
                    try fileManager.removeItem(at: cacheURL)
                    try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)
                }
                catch {
                    RapidLogger.log(message: "Cache not initialized", level: .debug)
                    return nil
                }
            }
        }
        else {
            do {
                try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)
            }
            catch {
                RapidLogger.log(message: "Cache not initialized", level: .debug)
                return nil
            }
        }
        
        // Load info about cached data
        if let data = try? Data(contentsOf: cacheDir.appendingPathComponent("00.dat")), let info = NSKeyedUnarchiver.unarchiveObject(with: data) as? [String: [String: TimeInterval]] {
            cacheInfo = info
        }
        else {
            cacheInfo = [:]
        }
        
        // Load info about reference counts
        if let data = try? Data(contentsOf: cacheDir.appendingPathComponent("01.dat")), let info = NSKeyedUnarchiver.unarchiveObject(with: data) as? [String: [String: Int]] {
            referenceCountInfo = info
        }
        else {
            referenceCountInfo = [:]
        }
        
        diskQueue = DispatchQueue(label: "io.rapid.cache.disk", qos: .utility)
        
        super.init()
        
        // Prune cached data
        diskQueue.async {
            self.pruneCache()
        }
    }
    
    /// Compute hash for a key
    ///
    /// - Parameter key: Cache key
    ///   - unique: 'true' if hash should be unique for all possible keys from character set a-zA-Z0-9_-
    /// - Returns: Hash for the key
    func hash(forKey key: String, unique: Bool = false) -> String {
        if key.isEmpty {
            return "1"
        }
        
        if unique {
            //Concatanate ascii values
            return key.characters.flatMap({ $0.asciiValue }).reduce("") { "\($0)\($1)" }
        }
        
        // Get list of characters, compute their frequencies and sort characters according to their frequencies
        let metaString = key.lowercased().characters.frequencies.sorted(by: { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 })
        
        var hash: UInt64 = 0
        
        for (index, tuple) in metaString.enumerated() {
            hash += (UInt64(index + 1) * 101) * UInt64(tuple.1) * UInt64(tuple.0.asciiValue ?? 0)
            
            if hash > UInt64(UInt32.max) {
                hash = hash % 2147483647
            }
        }
        
        return "\(max(hash, 1))"
    }
    
    /// Find out if there are cached data for a given key
    ///
    /// - Parameters:
    ///   - key: Cache key
    ///   - completion: Completion handler. Boolean parameter is `true` if any data are cached for the key
    func hasData(forKey key: String, completion: @escaping (Bool) -> Void) {
        diskQueue.async {
            let hash = self.hash(forKey: key)
            completion(self.cacheInfo[hash]?[key] != nil)
        }
    }
    
    /// Get cached data for a given key
    ///
    /// - Parameters:
    ///   - key: Cache key
    ///   - secret: Secret key for data decryption
    ///   - completion: Completion handler. If there are any cached data for the key they are passed in the completion handler parameter.
    func loadDataset(forKey key: String, secret: String? = nil, completion: @escaping ([RapidCachableObject]?) -> Void) {
        diskQueue.async {
            completion(self.loadDataset(forKey: key, secret: secret))
        }
    }
    
    /// Get cached object with given group ID and object ID
    ///
    /// - Parameters:
    ///   - groupID: `RapidCachableObject` group ID
    ///   - objectID: `RapidCachableObject` object ID
    ///   - secret: Secret key for data decryption
    ///   - completion: Completion handler. If there is any cached object for the ids it is passed in the completion handler parameter.
    func loadObject(withGroupID groupID: String, objectID: String, secret: String? = nil, completion: @escaping (RapidCachableObject?) -> Void) {
        diskQueue.async {
            completion(self.loadObjects(forGroupID: groupID, objectIDs: [objectID], secret: secret).first)
        }
    }
    
    /// Store data with a given key to the cache
    ///
    /// - Parameters:
    ///   - data: Data to be cached
    ///   - key: Cache key
    ///   - secret: Secret key for data encryption
    func save(dataset: [RapidCachableObject], forKey key: String, secret: String? = nil) {
        diskQueue.async {
            self.saveDataset(dataset, forKey: key, secret: secret)
        }
    }
    
    /// Store cachable object with a given group ID and object ID
    ///
    /// - Parameters:
    ///   - object: `RapidCachableObject` to be cached
    ///   - secret: Secret key for data encryption
    func save(object: RapidCachableObject, withSecret secret: String? = nil) {
        diskQueue.async {
            self.saveObjects(objects: [object], withSecret: secret)
        }
    }
    
    /// Remove cached object from all cached dataset
    ///
    /// - Parameters:
    ///   - groupID: Group ID of `RapidCachableObject` that should be removed
    ///   - objectID: Object ID of `RapidCachableObject` that should be removed
    func removeObject(withGroupID groupID: String, objectID: String) {
        diskQueue.async {
            self.removeObject(withGroupID: groupID, objectIDs: [objectID])
        }
    }
    
    /// Remove all data from the cache
    func clearCache() {
        diskQueue.async {
            self.removeCache()
        }
    }
    
    /// Remove cached data for a given key
    ///
    /// - Parameter key: Cache key
    func clearCache(forKey key: String) {
        diskQueue.async {
            self.removeDataset(forKey: key)
        }
    }
    
}

// MARK: Class methods
extension RapidCache {
    
    /// Get an URL to a cache directory for a given API key
    ///
    /// - Parameter apiKey: API key of a Rapid database
    /// - Returns: URL to a cache directory
    class func cacheURL(forApiKey apiKey: String) -> URL? {
        let urlSafeApiKey = apiKey.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "-")
        
        guard let cachePath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first else {
            return nil
        }
        
        return URL(string: cachePath, relativeTo: URL(string: "file://"))?.appendingPathComponent("io.rapid.cache", isDirectory: true).appendingPathComponent(urlSafeApiKey, isDirectory: true)
    }
    
    /// Remove all data from a cache with a given API key
    ///
    /// - Parameter apiKey: API key of a Rapid database
    class func clearCache(forApiKey apiKey: String) {
        guard let cacheURL = cacheURL(forApiKey: apiKey) else {
            return
        }
        
        do {
            let manager = FileManager()
            
            try manager.removeItem(at: cacheURL)
        }
        catch {
            RapidLogger.log(message: "Cache wasn't cleared", level: .debug)
        }
    }
}

// MARK: Private methods
fileprivate extension RapidCache {
    
    /// Bitwise XOR of binary data
    ///
    /// - Parameters:
    ///   - data: Data that should be XORed
    ///   - secret: Secret key used for XOR
    /// - Returns: XORed data
    func byteXor(data: Data, secret: String) -> Data {
        guard let secretData = secret.data(using: .utf8) else {
            return data
        }
        
        let secretBytes = Array(secretData)
        
        var encrypted = [UInt8]()
        for byte in data.enumerated() {
            let index = byte.offset % secretBytes.count
            let next = byte.element ^ secretBytes[index]
            encrypted.append(next)
        }
        
        return Data(bytes: encrypted)
    }
    
    /// Get cached objects with given group ID and object IDs
    ///
    /// - Parameters:
    ///   - groupID: Shared group ID of cache objects
    ///   - objectIDs: Array of object IDs
    ///   - secret: Secret key for data decryption
    /// - Returns: Array of cached objects
    func loadObjects(forGroupID groupID: String, objectIDs: [String], secret: String?) -> [RapidCachableObject] {
        guard let fileDict = loadObjectsDictionary(forGroupID: groupID) else {
            return []
        }
        
        var cachedObjects = [RapidCachableObject]()
        
        for objectID in objectIDs {
            if let data = fileDict[objectID] {
                let cachedObject: RapidCachableObject?
                
                if let secret = secret {
                    let cache = byteXor(data: data, secret: secret)
                    cachedObject = NSKeyedUnarchiver.unarchiveObject(with: cache) as? RapidCachableObject
                }
                else {
                    cachedObject = NSKeyedUnarchiver.unarchiveObject(with: data) as? RapidCachableObject
                }
                
                if let cachedObject = cachedObject {
                    cachedObjects.append(cachedObject)
                }
            }
        }
        
        return cachedObjects
    }
    
    /// Get a dictionary with cached objects with a given group ID
    ///
    /// - Parameter groupID: Shared group ID of cached objects
    /// - Returns: Dictionary with cached objects
    func loadObjectsDictionary(forGroupID groupID: String) -> [String: Data]? {
        let groupHash = self.hash(forKey: groupID, unique: true)
        
        return objectsDictionary(forHash: groupHash)
    }
    
    /// Get cached data for a given key
    ///
    /// - Parameters:
    ///   - key: Cache key
    ///   - secret: Secret key for data decryption
    /// - Returns: Cached data if there are any
    func loadDataset(forKey key: String, secret: String?) -> [RapidCachableObject]? {
        let hash = self.hash(forKey: key)

        // Check in-memory cache info first
        if self.cacheInfo[hash]?[key] == nil {
            return nil
        }

        // Get array of object IDs, otherwise return nil
        let linkDict = self.linkDictionary(forHash: hash)
        guard let linkArray = linkDict[key] else {
            return nil
        }
        
        // If the array of object IDs is empty return empty array
        guard let groupID = linkArray.first?[0] else {
            return []
        }
        
        let ids = linkArray.map({ $0[1] })
        return loadObjects(forGroupID: groupID, objectIDs: ids, secret: secret)
    }
    
    /// Get lists of IDs of cached objects for all keys with a same hash value
    ///
    /// - Parameter hash: Hash value of a cache key
    /// - Returns: Dictionary with arrays of IDs of cached `RapidCachableObjects`
    func linkDictionary(forHash hash: String) -> [String: [[String]]] {
        let url = self.url(forHash: hash)
        
        do {
            let data = try Data(contentsOf: url)
            return NSKeyedUnarchiver.unarchiveObject(with: data) as? [String: [[String]]] ?? [:]
        }
        catch {
            return [:]
        }
    }
    
    /// Get cached objects for all keys with a same hash value
    ///
    /// - Parameter hash: Hash value of a `RapidCachableObject` group ID
    /// - Returns: Dictionary with cached pieces of data
    func objectsDictionary(forHash hash: String) -> [String: Data] {
        let url = self.url(forHash: hash, linkFile: false)
        
        do {
            let data = try Data(contentsOf: url)
            return NSKeyedUnarchiver.unarchiveObject(with: data) as? [String: Data] ?? [:]
        }
        catch {
            return [:]
        }
    }
    
    /// Store objects for a given dataset to the cache
    ///
    /// - Parameters:
    ///   - objects: Array of `RapidCachableObject`
    ///   - pointers: List of object IDs that were previously associated with the given dataset
    ///   - secret: Secret key for data encryption
    func saveObjects(objects: [RapidCachableObject], pointers: [[String]]? = nil, withSecret secret: String? = nil) {
        var mutPointers = pointers ?? []
        
        // Get shared `RapidCachableObject` group ID
        // `objects` array can be empty
        let key: String?
        if let object = objects.first {
            key = object.groupID
        }
        else {
            key = pointers?.first?.first
        }
        
        let hash: String?
        var fileDict: [String: Data]
        var referenceCounts: [String: Int]
        if let key = key {
            let groupHash = self.hash(forKey: key, unique: true)
            fileDict = objectsDictionary(forHash: groupHash)
            referenceCounts = referenceCountInfo[groupHash] ?? [:]
            hash = groupHash
        }
        else {
            fileDict = [:]
            referenceCounts = [:]
            hash = nil
        }
        
        for object in objects {
            // If object was in a previous dataset remove it from the array (to mark which objects have been processed)
            // Otherwise, increase a reference count
            if let index = mutPointers.index(where: { $0[0] == object.groupID && $0[1] == object.objectID }) {
                mutPointers.remove(at: index)
            }
            else {
                let count = referenceCounts["\(object.groupID)/\(object.objectID)"] ?? 0
                referenceCounts["\(object.groupID)/\(object.objectID)"] = count + 1
            }
        }
        
        // Decrease a reference counts of objects that aren't in the new dataset
        var removeIDs = [String]()
        for link in mutPointers {
            let count = referenceCounts["\(link[0])/\(link[1])"] ?? 0
            referenceCounts["\(link[0])/\(link[1])"] = max(0, count - 1)
            
            // If reference count is zero put down an object ID
            if count < 2 {
                removeIDs.append(link[1])
            }
        }
        
        // Store objects to the dictionary
        for object in objects {
            let data = NSKeyedArchiver.archivedData(withRootObject: object)
            if let secret = secret {
                fileDict[object.objectID] = byteXor(data: data, secret: secret)
            }
            else {
                fileDict[object.objectID] = data
            }
        }
        
        // Remove objects that have zero reference counts
        for id in removeIDs {
            fileDict[id] = nil
        }
        
        // Save to disk
        if let hash = hash {
            referenceCountInfo[hash] = referenceCounts
            saveReferenceCountInfo()
            saveFile(fileDict, forHash: hash, linkFile: false)
        }
    }
    
    /// Store data with a given key to the cache
    ///
    /// - Parameters:
    ///   - cache: Data to be stored
    ///   - key: Cache key
    ///   - secret: Secret for data encryption
    func saveDataset(_ cache: [RapidCachableObject], forKey key: String, secret: String?) {
        let hash = self.hash(forKey: key)
        
        // Add data to the cache
        var linkDict = linkDictionary(forHash: hash)
        
        saveObjects(objects: cache, pointers: linkDict[key], withSecret: secret)
        
        linkDict[key] = cache.map({ [$0.groupID, $0.objectID] })

        // Put down a timestamp of data modification
        if var dict = cacheInfo[hash] {
            dict[key] = Date().timeIntervalSince1970
            cacheInfo[hash] = dict
        }
        else {
            cacheInfo[hash] = [key: Date().timeIntervalSince1970]
        }
        
        saveCacheInfo()
        saveFile(linkDict, forHash: hash)
    }
    
    /// Write cache file to a disk
    ///
    /// - Parameters:
    ///   - cache: Dictionary of cached pieces of data
    ///   - hash: Hash value of keys associated with data in this cache file
    ///   - linkFile: `true` if `cache` is a dictionary with object IDs not physical data
    func saveFile(_ cache: [AnyHashable: Any], forHash hash: String, linkFile: Bool = true) {
        do {
            let data = NSKeyedArchiver.archivedData(withRootObject: cache)
            
            try data.write(to: self.url(forHash: hash, linkFile: linkFile))
        }
        catch {
            RapidLogger.log(message: "Cache wasn't saved", level: .debug)
        }
    }
    
    /// Write info about cached data to a disk
    func saveCacheInfo() {
        do {
            let data = NSKeyedArchiver.archivedData(withRootObject: cacheInfo)
            
            try data.write(to: cacheInfoURL)
        }
        catch {
            RapidLogger.log(message: "Cache info wasn't saved", level: .debug)
        }
    }
    
    /// Write info about reference counts to a disk
    func saveReferenceCountInfo() {
        do {
            let data = NSKeyedArchiver.archivedData(withRootObject: referenceCountInfo)
            
            try data.write(to: referenceCountInfoURL)
        }
        catch {
            RapidLogger.log(message: "Reference count info wasn't saved", level: .debug)
        }
    }
    
    /// Remove cache directory from a disk
    func removeCache() {
        do {
            self.cacheInfo.removeAll()
            self.referenceCountInfo.removeAll()
            
            try self.fileManager.removeItem(at: self.cacheDir)
        }
        catch {
            RapidLogger.log(message: "Cache wasn't cleared", level: .debug)
        }
    }
    
    /// Remove cached data for a given key
    ///
    /// - Parameter key: Cache key
    func removeDataset(forKey key: String) {
        let hash = self.hash(forKey: key)
        
        self.cacheInfo[hash]?[key] = nil
        
        var linkDict = self.linkDictionary(forHash: hash)
        
        let links = linkDict[key] ?? []
        
        // Process referenced objects
        if let groupID = links.first?.first {
            let groupHash = self.hash(forKey: groupID, unique: true)
            
            var removeIDs = [String]()
            var referenceCounts = referenceCountInfo[groupHash] ?? [:]
            
            // Decrease reference counts
            for link in links {
                let count = referenceCounts["\(link[0])/\(link[1])"] ?? 0
                referenceCounts["\(link[0])/\(link[1])"] = max(0, count - 1)
                
                if count < 2 {
                    removeIDs.append(link[1])
                }
            }
            
            referenceCountInfo[groupHash] = referenceCounts
            
            // Remove objects with zero reference counts
            removeObject(withGroupID: groupID, objectIDs: removeIDs)
        }
        
        // If there are still any data stored under the same hash value save the updated file
        // Otherwise remove the cache file
        if (self.cacheInfo[hash]?.keys.count ?? 0) > 0 {
            linkDict[key] = nil
            
            self.saveFile(linkDict, forHash: hash)
        }
        else {
            self.removeFile(forHash: hash)
        }
        
        self.saveCacheInfo()
        self.saveReferenceCountInfo()
    }
    
    /// Remove cached objects with given group ID and object IDs
    ///
    /// - Parameters:
    ///   - groupID: Shared `RapidCachableObject` group ID
    ///   - objectIDs: Array of `RapidCachableObject` object IDs
    func removeObject(withGroupID groupID: String, objectIDs: [String]) {
        guard var fileDict = loadObjectsDictionary(forGroupID: groupID) else {
            return
        }
        
        let hash = self.hash(forKey: groupID, unique: true)
        var references = referenceCountInfo[hash] ?? [:]
        
        for id in objectIDs {
            fileDict[id] = nil
            references["\(groupID)/\(id)"] = nil
        }
        
        if references.keys.count > 0 {
            saveFile(fileDict, forHash: hash, linkFile: false)
        }
        else {
            removeFile(forHash: hash, linkFile: false)
        }
        
        referenceCountInfo[hash] = references
        saveReferenceCountInfo()
    }
    
    /// Remove cache file from a disk
    ///
    /// - Parameters:
    ///   - hash: Hash value associated with data stored in a file
    ///   - linkFile: `true` if a cache file contains object IDs not physical data
    func removeFile(forHash hash: String, linkFile: Bool = true) {
        do {
            try fileManager.removeItem(at: url(forHash: hash, linkFile: linkFile))
        }
        catch {
            RapidLogger.log(message: "Cache file wasn't removed", level: .debug)
        }
    }
    
    /// Get URL to a file containing data that are stored under a given hash value
    ///
    /// - Parameters:
    ///   - hash: Hash value
    ///   - linkFile: `true` if a cache file contains object IDs not physical data
    /// - Returns: URL to a file
    func url(forHash hash: String, linkFile: Bool = true) -> URL {
        let prefix = linkFile ? "00" : "01"
        return cacheDir.appendingPathComponent("\(prefix)\(hash).dat")
    }
    
    /// Prune outdated or oversized cached data
    func pruneCache() {
        pruneOutdatedFiles()
        pruneIfNecessary()
    }
    
    /// Prune outdated cached data
    func pruneOutdatedFiles() {
        guard let ttl = timeToLive else {
            return
        }
        
        let referenceTimestamp = Date().timeIntervalSince1970 - ttl
        
        for (_, caches) in cacheInfo {
            for (key, timestamp) in caches where timestamp < referenceTimestamp {
                RapidLogger.log(message: "Outdated cache removed - key: \(key)", level: .debug)
                
                removeDataset(forKey: key)
            }
        }
    }
    
    /// Prune the oldest cached data if the cache directory is too large
    func pruneIfNecessary() {
        guard let maxSize = maxSize, Int(maxSize * 1024 * 1024) < (cacheDir.memorySize ?? 0) else {
            return
        }
        
        // Sort cached data according to their time of modification
        var sortedValues = cacheInfo
            .values
            .reduce([(String, TimeInterval)](), { temp, dict in
                let tuples = dict.map({ (key, value) in (key, value) })
                return temp + tuples
            })
            .sorted(by: { $0.1 < $1.1 })
        
        while (cacheDir.memorySize ?? 0) > Int((maxSize/2) * 1024 * 1024) && sortedValues.count > 0 {
            for (key, _) in sortedValues.prefix(5) {
                RapidLogger.log(message: "Cache file deleted because of size pruning - key: \(key)", level: .debug)
                
                removeDataset(forKey: key)
            }
            
            sortedValues = Array(sortedValues.dropFirst(5))
        }
    }
}
