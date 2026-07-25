import 'package:meta/meta.dart';

/// Base type for every failure RemoteLink models explicitly.
///
/// Errors carry a stable [code] so that the mobile UI can localise a message
/// without string-matching on English text, and so that telemetry can aggregate
/// failures across versions.
@immutable
sealed class RemoteLinkError implements Exception {
  const RemoteLinkError({required this.code, required this.message, this.cause});

  /// Stable machine-readable identifier, e.g. `protocol.short_frame`.
  final String code;

  /// Developer-facing English description. Never shown raw to end users.
  final String message;

  /// Underlying error, when this wraps a lower-level failure.
  final Object? cause;

  @override
  String toString() =>
      '$runtimeType($code): $message${cause == null ? '' : ' <- $cause'}';
}

/// The peer sent bytes that do not conform to the wire format.
///
/// Always fatal for the connection: once framing is desynchronised there is no
/// safe way to resynchronise a length-prefixed stream.
@immutable
final class ProtocolError extends RemoteLinkError {
  const ProtocolError(String code, String message, {Object? cause})
      : super(code: 'protocol.$code', message: message, cause: cause);
}

/// Handshake, pairing, authentication, or AEAD failure.
///
/// Deliberately coarse: distinguishing "bad MAC" from "unknown device" to a
/// remote caller leaks information useful to an attacker. The detail lives in
/// [message] for local logs only.
@immutable
final class SecurityError extends RemoteLinkError {
  const SecurityError(String code, String message, {Object? cause})
      : super(code: 'security.$code', message: message, cause: cause);
}

/// Socket, discovery, or timeout failure. Usually recoverable by reconnecting.
@immutable
final class TransportError extends RemoteLinkError {
  const TransportError(
    String code,
    String message, {
    Object? cause,
    this.retryable = true,
  }) : super(code: 'transport.$code', message: message, cause: cause);

  /// Whether the reconnect supervisor should retry. `false` for permanent
  /// conditions such as a version mismatch or a revoked device.
  final bool retryable;
}

/// A native OS call failed. [osErrorCode] is the platform's raw error value
/// (`GetLastError()` on Windows, `errno`/OSStatus on macOS).
@immutable
final class NativeError extends RemoteLinkError {
  const NativeError(
    String code,
    String message, {
    this.osErrorCode,
    Object? cause,
  }) : super(code: 'native.$code', message: message, cause: cause);

  final int? osErrorCode;

  @override
  String toString() =>
      '${super.toString()}${osErrorCode == null ? '' : ' [os=$osErrorCode]'}';
}

/// The device is known but not permitted to perform the requested action.
@immutable
final class PermissionError extends RemoteLinkError {
  const PermissionError(String code, String message, {Object? cause})
      : super(code: 'permission.$code', message: message, cause: cause);
}
