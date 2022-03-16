//
//  ClientTokenRetrier.swift
//  TescoClubcard
//
//  Created by Lukas Andrlik on 22.02.2021.
//  Copyright © 2021 adastra.one. All rights reserved.
//

import Foundation
import Alamofire
 
class ClientTokenRetrier: RequestInterceptor {
        
    private typealias RefreshCompletion = (_ succeeded: Bool, _ accessToken: String?) -> Void
    internal typealias RequestRetryCompletion = (RetryResult) -> Void
    
    private let retryLimit = 2
    private var isRefreshing = false
    
    private var requestsToRetry: [RequestRetryCompletion] = []
    
    private let lock = NSLock()
    
    func retry(_ request: Request, for session: Session, dueTo error: Error, completion: @escaping RequestRetryCompletion) {
        
        lock.lock() ; defer { lock.unlock() }
        
        let loginData = UserLoginData(
            email: self.userDefaultsManager.email,
            password: self.userDefaultsManager.password,
            clubcardNumber: self.userDefaultsManager.clubcardNumber,
            isLoginAvailable: true
        )
        
        let loginEndpoint = Clubcard.login(userInfo: loginData)
        let loginEndpointUrl = loginEndpoint.baseURL.absoluteString + loginEndpoint.path

        guard let requestUrl = request.request?.url?.absoluteString, let responseStatusCode = request.response?.statusCode else {
            completion(.doNotRetry)
            return
        }
        
        if (request.retryCount < retryLimit) && (userStatusHelper.getUserStatus == .loggedIn) && (loginEndpointUrl != requestUrl) && (responseStatusCode == 401) {
            
            requestsToRetry.append(completion)
            refreshToken(endpoint: loginEndpoint) { [weak self] succeeded, accessToken in
                guard let self = self else { return }
                
                self.lock.lock() ; defer { self.lock.unlock() }
                
                self.isRefreshing = false
                if let accessToken = accessToken {
                    self.userDefaultsManager.accessToken = accessToken
                    self.requestsToRetry.forEach { $0(.retry) }
                    self.requestsToRetry.removeAll()
                } else {
                    completion(.doNotRetry)
                }
            }
        } else {
            completion(.doNotRetry)
        }
    }

    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var request = urlRequest
        guard !self.userDefaultsManager.accessToken.isEmpty else {
            completion(.success(urlRequest))
            return
        }
        request.setValue(self.userDefaultsManager.accessToken, forHTTPHeaderField: "Access-Token")
        completion(.success(request))
    }
    
    // MARK: - Private - Refresh Token

    private func refreshToken(endpoint: Clubcard, completion: @escaping RefreshCompletion) {
        
        guard !isRefreshing else { return }
        isRefreshing = true

        networkManager.request(endpoint,
                               parser: ParsingHelper.loginParser,
                               completion: { accessToken in
                                completion(true, accessToken)
                               }, errorHandler: { (error) in
                                completion(false, nil)
                               })
    }
}

// MARK: - DI
extension ClientTokenRetrier: HasUserDefaultsManager {}

extension ClientTokenRetrier: HasNetworkManager {}

extension ClientTokenRetrier: HasUserStatusHelper {
    var userStatusHelper: UserStatusHelpable {
        userStatusHelper()
    }
}
