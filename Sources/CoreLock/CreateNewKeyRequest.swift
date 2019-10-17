//
//  CreateNewKeyRequest.swift
//  CoreLock
//
//  Created by Alsey Coleman Miller on 10/16/19.
//  Copyright © 2019 ColemanCDA. All rights reserved.
//

import Foundation
import CryptoSwift

public struct CreateNewKeyNetServiceRequest: Equatable {
    
    /// Lock server
    public let server: URL
    
    /// Authorization header
    public let authorization: LockNetService.Authorization
    
    /// Encrypted request
    public let encryptedData: LockNetService.EncryptedData
}

// MARK: - URL Request

public extension CreateNewKeyNetServiceRequest {
    
    func urlRequest(encoder: JSONEncoder = JSONEncoder()) -> URLRequest {
        
        // http://localhost:8080/keys
        let url = server.appendingPathComponent("keys")
        var urlRequest = URLRequest(url: url)
        urlRequest.addValue(authorization.header, forHTTPHeaderField: LockNetService.Authorization.headerField)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = try! encoder.encode(encryptedData)
        return urlRequest
    }
}

// MARK: - Encryption

public extension CreateNewKeyNetServiceRequest {
    
    init(server: URL,
         encrypt value: CreateNewKeyRequest,
         with key: KeyCredentials,
         encoder: JSONEncoder = JSONEncoder()) throws {
        
        self.server = server
        self.authorization = LockNetService.Authorization(key: key)
        let data = try encoder.encode(value)
        self.encryptedData = try .init(encrypt: data, with: key.secret)
    }
    
    static func decrypt(_ encryptedData: LockNetService.EncryptedData,
                        with key: KeyData,
                        decoder: JSONDecoder = JSONDecoder()) throws -> CreateNewKeyRequest {
        
        let jsonData = try encryptedData.decrypt(with: key)
        return try decoder.decode(CreateNewKeyRequest.self, from: jsonData)
    }
}

// MARK: - Client

public extension LockNetService.Client {
    
    /// Create new key.
    func createKey(_ newKey: CreateNewKeyRequest,
                   for server: LockNetService,
                   with key: KeyCredentials,
                   timeout: TimeInterval = 30.0) throws {
        
        log?("Create \(newKey.permission.type) key \"\(newKey.name)\" \(newKey.identifier)")
        
        let request = try CreateNewKeyNetServiceRequest(
            server: server.url,
            encrypt: newKey,
            with: key,
            encoder: jsonEncoder
        )
        
        let (httpResponse, _) = try urlSession.synchronousDataTask(with: request.urlRequest())
        
        guard httpResponse.statusCode == 202
            else { throw LockNetService.Error.statusCode(httpResponse.statusCode) }
    }
}
