//
//  APIRequest.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

public typealias APIRequestCompletion = (APIRequest.Response?, Error?) -> Void

public struct APIRequest {
    
    private let request: URLRequest
    private let urlSession: URLSession
    
    public init(configuration: APIRequest.Configuration,
                urlSession: URLSession = .shared) {
        self.request = configuration.request
        self.urlSession = urlSession
    }

    @discardableResult
    public func fetch(useEphemeralURLSession: Bool = true,
                      callBackOnMainThread: Bool = false,
                      completion: @escaping APIRequestCompletion) -> URLSessionDataTask {
        let session = URLSession.makeSession(useMainThreadCallbackQueue: callBackOnMainThread, ephemeral: useEphemeralURLSession)
        let task = session.dataTask(with: request) { (data, response, error) in
            if let error = error {
                completion(nil, .urlSession(error))
            } else {
                do {
                    try self.validate(data: data, response: response)
                    completion(APIRequest.Response(data: data, response: response), nil)
                } catch {
                    completion(nil, error)
                }
            }
        }
        task.resume()
        return task
    }
    
    private func validate(data: Data?,
                          response: URLResponse?,
                          shouldThrowOnMissingEtag: Bool = false) throws {
        guard let httpResponse = response?.asHTTPURLResponse else { throw APIRequest.Error.invalidResponse }
        try httpResponse.assertSuccessfulStatusCode()
        
        let etag = httpResponse.etag
        if shouldThrowOnMissingEtag && etag == nil {
            throw APIRequest.Error.missingEtagInResponse
        }
        guard let data = data, data.count > 0 else { throw APIRequest.Error.emptyData } // is it ok for every request?
    }

    public func fetch() async throws -> APIRequest.Response {
        let (data, response) = try await fetch(for: request)
        try validate(data: data, response: response, shouldThrowOnMissingEtag: true)
        return APIRequest.Response(data: data, response: response)
    }
        
    private func fetch(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch let error {
            throw Error.urlSession(error)
        }
    }

}

