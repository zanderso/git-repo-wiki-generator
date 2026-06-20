// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' as io;
import 'package:args/args.dart';
import 'package:git_repo_wiki_generator/compile_wiki.dart';

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption(
      'input-dir',
      abbr: 'i',
      help: 'The directory containing raw commit markdown files.',
      mandatory: true,
    )
    ..addOption(
      'output-dir',
      abbr: 'o',
      help: 'The directory where compiled wiki markdown files will be written.',
      mandatory: true,
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help message');

  try {
    final results = parser.parse(arguments);

    if (results.flag('help')) {
      print('Usage: dart bin/compile_wiki.dart -i <input-dir> -o <output-dir>');
      print(parser.usage);
      return;
    }

    final inputDirName = results.option('input-dir') as String;
    final outputDirName = results.option('output-dir') as String;

    final inputDir = io.Directory(inputDirName);
    final outputDir = io.Directory(outputDirName);

    print('Compiling wiki from $inputDirName to $outputDirName...');
    compileWiki(inputDir, outputDir);
  } on FormatException catch (e) {
    print(e.message);
    print('Usage: dart bin/compile_wiki.dart -i <input-dir> -o <output-dir>');
    print(parser.usage);
    io.exitCode = 1;
  } on ArgumentError catch (e) {
    print('Error: ${e.message}');
    io.exitCode = 1;
  }
}
