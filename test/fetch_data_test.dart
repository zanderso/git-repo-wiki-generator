// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io' as io;
import 'package:test/test.dart';
import 'package:args/args.dart';
import '../bin/fetch_data.dart' as cli;

void main() {
  group('ArgParser', () {
    late ArgParser parser;

    setUp(() {
      parser = cli.buildParser();
    });

    test('defines required options', () {
      expect(parser.options.containsKey('config'), isTrue);
      expect(parser.options['config']!.abbr, equals('c'));
      expect(parser.options['config']!.mandatory, isTrue);
    });

    test('defines optional options including commit-output and pr-output', () {
      expect(parser.options.containsKey('commit-output'), isTrue);
      expect(parser.options['commit-output']!.abbr, equals('o'));
      expect(parser.options['commit-output']!.mandatory, isFalse);

      expect(parser.options.containsKey('output-dir'), isTrue);
      expect(parser.options['output-dir']!.abbr, equals('d'));
      expect(parser.options['output-dir']!.mandatory, isFalse);

      expect(parser.options.containsKey('wiki-dir'), isTrue);
      expect(parser.options['wiki-dir']!.abbr, equals('w'));
      expect(parser.options['wiki-dir']!.mandatory, isFalse);

      expect(parser.options.containsKey('pr-output'), isTrue);
      expect(parser.options['pr-output']!.mandatory, isFalse);

      expect(parser.options.containsKey('pr-dir'), isTrue);
      expect(parser.options['pr-dir']!.mandatory, isFalse);
    });

    test('parses options correctly when both are specified', () {
      final results = parser.parse([
        '-c',
        'config.json',
        '-o',
        'out.jsonl',
        '--pr-output',
        'prs.jsonl',
      ]);
      expect(results['config'], equals('config.json'));
      expect(results['commit-output'], equals('out.jsonl'));
      expect(results['pr-output'], equals('prs.jsonl'));
    });

    test('parses option correctly when only commit-output is specified', () {
      final results = parser.parse([
        '-c',
        'config.json',
        '--commit-output',
        'out.jsonl',
      ]);
      expect(results['config'], equals('config.json'));
      expect(results['commit-output'], equals('out.jsonl'));
      expect(results['pr-output'], isNull);
    });

    test('parses option correctly when only pr-output is specified', () {
      final results = parser.parse([
        '-c',
        'config.json',
        '--pr-output',
        'prs.jsonl',
      ]);
      expect(results['config'], equals('config.json'));
      expect(results['commit-output'], isNull);
      expect(results['pr-output'], equals('prs.jsonl'));
    });
  });

  group('CLI main validation tests', () {
    late io.Directory tempDir;
    late io.File configFile;

    setUp(() {
      tempDir = io.Directory.systemTemp.createTempSync('cli_fetch_data_test_');
      configFile = io.File('${tempDir.path}/config.json');
      configFile.writeAsStringSync('''
      {
        "token": "test_token",
        "since": "2026-06-13T00:00:00Z",
        "until": "2026-06-19T23:59:59Z",
        "repos": ["owner/repo"],
        "bots": ["bot"]
      }
      ''');
      io.exitCode = 0;
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
      io.exitCode = 0;
    });

    test(
      'fails if neither --commit-output nor --pr-output are specified',
      () async {
        final printed = <String>[];
        await runZoned(
          () async {
            await cli.main(['-c', configFile.path]);
          },
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) {
              printed.add(line);
            },
          ),
        );

        expect(io.exitCode, equals(1));
        expect(
          printed,
          anyElement(
            contains(
              'Error: At least one of --commit-output or --pr-output must be specified.',
            ),
          ),
        );
      },
    );

    test(
      'fails if --output-dir is specified but --commit-output is not',
      () async {
        final printed = <String>[];
        await runZoned(
          () async {
            await cli.main([
              '-c',
              configFile.path,
              '--pr-output',
              'prs.jsonl',
              '--output-dir',
              'mdout',
            ]);
          },
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) {
              printed.add(line);
            },
          ),
        );

        expect(io.exitCode, equals(1));
        expect(
          printed,
          anyElement(
            contains(
              'Error: --commit-output is required when using --output-dir.',
            ),
          ),
        );
      },
    );

    test('fails if --pr-dir is specified but --pr-output is not', () async {
      final printed = <String>[];
      await runZoned(
        () async {
          await cli.main([
            '-c',
            configFile.path,
            '--commit-output',
            'commits.jsonl',
            '--pr-dir',
            'pr_md',
          ]);
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            printed.add(line);
          },
        ),
      );

      expect(io.exitCode, equals(1));
      expect(
        printed,
        anyElement(
          contains('Error: --pr-output is required when using --pr-dir.'),
        ),
      );
    });
  });
}
