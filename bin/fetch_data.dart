// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:github/github.dart' as g;
import 'package:git_repo_wiki_generator/config.dart';
import 'package:git_repo_wiki_generator/json_to_markdown.dart';
import 'package:git_repo_wiki_generator/compile_wiki.dart';
import 'package:git_repo_wiki_generator/commit_downloader.dart';

// Usage:
//
// $ dart bin/dash_commit_counts.dart -c config.json -o output.jsonl
//
// Pass a config.json file using the -c option to specify which commits to pull.
//
// {
//     "token": "Your GitHub token",
//     "since": "2026-05-21",
//     "until": "2026-05-27",
//     "repos": [
//         "flutter/flutter",
//         ...
//     ],
//     "bots": [
//         "gemini-code-assist[bot]",
//         ...
//     ]
// }

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
    ..addOption(
      'config',
      abbr: 'c',
      help: 'Path of the configuration file.',
      mandatory: true,
    )
    ..addOption(
      'output',
      abbr: 'o',
      help: 'Where to write raw commit json data',
      mandatory: true,
    )
    ..addOption(
      'output-dir',
      abbr: 'd',
      help:
          'The subdirectory of the working directory in which a markdown '
          'doc for each commit will be written. Created if not present.',
      mandatory: false,
    )
    ..addOption(
      'wiki-dir',
      abbr: 'w',
      help:
          'The subdirectory of the working directory in which compiled wiki '
          'pages will be written. Created if not present.',
      mandatory: false,
    );
}

void printUsage(ArgParser argParser) {
  print('Usage: dart bin/dash_commit_counts.dart <flags> [arguments]');
  print(argParser.usage);
}

bool _verbose = false;

void main(List<String> arguments) async {
  final ArgParser argParser = buildParser();
  try {
    final ArgResults results = argParser.parse(arguments);

    // Process the parsed arguments.
    if (results.flag('help')) {
      printUsage(argParser);
      return;
    }
    if (results.flag('verbose')) {
      _verbose = true;
    }

    if (_verbose) {
      print('[VERBOSE] All arguments: ${results.arguments}');
    }

    final (configResult, errorMsg) = Config.fromFile(
      results.option('config') as String,
    );
    if (errorMsg != null) {
      print(errorMsg);
      print('');
      printUsage(argParser);
      io.exitCode = 1;
      return;
    }
    final config = configResult!;

    if (_verbose) {
      print(config);
    }

    if (results.wasParsed('wiki-dir') && !results.wasParsed('output-dir')) {
      print('Error: --output-dir is required when using --wiki-dir.');
      printUsage(argParser);
      io.exitCode = 1;
      return;
    }

    final g.GitHub github = g.GitHub(
      auth: g.Authentication.withToken(config.token),
    );
    final CommitDownloader downloader = CommitDownloader(
      github: github,
      verbose: _verbose,
    );
    final List<g.RepositoryCommit> commits = await downloader
        .downloadCommitData(config);

    if (_verbose) {
      print('[VERBOSE] Done downloading commit data.');
    }

    if (commits.isEmpty) {
      print('No commits found!');
      io.exitCode = 1;
      return;
    }

    final rawOutputJson = io.File(results.option('output') as String);
    writeCommits(commits, rawOutputJson);

    if (results.wasParsed('output-dir')) {
      final String outputDirName = results.option('output-dir') as String;
      final io.Directory outputDir = io.Directory(outputDirName);
      if (_verbose) {
        print(
          '[VERBOSE] Converting JSONL to Markdown in directory: $outputDirName',
        );
      }
      await convertJsonlToMarkdown(rawOutputJson, outputDir);
    }

    if (results.wasParsed('wiki-dir')) {
      final String wikiDirName = results.option('wiki-dir') as String;
      final io.Directory wikiDir = io.Directory(wikiDirName);
      final String outputDirName = results.option('output-dir') as String;
      final io.Directory outputDir = io.Directory(outputDirName);
      if (_verbose) {
        print(
          '[VERBOSE] Compiling Wiki into directory: $wikiDirName from $outputDirName',
        );
      }
      compileWiki(outputDir, wikiDir);
    }
  } on FormatException catch (e) {
    // Print usage information if an invalid argument was provided.
    print(e.message);
    print('');
    printUsage(argParser);
  }
}

void writeCommits(List<g.RepositoryCommit> commits, io.File rawOutputJson) {
  if (_verbose) {
    print('[VERBOSE] Writing out raw commit data.');
  }

  final sink = rawOutputJson.openWrite(mode: io.FileMode.append);
  try {
    for (final g.RepositoryCommit commit in commits) {
      sink.writeln(jsonEncode(commit.toJson()));
    }
  } finally {
    sink.close();
  }
}
