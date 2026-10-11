#
# Embeds the Rust crypto library (matrix-sdk-crypto, see ../rust) in iOS apps that use
# cluborbit_matrix. Dart loads it through flutter_rust_bridge as
# `cluborbit_matrix_native.framework/cluborbit_matrix_native`.
#
# The framework is built locally, like the Android .so files - run ../rust/build_ios.sh first.
#
Pod::Spec.new do |s|
  s.name             = 'cluborbit_matrix'
  s.version          = '0.1.0'
  s.summary          = 'ClubOrbit Matrix native crypto (Rust) for iOS.'
  s.homepage         = 'https://github.com/gbanks489/cluborbit_packages'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'ClubOrbit' => 'gbanks489@gmail.com' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '15.0'
  s.dependency 'Flutter'

  s.vendored_frameworks = 'Frameworks/cluborbit_matrix_native.xcframework'

  unless File.exist?(File.join(__dir__, 'Frameworks', 'cluborbit_matrix_native.xcframework'))
    Pod::UI.warn 'cluborbit_matrix: Frameworks/cluborbit_matrix_native.xcframework is missing - ' \
                 'run cluborbit_matrix/rust/build_ios.sh, or encrypted chat will not work on iOS.'
  end
end
