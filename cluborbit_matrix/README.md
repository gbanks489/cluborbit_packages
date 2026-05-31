<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages).
-->

TODO: Put a short description of the package here that helps potential users
know whether this package might be useful for them.

## Features

TODO: List what your package can do. Maybe include images, gifs, or videos.

## Getting started

TODO: List prerequisites and provide or point to information on how to
start using the package.

## Usage

TODO: Include short and useful examples for package users. Add longer examples
to `/example` folder.

```dart
const like = 'sample';
```

## Additional information

TODO: Tell users more about the package: where to find more information, how to
contribute to the package, how to file issues, what response they can expect
from the package authors, and more.

# dev
flutter run --flavor dev --dart-define=ENV_FILE=.dev.env
cd C:\projects\playerchat\playerchat_matrix\example
flutter build apk --release --flavor dev --dart-define=ENV_FILE=.dev.env

# uat
flutter run --flavor uat --dart-define=ENV_FILE=.uat.env

# prod
flutter run --flavor prod --dart-define=ENV_FILE=.prod.env


# tail logs - in terminal 
adb shell
run-as com.cluborbit.messenger.app.dev
cd files
ls 
tail -f app.log
