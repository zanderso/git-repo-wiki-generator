// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:github/github.dart' as g;

// Add your github token here.
const String githubApiKey = 'ADD YOUR API KEY HERE';

const List<String> flutterRepos = <String>[
  'flutter/flutter',
  'flutter/packages',
  'flutter/cocoon',
  'flutter/flutter-intellij',
  'flutter/devtools',
  'flutter/tests',
  'flutter/website',

  // Excluding these due to massive import and deletion PRs.
  //'flutter/samples',
  //'flutter/demos',
  //'flutter/codelabs',
  //'flutter/ai',
];

const List<String> dartRepos = <String>[
  'dart-lang/ai',
  'dart-lang/sdk',
  'dart-lang/web',
  'dart-lang/source_gen',
  'dart-lang/labs',
  'dart-lang/i18n',
  'dart-lang/pub',
  'dart-lang/setup-dart',
  'dart-lang/webdev',
  'dart-lang/site-www',
  'dart-lang/native',
  'dart-lang/pub-dev',
  'dart-lang/build',
  'dart-lang/dartbug.com',
  'dart-lang/dart-pad',
  'dart-lang/homebrew-dart',
  'dart-lang/mockito',
  'dart-lang/core',
  'dart-lang/tools',
  'dart-lang/sample-pop_pop_win',
  'dart-lang/dart_style',
  'dart-lang/pana',
  'dart-lang/test',
  'dart-lang/dartdoc',
  'dart-lang/ecosystem',
  'dart-lang/flute',
  'dart-lang/dart_ci',
  'dart-lang/dart-docker',
  'dart-lang/repo_manager',
  'dart-lang/site-shared',
  'dart-lang/chocolatey-packages',
  'dart-lang/leak_tracker',
  'dart-lang/http',
  'dart-lang/shelf',
  'dart-lang/grpc_cronet',
  'dart-lang/dart-syntax-highlight',
  'dart-lang/dart-lang.github.io',
];

const List<String> bots = <String>[
  'skia-flutter-autoroll',
  'engine-flutter-autoroll',
  'fluttergithubbot',
  'dependabot[bot]',
  'flutter-pub-roller-bot',
  'auto-submit[bot]',
  'github-actions[bot]',
  'flutteractionsbot',
  'DartDevtoolWorkflowBot',
];

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
    ..addFlag('dart', negatable: false, help: 'Analyze the dart-lang repos', defaultsTo: false)
    ..addOption('members', help: 'Members list file. One github user id per line.')
    ..addOption('output', help: 'Where to write summary CSV data', mandatory: true)
    ..addOption('raw-output', help: 'Where to write raw pull request json data', mandatory: true);
}

void printUsage(ArgParser argParser) {
  print('Usage: dart repo_analysis.dart <flags> [arguments]');
  print(argParser.usage);
}

void main(List<String> arguments) async {
  final ArgParser argParser = buildParser();
  try {
    final ArgResults results = argParser.parse(arguments);
    bool verbose = false;

    // Process the parsed arguments.
    if (results.flag('help')) {
      printUsage(argParser);
      return;
    }
    if (results.flag('verbose')) {
      verbose = true;
    }

    if (verbose) {
      print('[VERBOSE] All arguments: ${results.arguments}');
    }
  
    final Set<String> members;
    if (results.wasParsed('members')) {
      final io.File membersCsvFile = io.File(results.option('members') as String);
      members = findMembers(membersCsvFile);
    } else {
      members = <String>{};
    }
    final io.File outputCsvFile = io.File(results.option('output') as String);
    final io.File rawOutputJson = io.File(results.option('raw-output') as String);
  
    final (Map<String, List<g.RepositoryCommit>>, Map<String, List<g.RepositoryCommit>>) countMaps;
    // Fetch data and write to the file.
    countMaps = await downloadCommitData(
      repos: results.flag('dart') ? dartRepos : flutterRepos,
      memberIDs: members,
      after: DateTime.utc(2025),
    );

    processCommits(countMaps, outputCsvFile, rawOutputJson);

  } on FormatException catch (e) {
    // Print usage information if an invalid argument was provided.
    print(e.message);
    print('');
    printUsage(argParser);
  }
}

