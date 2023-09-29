//
//  SplashViewModel.swift
//  여행의 시작 Boarding
//
//  Created by 서충원 on 2023/09/27.
//

import Foundation
import RxSwift
import RxCocoa
import KakaoSDKCommon
import RxKakaoSDKCommon
import KakaoSDKAuth
import RxKakaoSDKAuth
import KakaoSDKUser
import RxKakaoSDKUser
import FirebaseAuth

class SplashViewModel {
    
    let isUserLoggedIn = PublishRelay<Bool>()
    
    let disposeBag = DisposeBag()
    
    func checkCurrentUser() {
        let user = Auth.auth().currentUser
        if let user = user {
            isUserLoggedIn.accept(true)
            print("현재 로그인된 유저는 \(user)")
        } else {
            isUserLoggedIn.accept(false)
        }
    }
    
    // 카카오 로그인 유무 확인 - 현재는 사용 안하고 Firebase Auth로 로그인 판별중
    func checkTokenExist() {
        if AuthApi.hasToken() {
            checkTokenInfo()
        } else {
            //토큰이 없는 상태 - transfer LogIn
            isUserLoggedIn.accept(false)
        }
    }
    
    func checkTokenInfo() {
        UserApi.shared.rx.accessTokenInfo()
            .subscribe(onSuccess: { [weak self] accessTokenInfo in
                //토큰도 있고, 토큰에 에러도 없는 상태 - transfer Home
                self?.isUserLoggedIn.accept(true)
            }, onFailure: { [weak self] error in
                if let sdkError = error as? SdkError, sdkError.isInvalidTokenError() == true {
                    //토큰이 있지만, 토큰에 유효성 에러가 있는 상태 - transfer LogIn
                    self?.isUserLoggedIn.accept(false)
                    print("Token is Invalid")
                } else {
                    //토큰이 있지만, 토큰에 다른 에러가 있는 상태 - transfer LogIn
                    self?.isUserLoggedIn.accept(false)
                    print("Error: \(error)")
                }
            })
            .disposed(by: disposeBag)
    }
}
