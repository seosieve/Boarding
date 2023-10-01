//
//  LogInViewModel.swift
//  여행의 시작 Boarding
//
//  Created by 서충원 on 2023/09/19.
//

import Foundation
import RxSwift
import RxCocoa
import RxKakaoSDKAuth
import KakaoSDKAuth
import RxKakaoSDKUser
import KakaoSDKUser
import FirebaseAuth
import CryptoKit
import AuthenticationServices

class LogInViewModel: NSObject {
    var currentNonce: String?
    let userNotExist = PublishRelay<Bool>()
    
    let errorCatch = PublishRelay<Bool>()
    let logInResult = PublishRelay<Bool>()
    
    let disposeBag = DisposeBag()
}

//MARK: - Apple SignIn
extension LogInViewModel {
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Nonce 생성 오류: \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        return String(nonce)
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        return hashString
    }
    
    func appleLogIn() {
        let nonce = randomNonceString()
        currentNonce = nonce
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
    
    func makeProfile(nickname: String, thumbnail: URL) {
        let changeRequest = Auth.auth().currentUser?.createProfileChangeRequest()
        changeRequest?.displayName = nickname
        changeRequest?.photoURL = thumbnail
        changeRequest?.commitChanges { [weak self] error in
            if let error = error {
                self?.errorCatch.accept(true)
                print("파이어베이스 프로필 생성 오류: \(error)")
            } else {
                self?.logInResult.accept(true)
                print("파이어베이스 프로필 생성 성공")
            }
        }
    }
}

extension LogInViewModel: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return window
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            let nonce = currentNonce!
            let tokenData = appleIDCredential.identityToken!
            let token = String(data: tokenData, encoding: .utf8)!
            let credential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: appleIDCredential.fullName)
            
            Auth.auth().signIn(with: credential) { [weak self] (authResult, error) in
                if let error = error {
                    print(error)
                    self?.errorCatch.accept(true)
                } else if let authResult = authResult {
                    if let fullName = appleIDCredential.fullName {
                        let displayName = [fullName.givenName, fullName.familyName].compactMap{$0}.joined()
                        self?.makeProfile(nickname: displayName, thumbnail: URL(string: "https://t3.ftcdn.net/jpg/00/64/67/52/360_F_64675209_7ve2XQANuzuHjMZXP3aIYIpsDKEbF5dD.jpg")!)
                        print("유저 로그인 성공: \(authResult)")
                    }
                }
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        //X버튼 누를때도 실행되기 때문에 에러처리 안했음
        self.logInResult.accept(false)
        print("애플 로그인 에러: \(error.localizedDescription)")
    }
}

//MARK: - Kakao SignIn
extension LogInViewModel {
    func kakaoLogIn() {
        if UserApi.isKakaoTalkLoginAvailable() {
            UserApi.shared.rx.loginWithKakaoTalk()
                .subscribe(onNext:{ [weak self] _ in
                    self?.kakaoUserInfo()
                }, onError: { [weak self] error in
                    self?.errorCatch.accept(true)
                    print("카카오톡(APP) 로그인 에러: \(error)")
                })
                .disposed(by: disposeBag)
        } else {
            UserApi.shared.rx.loginWithKakaoAccount()
                .subscribe(onNext: { [weak self] _ in
                    self?.kakaoUserInfo()
                }, onError: { [weak self] error in
                    self?.errorCatch.accept(true)
                    print("카카오계정(WEB) 로그인 에러: \(error)")
                })
                .disposed(by: disposeBag)
        }
    }
    
    func kakaoUserInfo() {
        UserApi.shared.rx.me()
            .subscribe(onSuccess:{ [weak self] user in
                if let email = user.kakaoAccount?.email, let password = user.id {
                    self?.signInUser(email: email, password: String(password))
                } else {
                    self?.errorCatch.accept(true)
                }
            }, onFailure: { [weak self] error in
                self?.errorCatch.accept(true)
                print("카카오 유저 정보 불러오기 오류: \(error)")
            })
            .disposed(by: disposeBag)
    }
    
    func signInUser(email: String, password: String) {
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] (authResult, error) in
            if let error = error {
                let code = (error as NSError).code
                print(code, error)
                switch code {
                case 17011:
                    // 유저가 존재하지 않을때
                    self?.userNotExist.accept(true)
                default:
                    self?.errorCatch.accept(true)
                }
            } else if let authResult = authResult {
                self?.logInResult.accept(true)
                print("유저 로그인 성공: \(authResult)")
            }
        }
    }
}
