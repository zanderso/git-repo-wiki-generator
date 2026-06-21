// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' as io;
import 'package:args/args.dart';
import 'package:git_repo_wiki_generator/json_to_markdown.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'output-dir',
      abbr: 'd',
      help: 'The directory in which converted markdown files will be written.',
      mandatory: true,
    )
    ..addFlag(
      'prs',
      help:
          'Indicate that the input jsonl data is for PRs rather than commits.',
      negatable: false,
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help message');

  try {
    final results = parser.parse(arguments);

    if (results.flag('help')) {
      print(
        'Usage: dart bin/json_to_markdown.dart -d <output-dir> <input-jsonl-files...>',
      );
      print(parser.usage);
      return;
    }

    final outputDirName = results.option('output-dir') as String;
    final outputDir = io.Directory(outputDirName);

    if (results.rest.isEmpty) {
      print('Error: At least one input JSONL file must be specified.');
      io.exitCode = 1;
      return;
    }

    for (final fileArg in results.rest) {
      final file = io.File(fileArg);
      if (!file.existsSync()) {
        print('Error: Input file does not exist: $fileArg');
        io.exitCode = 1;
        return;
      }
      if (results.flag('prs')) {
        await convertJsonlToMarkdown(
          file,
          outputDir,
          includeFilter: defaultPrFilters,
          filenameField: '.pull_request.merge_commit_sha',
        );
      } else {
        await convertJsonlToMarkdown(file, outputDir);
      }
    }
    print('Conversion completed successfully.');
  } on FormatException catch (e) {
    print(e.message);
    print(
      'Usage: dart bin/json_to_markdown.dart -d <output-dir> <input-jsonl-files...>',
    );
    print(parser.usage);
    io.exitCode = 1;
  }
}
