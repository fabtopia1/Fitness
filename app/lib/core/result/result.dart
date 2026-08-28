/// A total result type. The domain layer never throws across a boundary — it
/// returns a [Result] so the caller is forced by the type system to handle
/// failure. See docs/02-system-architecture.md §9.
sealed class Result<T, E> {
  const Result();

  bool get isOk => this is Ok<T, E>;
  bool get isErr => this is Err<T, E>;

  /// The value, or null if this is an error.
  T? get valueOrNull => switch (this) {
        Ok<T, E>(:final value) => value,
        Err<T, E>() => null,
      };

  /// The error, or null if this is a success.
  E? get errorOrNull => switch (this) {
        Ok<T, E>() => null,
        Err<T, E>(:final error) => error,
      };

  R when<R>({
    required R Function(T value) ok,
    required R Function(E error) err,
  }) =>
      switch (this) {
        Ok<T, E>(:final value) => ok(value),
        Err<T, E>(:final error) => err(error),
      };

  Result<R, E> map<R>(R Function(T value) transform) => switch (this) {
        Ok<T, E>(:final value) => Ok<R, E>(transform(value)),
        Err<T, E>(:final error) => Err<R, E>(error),
      };

  Result<R, E> flatMap<R>(Result<R, E> Function(T value) transform) =>
      switch (this) {
        Ok<T, E>(:final value) => transform(value),
        Err<T, E>(:final error) => Err<R, E>(error),
      };

  T getOrElse(T Function(E error) fallback) => switch (this) {
        Ok<T, E>(:final value) => value,
        Err<T, E>(:final error) => fallback(error),
      };
}

final class Ok<T, E> extends Result<T, E> {
  const Ok(this.value);
  final T value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Ok<T, E> && other.value == value);

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => 'Ok($value)';
}

final class Err<T, E> extends Result<T, E> {
  const Err(this.error);
  final E error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Err<T, E> && other.error == error);

  @override
  int get hashCode => Object.hash(runtimeType, error);

  @override
  String toString() => 'Err($error)';
}
