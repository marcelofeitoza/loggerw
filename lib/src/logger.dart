import 'package:loggerw/src/filters/development_filter.dart';
import 'package:loggerw/src/printers/pretty_printer.dart';
import 'package:loggerw/src/outputs/console_output.dart';
import 'package:loggerw/src/log_printer.dart';
import 'package:loggerw/src/log_output.dart';
import 'package:loggerw/src/log_filter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// [Level]s to control logging output. Logging can be enabled to include all
/// levels above certain [Level].
enum Level {
  all(0),
  @Deprecated('[verbose] is being deprecated in favor of [trace].')
  verbose(999),
  trace(1000),
  debug(2000),
  info(3000),
  warning(4000),
  error(5000),
  @Deprecated('[wtf] is being deprecated in favor of [fatal].')
  wtf(5999),
  fatal(6000),
  @Deprecated('[nothing] is being deprecated in favor of [off].')
  nothing(9999),
  off(10000),
  ;

  final int value;

  const Level(this.value);
}

class LogEvent {
  final Level level;
  final dynamic message;
  final Object? error;
  final StackTrace? stackTrace;

  /// Time when this log was created.
  final DateTime time;

  LogEvent(
    this.level,
    this.message, {
    DateTime? time,
    this.error,
    this.stackTrace,
  }) : time = time ?? DateTime.now();
}

class OutputEvent {
  final List<String> lines;
  final LogEvent origin;

  Level get level => origin.level;

  OutputEvent(this.origin, this.lines);
}

typedef LogCallback = void Function(LogEvent event);

typedef OutputCallback = void Function(OutputEvent event);

/// Use instances of logger to send log messages to the [LogPrinter].
class Logger {
  /// The current logging level of the app.
  ///
  /// All logs with levels below this level will be omitted.
  static Level level = Level.trace;

  /// The current default implementation of log filter.
  static LogFilter Function() defaultFilter = () => DevelopmentFilter();

  /// The current default implementation of log printer.
  static LogPrinter Function() defaultPrinter = () => PrettyPrinter();

  /// The current default implementation of log output.
  static LogOutput Function() defaultOutput = () => ConsoleOutput();

  static final Set<LogCallback> _logCallbacks = {};

  static final Set<OutputCallback> _outputCallbacks = {};

  final LogFilter _filter;
  final LogPrinter _printer;
  final LogOutput _output;
  bool _active = true;
  final String? apiURL; // Add this instance variable

  /// Create a new instance of Logger.
  ///
  /// You can provide a custom [printer], [filter], [output] and [level].
  /// If no custom [printer] is provided, [PrettyPrinter] is used.
  /// If no custom [filter] is provided, [DevelopmentFilter] is used.
  Logger({
    LogFilter? filter,
    LogPrinter? printer,
    LogOutput? output,
    Level? level,
    String? apiUrl, // Add apiUrl as a constructor parameter
  })  : _filter = filter ?? defaultFilter(),
        _printer = printer ?? defaultPrinter(),
        _output = output ?? defaultOutput(),
        apiURL = apiUrl {
    // Store apiUrl as an instance variable
    _filter.init();
    _filter.level = level ?? Logger.level;
    _printer.init();
    _output.init();
  }

  /// Log a message at level [Level.verbose].
  @Deprecated(
      "[Level.verbose] is being deprecated in favor of [Level.trace], use [t] instead.")
  void v(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    t(message, time: time, error: error, stackTrace: stackTrace);
  }

  /// Log a message at level [Level.trace].
  void t(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(Level.trace, message, time: time, error: error, stackTrace: stackTrace);
  }

  /// Log a message at level [Level.debug].
  void d(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(Level.debug, message, time: time, error: error, stackTrace: stackTrace);
  }

  /// Log a message at level [Level.info].
  void i(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(Level.info, message, time: time, error: error, stackTrace: stackTrace);
  }

