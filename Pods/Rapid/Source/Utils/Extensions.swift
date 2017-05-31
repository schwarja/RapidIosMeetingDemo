//
//  TimerExtension.swift
//  Rapid
//
//  Created by Jan on 12/04/2017.
//  Copyright © 2017 Rapid.io. All rights reserved.
//

import Foundation

class TimerTarget: NSObject {
    
    let block: (_ userInfo: Any?) -> Void
    
    init(block: @escaping (_ userInfo: Any?) -> Void) {
        self.block = block
    }
    
    func timerFired(_ timer: Timer) {
        block(timer.userInfo)
    }
}

extension Timer {
    
    class func scheduledTimer(timeInterval ti: TimeInterval, userInfo: Any?, repeats yesOrNo: Bool, block: @escaping (_ userInfo: Any?) -> Void) -> Timer {
        let target = TimerTarget(block: block)
        
        return Timer.scheduledTimer(timeInterval: ti, target: target, selector: #selector(target.timerFired(_:)), userInfo: userInfo, repeats: yesOrNo)
    }
}

extension Character {
    var asciiValue: UInt32? {
        return String(self).unicodeScalars.filter({$0.isASCII}).first?.value
    }
}

extension Collection where Iterator.Element: Hashable {
    var frequencies: [(Iterator.Element, Int)] {
        var seen: [Iterator.Element: Int] = [:]
        var frequencies: [(Iterator.Element, Int)] = []
        for element in self {
            if let idx = seen[element] {
                frequencies[idx].1 += 1
            }
            else {
                seen[element] = frequencies.count
                frequencies.append((element, 1))
            }
        }
        return frequencies
    }
}

extension URL {
    
    /// Memory size in bytes
    /// Returns nil if URL is not local or does not exist
    var memorySize: Int? {
        guard self.isFileURL else {
            return nil
        }
        
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: self.path, isDirectory: &isDir) else {
            return nil
        }
        
        if !isDir.boolValue {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: self.path)
                return attributes[FileAttributeKey.size] as? Int ?? 0
            }
            catch {
                return 0
            }
            
        }
        
        var totalSize = 0
        
        let enumerator = FileManager.default.enumerator(at: self, includingPropertiesForKeys: [.isExcludedFromBackupKey])
        
        if let enumerator = enumerator {
            
            for fileURL in enumerator {
                
                if let fileURL = fileURL as? URL {
                    
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                        let size = attributes[FileAttributeKey.size] as? Int ?? 0
                        totalSize += size
                    }
                    catch { }
                    
                }
            }
        }
        
        return totalSize
    }
}

extension OperationQueue {
    
    func async(execute work: @escaping @convention(block) () -> Void) {
        if OperationQueue.current == self {
            work()
        }
        else {
            self.addOperation(work)
        }
    }
}

extension Dictionary {
    
    mutating func merge(with dictionary: [Key: Value]) {
        for (key, value) in dictionary {
            let current = self[key]
            
            if value is NSNull {
                self[key] = nil
            }
            else if var currentDict = current as? [Key: Value], let valueDict = value as? [Key: Value] {
                currentDict.merge(with: valueDict)
                self[key] = currentDict as? Value            }
            else {
                self[key] = value
            }
        }
    }
}
