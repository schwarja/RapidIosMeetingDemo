//
//  Helpers.swift
//  Rapid
//
//  Created by Jan Schwarz on 16/03/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

import Foundation

/// Helper method which runs a block of code on the main thread after specified number of seconds
///
/// - Parameters:
///   - delay: Run a block of code after `delay`
///   - closure: Block of code to be run
func runAfter(_ delay: TimeInterval, queue: DispatchQueue = DispatchQueue.main, closure: @escaping () -> Void) {
    queue.asyncAfter(
        deadline: DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: closure)
}

class Generator {
    
    /// Unique ID which can serve as a document or collection ID
    class var uniqueID: String {
        let shortID = base64(fromGuid: NSUUID())
        return shortID
    }
    
    /// Array of 64 characters for GUID representation
    static let byteCharArray = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-".characters)
    
    /// Get string representation of GUID
    ///
    /// Standard GUID string representation uses only hexadecimal characters (0123456789ABCDEF).
    /// This method uses 64 characters so the 128-bit GUID can be encoded to 22 characters in comparison with 32 characters of standard GUID representation.
    ///
    /// - Parameter guid: `NSUUID` instance
    /// - Returns: GUID string representation
    class func base64(fromGuid guid: NSUUID) -> String {
        // Get binary representation of GUID (it has 16 bytes)
        var bytes = [UInt8](repeating: 0, count: 16)
        guid.getBytes(&bytes)
        let data = Data(bytes: bytes)
        
        var numberOfBitsCarried: UInt8 = 0
        var carry: UInt8 = 0
        var resultString = ""
        
        for byte in data.enumerated() {
            numberOfBitsCarried += 2
            
            // Get 64-based number
            // Take first `8 - numberOfBitsCarried` bits from the byte and prepend it with bits carried from last iteration
            let shifted = (byte.element >> numberOfBitsCarried) + (carry << (8 - numberOfBitsCarried))
            
            // Append character to string
            resultString += String(byteCharArray[Int(shifted)])
            
            // Carry those bits which were not used for the 64-based number computation
            // It is last `numberOfBitsCarried` bits from the byte
            carry = byte.element & (255 >> (8 - numberOfBitsCarried))
            
            // 6 bits are enough to get next 64-based number.
            // So if 6 bits should be carried to a next iteration get 64-based number from it and do not carry anything
            if numberOfBitsCarried == 6 {
                resultString += String(byteCharArray[Int(carry)])
                
                carry = 0
                numberOfBitsCarried = 0
            }
        }
        
        // Deal with last two bits
        if numberOfBitsCarried > 0 {
            let shifted = carry << (6 - numberOfBitsCarried)
            resultString += String(byteCharArray[Int(shifted)])
        }
        
        return resultString
    }

}

class Decoder {
    
    /// Decode API key
    ///
    /// - Parameter apiKey: API key
    /// - Returns: Tuple of decoded values
    class func decode(apiKey: String) -> URL? {
        if let data = Data(base64Encoded: apiKey),
        let decodedString = String(data: data, encoding: .utf8),
        !decodedString.isEmpty,
        let url = URL(string: "ws://\(decodedString)") {
            return url
        }

        return nil
    }
}

class Validator {
    
    /// Check a document dictionary if it is valid
    ///
    /// - Parameter dict: Dictionary with a document value
    /// - Returns: Validated error
    /// - Throws: `RapidError.invalidData`
    class func validate(document dict: [AnyHashable: Any]) throws -> [AnyHashable: Any] {
        if isValid(document: dict) {
            return dict
        }
        
        throw RapidError.invalidData(reason: .invalidDocument(document: dict))
    }
    
    /// Check a document dictionary if it is valid
    ///
    /// - Parameter dict: Dictionary with a document value
    /// - Returns: `true` if a document is valid
    class func isValid(document dict: [AnyHashable: Any]) -> Bool {
        guard JSONSerialization.isValidJSONObject(dict) else {
            return false
        }
        
        for (key, value) in dict {
            if let key = key as? String, isValid(key: key) {
                if let dictionary = value as? [AnyHashable: Any] {
                    return isValid(document: dictionary)
                }
                else if let array = value as? [[AnyHashable: Any]] {
                    for dictionary in array {
                        if !isValid(document: dictionary) {
                            return false
                        }
                    }
                }

                continue
            }

            return false
        }
        
        return true
    }
    
    /// Check a key if it is valid
    ///
    /// - Parameter key: String with a key value
    /// - Returns: `true` if a key is valid
    class func isValid(key: String) -> Bool {
        let test = NSPredicate(format:"NOT (SELF CONTAINS '.')")
        return test.evaluate(with: key) && !key.isEmpty
    }
    
    /// Check a key path if it is valid
    ///
    /// - Parameter keyPath: String with a key path value
    /// - Returns: `true` if a key path is valid
    class func isValid(keyPath: String) -> Bool {
        let components = keyPath.components(separatedBy: ".")
        
        for key in components {
            if !isValid(key: key) {
                return false
            }
        }
        
        return true
    }
    
    /// Check an identifier if it is valid
    ///
    /// - Parameter identifier: String with an identifier value
    /// - Returns: Validated identifier
    /// - Throws: `RapidError.invalidData`
    @discardableResult
    class func validate(identifier: String) throws -> String {
        if isValid(identifier: identifier) {
            return identifier
        }

        throw RapidError.invalidData(reason: .invalidIdentifierFormat(identifier: identifier))
    }
    
    /// Check an identifier if it is valid
    ///
    /// - Parameter identifier: String with an identifier value
    /// - Returns: `true` if an identifier is valid
    class func isValid(identifier: String) -> Bool {
        let regex = "^[a-zA-Z0-9_-]+$"
        
        let test = NSPredicate(format:"SELF MATCHES %@", regex)
        return test.evaluate(with: identifier)
    }
    
}