  /// Log a message at level [Level.warning].
  void w(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(Level.warning, message,
        time: time, error: error, stackTrace: stackTrace);
  }

  /// Log a message at level [Level.error].
  void e(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(Level.error, message, time: time, error: error, stackTrace: stackTrace);
  }

  /// Log a message at level [Level.wtf].
  @Deprecated(
      "[Level.wtf] is being deprecated in favor of [Level.fatal], use [f] instead.")
  void wtf(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    f(message, time: time, error: error, stackTrace: stackTrace);
  }

  /// Log a message at level [Level.fatal].
  void f(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(Level.fatal, message, time: time, error: error, stackTrace: stackTrace);
  }

  /// Log a message with [level].
  void log(
    Level level,
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    if (!_active) {
      throw ArgumentError('Logger has already been closed.');
    } else if (error != null && error is StackTrace) {
      throw ArgumentError('Error parameter cannot take a StackTrace!');
    } else if (level == Level.all) {
      throw ArgumentError('Log events cannot have Level.all');
      // ignore: deprecated_member_use_from_same_package
    } else if (level == Level.off || level == Level.nothing) {
      throw ArgumentError('Log events cannot have Level.off');
    }

    var logEvent = LogEvent(
      level,
      message,
      time: time,
      error: error,
      stackTrace: stackTrace,
    );
    for (var callback in _logCallbacks) {
      callback(logEvent);
    }

    if (_filter.shouldLog(logEvent)) {
      var output = _printer.log(logEvent);

      if (output.isNotEmpty) {
        var outputEvent = OutputEvent(logEvent, output);
        // Issues with log output should NOT influence
        // the main software behavior.
        try {
          for (var callback in _outputCallbacks) {
            callback(outputEvent);
          }
          _output.output(outputEvent);
        } catch (e, s) {
          print(e);
          print(s);
        }
      }

      // Perform a POST request to the specified API URL
      // Perform a POST request to the stored API URL
      if (apiURL != null) {
        await _sendLogToApi(
          level: level,
          message: message,
          time: time,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _sendLogToApi({
    required Level level,
    required dynamic message,
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    if (apiURL == null) {
      print('API URL not provided. Cannot send log to API.');
      return;
    }

    var object = {
      'level': level.toString().split('.').last.toUpperCase(),
      'message': message.toString(),
      'time': time?.toIso8601String(),
      'error': error?.toString().replaceAll('\n', ' '),
      'stackTrace': stackTrace?.toString()
    };

    print('Sending log to API: $object');

    try {
      final response = await http.post(
        Uri.parse(apiURL!),
        body: jsonEncode(object),
        headers: {'Content-Type': 'application/json'},
      );

      print('API Response Status Code: ${response.statusCode}');
      print('API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        print('Log successfully sent to API');
      } else {
        print('Failed to send log to API');
      }
    } catch (e) {
      print('Error sending log to API: $e');
    }
  }

  bool isClosed() {
    return !_active;
  }

  /// Closes the logger and releases all resources.
  Future<void> close() async {
    _active = false;
    await _filter.destroy();
    await _printer.destroy();
    await _output.destroy();
  }

  /// Register a [LogCallback] which is called for each new [LogEvent].
  static void addLogListener(LogCallback callback) {
    _logCallbacks.add(callback);
  }

  /// Removes a [LogCallback] which was previously registered.
  ///
  /// Returns whether the callback was successfully removed.
  static bool removeLogListener(LogCallback callback) {
    return _logCallbacks.remove(callback);
  }

  /// Register an [OutputCallback] which is called for each new [OutputEvent].
  static void addOutputListener(OutputCallback callback) {
    _outputCallbacks.add(callback);
  }

  /// Removes a [OutputCallback] which was previously registered.
  ///
  /// Returns whether the callback was successfully removed.
  static void removeOutputListener(OutputCallback callback) {
    _outputCallbacks.remove(callback);
  }
}
