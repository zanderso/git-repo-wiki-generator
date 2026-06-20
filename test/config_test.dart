// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' as io;
import 'package:test/test.dart';
import 'package:repo_analysis/config.dart';

void main() {
  group('Config.fromMap', () {
    test('parses a valid configuration map successfully', () {
      final validMap = {
        'token': 'ghp_abcdef123456',
        'since': '2026-05-21T00:00:00Z',
        'until': '2026-05-27T23:59:59Z',
        'repos': ['flutter/flutter', 'flutter/engine'],
        'bots': ['gemini-code-assist[bot]', 'dependabot[bot]'],
      };

      final (config, error) = Config.fromMap(validMap);
      expect(error, isNull);
      expect(config, isNotNull);
      expect(config!.token, equals('ghp_abcdef123456'));
      expect(config.since, equals(DateTime.parse('2026-05-21T00:00:00Z')));
      expect(config.until, equals(DateTime.parse('2026-05-27T23:59:59Z')));
      expect(config.repos, equals(['flutter/flutter', 'flutter/engine']));
      expect(config.bots, equals(['gemini-code-assist[bot]', 'dependabot[bot]']));
    });

    test('fails if token is missing or not a String', () {
      final mapNoToken = {
        'since': '2026-05-21T00:00:00Z',
        'until': '2026-05-27T23:59:59Z',
        'repos': ['flutter/flutter'],
        'bots': ['bot'],
      };
      final (config1, error1) = Config.fromMap(mapNoToken);
      expect(config1, isNull);
      expect(error1, contains('"token" field must be a non-empty string.'));

      final mapInvalidToken = Map<String, dynamic>.from(mapNoToken)..['token'] = 12345;
      final (config2, error2) = Config.fromMap(mapInvalidToken);
      expect(config2, isNull);
      expect(error2, contains('"token" field must be a non-empty string.'));
    });

    test('fails if since date is missing or invalid', () {
      final baseMap = {
        'token': 'abc',
        'until': '2026-05-27T23:59:59Z',
        'repos': ['flutter/flutter'],
        'bots': ['bot'],
      };

      final (config1, error1) = Config.fromMap(baseMap);
      expect(config1, isNull);
      expect(error1, contains('"since" field must be a non-empty string.'));

      final mapInvalidSince = Map<String, dynamic>.from(baseMap)..['since'] = 'not-a-date';
      final (config2, error2) = Config.fromMap(mapInvalidSince);
      expect(config2, isNull);
      expect(error2, contains('is not a valid date string'));
    });

    test('fails if until date is missing or invalid', () {
      final baseMap = {
        'token': 'abc',
        'since': '2026-05-21T00:00:00Z',
        'repos': ['flutter/flutter'],
        'bots': ['bot'],
      };

      final (config1, error1) = Config.fromMap(baseMap);
      expect(config1, isNull);
      expect(error1, contains('"until" field must be a non-empty string.'));

      final mapInvalidUntil = Map<String, dynamic>.from(baseMap)..['until'] = 'not-a-date';
      final (config2, error2) = Config.fromMap(mapInvalidUntil);
      expect(config2, isNull);
      expect(error2, contains('is not a valid date string'));
    });

    test('fails if repos field is missing, empty, or not a list of strings', () {
      final baseMap = {
        'token': 'abc',
        'since': '2026-05-21T00:00:00Z',
        'until': '2026-05-27T23:59:59Z',
        'bots': ['bot'],
      };

      final (config1, error1) = Config.fromMap(baseMap);
      expect(config1, isNull);
      expect(error1, contains('"repos" field must be a non-empty list of strings.'));

      final mapEmptyRepos = Map<String, dynamic>.from(baseMap)..['repos'] = [];
      final (config2, error2) = Config.fromMap(mapEmptyRepos);
      expect(config2, isNull);
      expect(error2, contains('"repos" field must be a non-empty list of strings.'));

      final mapInvalidReposType = Map<String, dynamic>.from(baseMap)..['repos'] = [123, 456];
      final (config3, error3) = Config.fromMap(mapInvalidReposType);
      expect(config3, isNull);
      expect(error3, contains('"repos" field must be a non-empty list of strings.'));
    });

    test('fails if bots field is missing, empty, or not a list of strings', () {
      final baseMap = {
        'token': 'abc',
        'since': '2026-05-21T00:00:00Z',
        'until': '2026-05-27T23:59:59Z',
        'repos': ['flutter/flutter'],
      };

      final (config1, error1) = Config.fromMap(baseMap);
      expect(config1, isNull);
      expect(error1, contains('"bots" field must be a non-empty list of strings.'));

      final mapEmptyBots = Map<String, dynamic>.from(baseMap)..['bots'] = [];
      final (config2, error2) = Config.fromMap(mapEmptyBots);
      expect(config2, isNull);
      expect(error2, contains('"bots" field must be a non-empty list of strings.'));

      final mapInvalidBotsType = Map<String, dynamic>.from(baseMap)..['bots'] = [123, 456];
      final (config3, error3) = Config.fromMap(mapInvalidBotsType);
      expect(config3, isNull);
      expect(error3, contains('"bots" field must be a non-empty list of strings.'));
    });
  });

  group('Config.fromJson', () {
    test('parses a valid JSON string successfully', () {
      final jsonStr = '''
      {
        "token": "token_123",
        "since": "2026-05-21T00:00:00Z",
        "until": "2026-05-27T23:59:59Z",
        "repos": ["flutter/flutter"],
        "bots": ["bot"]
      }
      ''';
      final (config, error) = Config.fromJson(jsonStr);
      expect(error, isNull);
      expect(config, isNotNull);
      expect(config!.token, equals('token_123'));
    });

    test('fails on malformed JSON string', () {
      final jsonStr = '{"token": "token_123",';
      final (config, error) = Config.fromJson(jsonStr);
      expect(config, isNull);
      expect(error, contains('Not valid json'));
    });

    test('fails when JSON root is not a map', () {
      final jsonStr = '["token", "since"]';
      final (config, error) = Config.fromJson(jsonStr);
      expect(config, isNull);
      expect(error, contains('Root of JSON configuration must be a map.'));
    });
  });

  group('Config.fromFile', () {
    late io.Directory tempDir;

    setUp(() {
      tempDir = io.Directory.systemTemp.createTempSync('config_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('parses a valid configuration file successfully', () {
      final file = io.File('${tempDir.path}/valid_config.json');
      file.writeAsStringSync('''
      {
        "token": "file_token",
        "since": "2026-05-21T00:00:00Z",
        "until": "2026-05-27T23:59:59Z",
        "repos": ["flutter/flutter"],
        "bots": ["bot"]
      }
      ''');

      final (config, error) = Config.fromFile(file.path);
      expect(error, isNull);
      expect(config, isNotNull);
      expect(config!.token, equals('file_token'));
    });

    test('fails when file does not exist', () {
      final (config, error) = Config.fromFile('${tempDir.path}/does_not_exist.json');
      expect(config, isNull);
      expect(error, contains('Failed to read file'));
    });

    test('fails when file contains invalid JSON', () {
      final file = io.File('${tempDir.path}/invalid_config.json');
      file.writeAsStringSync('{"token": "file_token",');

      final (config, error) = Config.fromFile(file.path);
      expect(config, isNull);
      expect(error, contains('is not valid json'));
    });

    test('fails when file contains JSON list instead of map', () {
      final file = io.File('${tempDir.path}/invalid_list_config.json');
      file.writeAsStringSync('[]');

      final (config, error) = Config.fromFile(file.path);
      expect(config, isNull);
      expect(error, contains('Root of JSON configuration must be a map.'));
    });
  });
}
