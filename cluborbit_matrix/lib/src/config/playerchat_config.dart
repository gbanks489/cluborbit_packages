import '../matrix_core/matrix_transport_client.dart';

enum MediaUploadMode { matrix, firebaseStorage }

typedef MatrixDatabaseBuilder = Future<Object?> Function(String databaseName);

class PlayerChatConfig {
  const PlayerChatConfig({
    required this.matrixHomeserver,
    this.serverHost = '',
    this.useHttps = true,
    this.mediaUploadMode = MediaUploadMode.matrix,
    this.pushGateway = '',
    this.pushGatewayUseHttps = true,
    this.pushAppId = 'com.cluborbit.playerchat',
    this.pushAppDisplayName = 'ClubOrbit Chat',
    this.matrixClientName = 'cluborbit_chat_client',
    this.matrixDatabaseName = 'cluborbit_chat_matrix_sdk',
    this.matrixDatabaseBuilder,
    this.matrixTransportFactory,
  });

  final String matrixHomeserver;
  final String serverHost;
  final bool useHttps;
  final MediaUploadMode mediaUploadMode;
  final String pushGateway;
  final bool pushGatewayUseHttps;
  final String pushAppId;
  final String pushAppDisplayName;

  final String matrixClientName;
  final String matrixDatabaseName;
  final MatrixDatabaseBuilder? matrixDatabaseBuilder;
  final MatrixTransportFactory? matrixTransportFactory;
}
