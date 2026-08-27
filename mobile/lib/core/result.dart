/// Typed failures surfaced by the repository layer. UI maps these to the
/// mandated user-visible states (offline, unauthorized, blocked, ...).
enum AppFailureKind {
  network,
  unauthorized,
  notFound,
  blocked,
  conflict,
  rateLimited,
  notConfigured,
  unknown,
}

class AppFailure implements Exception {
  const AppFailure(this.kind, [this.message]);

  final AppFailureKind kind;
  final String? message;

  @override
  String toString() => 'AppFailure(${kind.name}${message == null ? '' : ': $message'})';
}

/// Minimal Result type so use-cases return explicit success/failure instead
/// of leaking provider exceptions into widgets.
sealed class Result<T> {
  const Result();

  R fold<R>(R Function(T value) onSuccess, R Function(AppFailure failure) onFailure) {
    final self = this;
    return switch (self) {
      Success<T>(:final value) => onSuccess(value),
      Failure<T>(:final failure) => onFailure(failure),
    };
  }

  bool get isSuccess => this is Success<T>;
}

class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

class Failure<T> extends Result<T> {
  const Failure(this.failure);
  final AppFailure failure;
}