void processCommits(
  (Map<String, List<g.RepositoryCommit>>, Map<String, List<g.RepositoryCommit>>) countMaps,
  io.File outputCsvFile,
  io.File rawOutputJson,
) {
  final Map<String, List<g.RepositoryCommit>> memberCommits = countMaps.$1;
  final Map<String, List<g.RepositoryCommit>> externalCommits = countMaps.$2;

  int memberCommitcount = 0;
  int memberAdditions = 0;
  int memberDeletions = 0;
  for (final String id in memberCommits.keys) {
    final List<g.RepositoryCommit> commits = memberCommits[id]!;
    memberCommitcount += commits.length;
    int additions = 0;
    int deletions = 0;
    for (final g.RepositoryCommit commit in commits) {
      if ((commit.stats?.additions ?? 0) > 100000 || (commit.stats?.deletions ?? 0) > 100000) {
        print('LARGE PR: ${commit.htmlUrl} from $id');
      }
      additions += commit.stats?.additions ?? 0;
      deletions += commit.stats?.deletions ?? 0;
    }
    memberAdditions += additions;
    memberDeletions += deletions;
    outputCsvFile.writeAsStringSync(
      '$id,${commits.length},$additions,$deletions\n',
      mode: io.FileMode.append,
      flush: true,
    );
  }

  outputCsvFile.writeAsStringSync(',,,\n', mode: io.FileMode.append, flush: true);

  int externalCommitcount = 0;
  int externalAdditions = 0;
  int externalDeletions = 0;
  for (final String id in externalCommits.keys) {
    final List<g.RepositoryCommit> commits = externalCommits[id]!;
    externalCommitcount += commits.length;
    int additions = 0;
    int deletions = 0;
    for (final g.RepositoryCommit commit in commits) {
      if ((commit.stats?.additions ?? 0) > 100000 || (commit.stats?.deletions ?? 0) > 100000) {
        print('LARGE PR: ${commit.htmlUrl} from $id');
      }
      additions += commit.stats?.additions ?? 0;
      deletions += commit.stats?.deletions ?? 0;
    }
    externalAdditions += additions;
    externalDeletions += deletions;
    outputCsvFile.writeAsStringSync(
      '$id,${commits.length},$additions,$deletions\n',
      mode: io.FileMode.append,
      flush: true,
    );
  }

  print('Members: ${memberCommits.length}');
  print('nonMembers: ${externalCommits.length}');
  print('Member PR count: $memberCommitcount');
  print('nonMember PR count: $externalCommitcount');
  print('Member additions: $memberAdditions');
  print('nonMember additions: $externalAdditions');
  print('Member deletions: $memberDeletions');
  print('nonMember deletions: $externalDeletions');

  final List<Map<String, dynamic>> json = [];
  for (final String id in memberCommits.keys) {
    final List<g.RepositoryCommit> commits = memberCommits[id]!;
    for (final g.RepositoryCommit commit in commits) {
      json.add(commit.toJson());
    }
  }
  for (final String id in externalCommits.keys) {
    final List<g.RepositoryCommit> commits = externalCommits[id]!;
    for (final g.RepositoryCommit commit in commits) {
      json.add(commit.toJson());
    }
  }
  rawOutputJson.writeAsStringSync(jsonEncode(json), flush: true);
}

Set<String> findMembers(io.File membersCsvFile) {
  final Set<String> members = <String>{};
  final List<String> membersLines = membersCsvFile.readAsLinesSync();
  members.addAll(membersLines);
  return members;
}

