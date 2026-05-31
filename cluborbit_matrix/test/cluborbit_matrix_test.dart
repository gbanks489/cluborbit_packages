import 'package:flutter_test/flutter_test.dart';

import 'package:cluborbit_matrix/cluborbit_matrix.dart';

void main() {
  test('builds config correctly', () {
    const config = PlayerChatConfig(
      matrixHomeserver: 'https://matrix.org',
      serverHost: 'api.example.com',
      useHttps: true,
      mediaUploadMode: MediaUploadMode.matrix,
    );

    expect(config.matrixHomeserver, 'https://matrix.org');
    expect(config.useHttps, isTrue);
  });
}
