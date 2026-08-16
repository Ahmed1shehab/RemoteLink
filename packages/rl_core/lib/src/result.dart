import 'package:meta/meta.dart';

/// A value that is either a success ([Ok]) or a typed failure ([Err]).
///
/// The network and native layers use [Result] instead of exceptions on their
/// hot paths. Throwing across a per-frame boundary is both slower and easier to
/// forget to handle; a sealed [Result] makes the analyzer force exhaustive
/// switches at every call site.
@immutable
sealed class Result<T, E extends Object> {
  const Result();

  const factory Result.ok(T value) = Ok<T, E>;
  const factory Result.err(E error) = Err<T, E>;

  bool get isOk => this is Ok<T, E>;
  bool get isErr => this is Err<T, E>;

  /// The success value, or `null` when this is an [Err].
  T? get valueOrNull => switch (this) {
        Ok<T, E>(:final value) => value,
        Err<T, E>() => null,
      };

  /// The failure, or `null` when this is an [Ok].
  E? get errorOrNull => switch (this) {
        Ok<T, E>() => null,
        Err<T, E>(:final error) => error,
      };

  /// The success value, or [fallback] when this is an [Err].
  T unwrapOr(T fallback) => switch (this) {
        Ok<T, E>(:final value) => value,
        Err<T, E>() => fallback,
      };

  /// The success value. Throws [StateError] on [Err] — only call after an
  /// [isOk] check or in tests.
  T unwrap() => switch (this) {
        Ok<T, E>(:final value) => value,
        Err<T, E>(:final error) => throw StateError('unwrap() on Err: $error'),
      };

  /// Transforms the success value, leaving a failure untouched.
  Result<R, E> map<R>(R Function(T value) fn) => switch (this) {
        Ok<T, E>(:final value) => Ok<R, E>(fn(value)),
        Err<T, E>(:final error) => Err<R, E>(error),
      };

  /// Transforms the failure, leaving a success untouched.
  Result<T, F> mapErr<F extends Object>(F Function(E error) fn) =>
      switch (this) {
        Ok<T, E>(:final value) => Ok<T, F>(value),
        Err<T, E>(:final error) => Err<T, F>(fn(error)),
      };

  /// Chains another fallible step onto a success.
  Result<R, E> andThen<R>(Result<R, E> Function(T value) fn) => switch (this) {
        Ok<T, E>(:final value) => fn(value),
        Err<T, E>(:final error) => Err<R, E>(error),
      };

  /// Collapses both branches into a single value.
  R fold<R>(R Function(T value) onOk, R Function(E error) onErr) =>
      switch (this) {
        Ok<T, E>(:final value) => onOk(value),
        Err<T, E>(:final error) => onErr(error),
      };
}

@immutable
final class Ok<T, E extends Object> extends Result<T, E> {
  const Ok(this.value);

  final T value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Ok<T, E> && other.value == value);

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

@immutable
final class Err<T, E extends Object> extends Result<T, E> {
  const Err(this.error);

  final E error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Err<T, E> && other.error == error);

  @override
  int get hashCode => Object.hash(Err, error);

  @override
  String toString() => 'Err($error)';
}

/// Runs [body], converting any thrown object into an [Err] via [onError].
///
/// Used at the boundary between RemoteLink code and third-party APIs that still
/// signal failure by throwing (`dart:io`, `package:cryptography`).
Result<T, E> guard<T, E extends Object>(
  T Function() body,
  E Function(Object error, StackTrace stackTrace) onError,
) {
  try {
    return Ok<T, E>(body());
  } on Object catch (e, st) {
    return Err<T, E>(onError(e, st));
  }
}

/// Async counterpart of [guard].
Future<Result<T, E>> guardAsync<T, E extends Object>(
  Future<T> Function() body,
  E Function(Object error, StackTrace stackTrace) onError,
) async {
  try {
    return Ok<T, E>(await body());
  } on Object catch (e, st) {
    return Err<T, E>(onError(e, st));
  }
}
