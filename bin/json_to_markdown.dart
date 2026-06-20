// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:args/args.dart';

import 'package:repo_analysis/json_to_markdown.dart';

ArgParser buildParser() {
  return ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show additional command output.',
    )
    ..addMultiOption(
      'input',
      abbr: 'i',
      help: 'An input jsonl file.',
    )
    ..addOption(
      'output-dir',
      abbr: 'd',
      help: 'The subdirectory of the working directory in which a markdown '
            'doc for each commit will be written. Created if not present.',
      mandatory: true,
    );
}

void printUsage(ArgParser argParser) {
  print('Usage: dart repo_analysis.dart <flags> [arguments]');
  print(argParser.usage);
}

bool gVerbose = false;

const List<String> includeFilter = [
  '.commit.author',
  '.commit.commiter.date',
  '.commit.message',
  '.author.login',
  '.stats',
  '.files.files.filename',
  '.files.files.patch',
];

void main(List<String> arguments) async {
  final ArgParser argParser = buildParser();
  try {
    final ArgResults results = argParser.parse(arguments);
    final List<String> jsonlNames = results.multiOption('input');
    final String outputName = results.option('output-dir') as String;
    final io.Directory outputDir = io.Directory(outputName);

    if (jsonlNames.isEmpty) {
      io.exitCode = 1;
      print('Specify input files with --input');
      printUsage(argParser);
      return;
    }

    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    for (final String jsonlName in jsonlNames) {
      final io.File jsonlFile = io.File(jsonlName);
      final Stream<String> lines = jsonlFile.openRead()
        .transform(utf8.decoder)       // Convert bytes to UTF-8
        .transform(const LineSplitter());
      int i = 0;
      await for (final String line in lines) {
        final Map<String, dynamic> jsonObject = json.decode(line);
        final String mdPrefix;
        if (jsonObject.containsKey('sha')) {
          mdPrefix = jsonObject['sha'] as String;
        } else {
          mdPrefix =  i.toString();
        }
        final StringBuffer mdbuf = StringBuffer();
        final io.File mdFile = io.File('${outputDir.path}/$mdPrefix.md');
        jsonObjectToMarkdown(jsonObject, mdbuf, includeFilter: includeFilter);
        mdFile.writeAsStringSync(mdbuf.toString());
        i++;
      }
    }
  } on FormatException catch (e) {
    // Print usage information if an invalid argument was provided.
    print(e.message);
    print('');
    printUsage(argParser);
  }
}