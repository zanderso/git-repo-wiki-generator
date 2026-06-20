// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:test/test.dart';
import 'package:git_repo_wiki_generator/utils.dart';

void main() {
  group('callWithRetries', () {
    test('succeeds on first attempt without retrying', () async {
      int attempts = 0;
      final result = await callWithRetries<int>(() {
        attempts++;
        return 42;
      });

      expect(result, equals(42));
      expect(attempts, equals(1));
    });

    test('succeeds after multiple retries within limit', () async {
      int attempts = 0;
      final result = await callWithRetries<String>(
        () {
          attempts++;
          if (attempts < 3) {
            throw Exception('Attempt $attempts failed');
          }
          return 'success';
        },
        retries: 5,
        delay: const Duration(milliseconds: 10),
      );

      expect(result, equals('success'));
      expect(attempts, equals(3));
    });

    test('rethrows the exception after all retries are exhausted', () async {
      int attempts = 0;
      final callFuture = callWithRetries<double>(
        () {
          attempts++;
          throw FormatException('Malformed data on attempt $attempts');
        },
        retries: 4,
        delay: const Duration(milliseconds: 5),
      );

      await expectLater(
        callFuture,
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('attempt 4'),
          ),
        ),
      );
      expect(attempts, equals(4));
    });

    test('respects custom retry delay', () async {
      int attempts = 0;
      final stopwatch = Stopwatch()..start();

      await callWithRetries<void>(
        () {
          attempts++;
          if (attempts < 3) {
            throw Exception('Retry please');
          }
        },
        retries: 3,
        delay: const Duration(milliseconds: 50),
      );

      stopwatch.stop();
      expect(attempts, equals(3));
      // There are 2 delays between 3 attempts (attempt 1 fails -> delay -> attempt 2 fails -> delay -> attempt 3 succeeds).
      // Total delay should be at least 100ms.
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(95));
    });

    test('works with a synchronous return value', () async {
      final result = await callWithRetries<bool>(
        () => true,
        retries: 2,
        delay: const Duration(milliseconds: 1),
      );
      expect(result, isTrue);
    });

    test('rethrows immediately if retries <= 1', () async {
      int attempts = 0;
      final callFuture = callWithRetries<void>(
        () {
          attempts++;
          throw StateError('Immediate fail');
        },
        retries: 1,
        delay: const Duration(milliseconds: 100),
      );

      await expectLater(callFuture, throwsA(isA<StateError>()));
      expect(attempts, equals(1));
    });
  });
}