Future<T> callWithRetries<T>( // ignore: body_might_complete_normally
  Future<T> Function() f, {
  int retries = 5,
}) async {
  int retryCount = 0;
  while (retryCount < retries) {
    try {
      return await f();
    } catch (e) {
      retryCount += 1;
      if (retryCount >= retries) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
  throw Error();
}

// Do not exceed 5000 requests in an hour.
Future<void> pauseForRateLimit(g.GitHub github) async {
  final int? total = github.rateLimitLimit;
  final int? remaining = github.rateLimitRemaining;
  final DateTime? reset = github.rateLimitReset;

  // We won't be able to figure this out without this data, so
  // don't wait. Maybe the data will show up before the next
  // request.
  if (total == null || remaining == null || reset == null) {
    return;
  }

  final Duration timeUntilReset = reset.difference(DateTime.now());

  // Don't exceed `remaining` requests within the `timeUntilReset`
  // duration.
  final int millis = timeUntilReset.inMilliseconds;
  // Evenly divide up the remain time among the remaining quota.
  final double delayInMillis = remaining == 0 ? millis.toDouble() : millis / remaining;
  print('Rate limit: Waiting ${delayInMillis.ceil()} ms. '
        '($remaining/$total) reset in: $timeUntilReset');
  return Future.delayed(Duration(milliseconds: delayInMillis.ceil()));
}

Future<g.RepositoryCommit?> getCommit(
  g.RepositoriesService service,
  String repo,
  String? sha
) async {
  if (sha == null) {
    return null;
  }
  try {
    return await callWithRetries(() async {
      final g.RepositorySlug slug = g.RepositorySlug.full(repo);
      await pauseForRateLimit(service.github);
      return service.getCommit(slug, sha);
    }, retries: 5);
  } catch (e) {
    print('Error: $e');
    return null;
  }
}

Future<List<g.RepositoryCommit>> getCommits(
  g.RepositoriesService service,
  String repo,
  DateTime after,
) async {
  return callWithRetries(() async {
    final List<g.RepositoryCommit> commits = <g.RepositoryCommit>[];
    final g.RepositorySlug slug = g.RepositorySlug.full(repo);
    await pauseForRateLimit(service.github);
    final StreamSubscription<g.RepositoryCommit> sub = service.listCommits(
      slug,
      since: after,
    ).listen(
      (g.RepositoryCommit commit) async {
        commits.add(commit);
      },
    );
    try {
      await sub.asFuture();
    } catch (e) {
      try {
        await sub.cancel();
      } catch (e) {
        // ignore.
      }
      rethrow;
    }
    return commits;
  }, retries: 5);
}

// The first element of the return tuple is the list of commits for each member.
// The second element is the list of commits for each non-member.
Future<(Map<String, List<g.RepositoryCommit>>,
        Map<String, List<g.RepositoryCommit>>)> downloadCommitData({
  required List<String> repos,
  required Set<String> memberIDs,
  required DateTime after,
}) async {
  final g.GitHub github = g.GitHub(
    auth: g.Authentication.withToken(githubApiKey),
  );
  final g.RepositoriesService service = g.RepositoriesService(github);

  final Map<String, List<g.RepositoryCommit>> memberCommits = <String, List<g.RepositoryCommit>>{};
  final Map<String, List<g.RepositoryCommit>> externalCommits = <String, List<g.RepositoryCommit>>{};
  for (final String repo in repos) {
    io.stdout.write('Downloading commit data for "$repo"');
    //await io.stdout.flush();
    final List<g.RepositoryCommit> partialCommits;
    final List<g.RepositoryCommit> commits = [];
    try {
      partialCommits = await getCommits(service, repo, after);
      for (final g.RepositoryCommit commit in partialCommits) {
        final g.RepositoryCommit? fullCommit = await getCommit(service, repo, commit.sha);
        if (fullCommit == null) {
          continue;
        }
        commits.add(fullCommit);
      }
    } catch (e) {
      print('\nFailed to get commits for $repo: Error: $e');
      print(
        '\nrateLimitLimit: ${github.rateLimitLimit} '
        'rateLimitRemaining: ${github.rateLimitRemaining} '
        'rateLimitReset: ${github.rateLimitReset!.toLocal()}',
      );
      break;
    }
    for (final g.RepositoryCommit commit in commits) {
      if (commit.author == null || commit.author!.login == null) {
        continue;
      }

      final String id = commit.author!.login!;
      if (bots.contains(id)) {
        continue;
      }

      if (memberIDs.contains(id)) {
        memberCommits.update(
          id,
          (List<g.RepositoryCommit> l) => l..add(commit),
          ifAbsent: () => <g.RepositoryCommit>[commit],
        );
      } else {
        externalCommits.update(
          id,
          (List<g.RepositoryCommit> l) => l..add(commit),
          ifAbsent: () => <g.RepositoryCommit>[commit],
        );
      }
    }
    io.stdout.write(': Done.\n');
    // Vague attempt to avoid rate limiting.
    await Future.delayed(const Duration(minutes: 1));
  }

  return (memberCommits, externalCommits);
}
