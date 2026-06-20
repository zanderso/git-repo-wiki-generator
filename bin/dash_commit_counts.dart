// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:github/github.dart' as g;
import 'package:repo_analysis/config.dart';
import 'package:repo_analysis/utils.dart';



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

    final List<g.RepositoryCommit> commits = await downloadCommitData(config);

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


// Do not exceed 5000 requests in an hour.
Future<void> pauseForRateLimit(
  g.GitHub github, [
  int? remainingRequests,
]) async {
  final int? total = github.rateLimitLimit;
  final int? remainingQuota = github.rateLimitRemaining;
  final DateTime? reset = github.rateLimitReset;

  // We won't be able to figure this out without this data, so
  // don't wait. Maybe the data will show up before the next
  // request.
  if (total == null || remainingQuota == null || reset == null) {
    return;
  }

  // If the remaining requests are fewer than the remaining quota
  // then don't wait.
  if (remainingRequests != null && remainingRequests < remainingQuota) {
    return;
  }

  final Duration timeUntilReset = reset.difference(DateTime.now());
  if (timeUntilReset.isNegative) {
    // If the time until reset is in the past, then don't wait.
    return;
  }

  // Don't exceed `remaining` requests within the `timeUntilReset`
  // duration.
  final int millis = timeUntilReset.inMilliseconds;
  // Evenly divide up the remain time among the remaining quota.
  final double delayInMillis = remainingQuota == 0
      ? millis.toDouble()
      : millis / remainingQuota;
  if (delayInMillis < 1.0) {
    // If the delay is less than a millisecond, then don't wait.
    return;
  }

  print(
    'Rate limit: Waiting ${delayInMillis.ceil()} ms. '
    '($remainingQuota/$total) reset in: $timeUntilReset',
  );
  return Future.delayed(Duration(milliseconds: delayInMillis.ceil()));
}

Future<g.RepositoryCommit?> getCommit(
  g.RepositoriesService service,
  String repo,
  String? sha, {
  int? remainingRequests,
}) async {
  if (sha == null) {
    return null;
  }
  try {
    return await callWithRetries(() async {
      final g.RepositorySlug slug = g.RepositorySlug.full(repo);
      await pauseForRateLimit(service.github, remainingRequests);
      if (_verbose) {
        print('[VERBOSE] getting $sha from $repo');
      }
      return service.getCommit(slug, sha);
    }, retries: 5);
  } catch (e) {
    print('Failed to get commit: Error: $e');
    return null;
  }
}

Future<List<g.RepositoryCommit>> getCommits(
  g.RepositoriesService service,
  String repo,
  DateTime after,
  DateTime before, {
  int? remainingRequests,
}) async {
  return callWithRetries(() async {
    final List<g.RepositoryCommit> commits = <g.RepositoryCommit>[];
    final g.RepositorySlug slug = g.RepositorySlug.full(repo);
    await pauseForRateLimit(service.github, remainingRequests);
    if (_verbose) {
      print('[VERBOSE] Listing commits of $repo');
    }
    final stream = service.listCommits(slug, since: after, until: before);
    await for (final commit in stream) {
      commits.add(commit);
    }
    if (_verbose) {
      print('[VERBOSE] commit list stream for $repo completed');
    }
    return commits;
  }, retries: 5);
}

Future<List<g.RepositoryCommit>> downloadCommitData(Config config) async {
  final g.GitHub github = g.GitHub(
    auth: g.Authentication.withToken(config.token),
  );
  final g.RepositoriesService service = g.RepositoriesService(github);

  // Get all the partial commits for all the repos before requesting the complete data.
  final Map<String, List<g.RepositoryCommit>> partialCommits = {};
  for (final String repo in config.repos) {
    io.stdout.write('Downloading commit data for "$repo"\n');
    try {
      partialCommits[repo] = await getCommits(
        service,
        repo,
        config.since,
        config.until,
      );
    } catch (e) {
      print('\nFailed to get commits for $repo: Error: $e');
      print(
        '\nrateLimitLimit: ${github.rateLimitLimit} '
        '\nrateLimitRemaining: ${github.rateLimitRemaining} '
        '\nrateLimitReset: ${github.rateLimitReset!.toLocal()}',
      );
      return <g.RepositoryCommit>[];
    }
  }

  final List<g.RepositoryCommit> fullCommits = [];
  final int commitCount = partialCommits.values.fold(0, (c, l) => c + l.length);
  if (_verbose) {
    print('[VERBOSE] Downloading full data for $commitCount commits');
  }
  for (final MapEntry(key: repo, value: repoCommits)
      in partialCommits.entries) {
    if (_verbose) {
      print('[VERBOSE] ${commitCount - fullCommits.length} commits remaining.');
    }
    for (final commit in repoCommits) {
      final int remainingCommits = commitCount - fullCommits.length;
      final g.RepositoryCommit? fullCommit = await getCommit(
        service,
        repo,
        commit.sha,
        remainingRequests: remainingCommits,
      );
      if (fullCommit == null) {
        continue;
      }
      fullCommits.add(fullCommit);
    }
  }

  if (_verbose) {
    print('[VERBOSE] Got all commit data');
  }

  return fullCommits.where((g.RepositoryCommit commit) {
    if (commit.author == null) {
      print('***\nCommit without author!\n***\n$commit');
      return false;
    }
    final String id = commit.author!.login!;
    return !config.bots.contains(id);
  }).toList();
}
