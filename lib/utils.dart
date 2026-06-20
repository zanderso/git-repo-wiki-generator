// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

/// Calls the function [f] and retries up to [retries] times if it throws an exception.
///
/// The optional named parameter [delay] configures the length of the delay
/// between retry attempts.
Future<T> callWithRetries<T>(
  FutureOr<T> Function() f, {
  int retries = 5,
  Duration delay = const Duration(seconds: 1),
}) async {
  for (int attempt = 1; attempt <= retries; attempt++) {
    try {
      return await f();
    } catch (e) {
      if (attempt == retries) {
        rethrow;
      }
      await Future<void>.delayed(delay);
    }
  }
  throw StateError('Unreachable');
}
