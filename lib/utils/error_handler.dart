import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global error handler for uncaught exceptions
class GlobalErrorHandler {
  static void initialize() {
    // Handle Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _logError(details.exception, details.stack);
    };

    // Handle async errors
    PlatformDispatcher.instance.onError = (error, stack) {
      _logError(error, stack);
      return true;
    };
  }

  static void _logError(Object error, StackTrace? stack) {
    if (kDebugMode) {
      debugPrint('❌ Global Error: $error');
      if (stack != null) {
        debugPrint('Stack trace: $stack');
      }
    }
    // TODO: In production, send to crash reporting service (Sentry, Firebase Crashlytics, etc.)
  }
}

/// Error boundary widget that catches errors in widget tree
class ErrorBoundary extends ConsumerStatefulWidget {
  final Widget child;
  final Widget? fallback;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.fallback,
  });

  @override
  ConsumerState<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends ConsumerState<ErrorBoundary> {
  bool _hasError = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    // Catch errors in initState
    try {
      widget.child;
    } catch (e, stack) {
      _hasError = true;
      _error = e;
      if (kDebugMode) {
        debugPrint('ErrorBoundary caught error: $e\n$stack');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.fallback ??
          AppErrorWidget(
            message: _error?.toString() ?? 'An error occurred',
            onRetry: () {
              setState(() {
                _hasError = false;
                _error = null;
              });
            },
          );
    }

    return widget.child;
  }
}

/// Custom error widget with retry functionality
class AppErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const AppErrorWidget({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              SizedBox(height: 16),
              Text(
                'Something went wrong',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...[
                SizedBox(height: 24),
                ElevatedButton(
                  onPressed: onRetry,
                  child: Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

