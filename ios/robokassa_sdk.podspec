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
  # Robokassa's iOS SDK is vendored under Sources/robokassa_sdk/RobokassaSDK and
  # compiled straight into this target — it is not on the CocoaPods trunk, and a
  # podspec cannot point a `dependency` at a git source. See that directory's
  # VENDORED.md for the upstream commit and the local modifications.
  s.source_files = 'robokassa_sdk/Sources/robokassa_sdk/**/*.swift'
  s.resources = ['robokassa_sdk/Sources/robokassa_sdk/RobokassaSDK/AssetsResources/ic_robokassa_loader.png']
  s.resource_bundles = {
    'robokassa_sdk_privacy' => ['robokassa_sdk/Sources/robokassa_sdk/PrivacyInfo.xcprivacy']
  }
  s.dependency 'Flutter'

  # Robokassa's iOS SDK requires iOS 14.
  s.platform = :ios, '14.0'
  s.ios.deployment_target = '14.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
