//
//  PropertiesLoader.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/5/4.
//

import Foundation

public enum PropertiesLoader {
    public static func load(at url: URL) throws(LoadError) -> [String: String] {
        let data: Data
        do {
            data = try .init(contentsOf: url)
        } catch {
            throw .failedToReadFile(underlying: error)
        }
        
        guard let content = String(data: data, encoding: .utf8) else {
            throw .failedToDecodeContent
        }
        
        return try load(from: content)
    }
    
    public static func load(from string: String) throws(LoadError) -> [String: String] {
        var result: [String: String] = [:]
        // 必须按「任意换行符」切，而不是 split(separator: "\n")：
        // Swift 把 "\r\n" 当成**一个** Character，按 "\n" 切根本切不开，
        // 于是一份 CRLF 写出来的 Secrets.properties 会整份变成一行、抛 invalidLine，
        // 看起来就是"所有 Key 都丢了"。split(whereSeparator: \.isNewline) 同时吃
        // LF / CRLF / CR 三种行尾。
        let lines = string.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.starts(with: "#") }
        
        for line in lines {
            // omittingEmptySubsequences 必须关掉：`KEY=` 这类"键在、值为空"的行
            // 是合法的（CI 没拿到 secret 时就会写出这种行），以前它会被拆成
            // 只有键的一段而抛 invalidLine，进而让整份 Secrets.properties 作废，
            // 连带着把同一文件里其它正常的键一起丢掉（Issue #4）。
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                .map { String.init($0)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: .init(charactersIn: "\"")) }
            guard parts.count == 2, !parts[0].isEmpty else {
                throw .invalidLine(line: line)
            }
            
            let (key, value) = (parts[0], parts[1])
            
            guard result[key] == nil else {
                throw .duplicateKey(key: key)
            }
            result[key] = value
        }
        
        return result
    }
    
    public enum LoadError: LocalizedError {
        case failedToReadFile(underlying: Error)
        case failedToDecodeContent
        case invalidLine(line: String)
        case duplicateKey(key: String)
        
        public var errorDescription: String? {
            switch self {
            case .failedToReadFile(let underlying):
                "读取文件失败：\(underlying.localizedDescription)"
            case .failedToDecodeContent:
                "解码文件内容失败。"
            case .invalidLine(let line):
                "无效的行：\"\(line)\""
            case .duplicateKey(let key):
                "包含重复键：\"\(key)\""
            }
        }
    }
}
