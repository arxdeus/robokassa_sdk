#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint robokassa_sdk.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'robokassa_sdk'
  s.version          = '0.1.0'
  s.summary          = 'Robokassa payments for Flutter, with the native iOS checkout flow.'
  s.description      = <<-DESC
Signature generation, payment links, fiscal receipts, server callback
verification, and the full native 3-D Secure checkout flow via Robokassa's
official iOS SDK.
                       DESC
  s.homepage         = 'https://github.com/robokassa/sdk-flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Robokassa' => 'support@robokassa.ru' }
  s.source           = { :path => '.' }
  s.source_files = 'robokassa_sdk/Sources/robokassa_sdk/**/*'
  s.dependency 'Flutter'

  # Robokassa's iOS SDK.
  #
  # It is NOT published to the CocoaPods trunk, so a podspec cannot point at its
  # source — only a Podfile can. Your app must therefore declare where it comes
  # from, in `ios/Podfile`, inside the Runner target:
  #
  #   pod 'RobokassaSDK', :git => 'https://github.com/robokassa/sdk-ios.git', :tag => '1.0.0'
  #
  # CocoaPods then resolves this dependency against that external source. Without
  # it you will see:
  #   [!] Unable to find a specification for `RobokassaSDK`
  s.dependency 'RobokassaSDK'

  # Robokassa's iOS SDK requires iOS 14.
  s.platform = :ios, '14.0'
  s.ios.deployment_target = '14.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
