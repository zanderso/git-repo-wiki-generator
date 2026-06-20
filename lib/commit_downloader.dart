// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'package:github/github.dart' as g;
import 'package:git_repo_wiki_generator/config.dart';
import 'package:git_repo_wiki_generator/utils.dart';

/// A class responsible for downloading and filtering commit data from GitHub.
class CommitDownloader {
  final g.GitHub github;
  final g.RepositoriesService service;
  final bool verbose;
  final void Function(String) log;
  final Future<void> Function(Duration) delay;

  CommitDownloader({
    required this.github,
    g.RepositoriesService? service,
    this.verbose = false,
    void Function(String)? log,
    Future<void> Function(Duration)? delay,
  })  : service = service ?? g.RepositoriesService(github),
        log = log ?? print,
        delay = delay ?? Future.delayed;

  /// Do not exceed 5000 requests in an hour.
  Future<void> pauseForRateLimit([int? remainingRequests]) async {
    final int? total = github.rateLimitLimit;
    final int? remainingQuota = github.rateLimitRemaining;
    final DateTime? reset = github.rateLimitReset;

    // We won't be able to figure this out without this data, so
    // don't wait. Maybe the data will show up before the next request.
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

    // Don't exceed `remaining` requests within the `timeUntilReset` duration.
    final int millis = timeUntilReset.inMilliseconds;
    // Evenly divide up the remaining time among the remaining quota.
    final double delayInMillis = remainingQuota == 0
        ? millis.toDouble()
        : millis / remainingQuota;
    if (delayInMillis < 1.0) {
      // If the delay is less than a millisecond, then don't wait.
      return;
    }

    log(
      'Rate limit: Waiting ${delayInMillis.ceil()} ms. '
      '($remainingQuota/$total) reset in: $timeUntilReset',
    );
    await delay(Duration(milliseconds: delayInMillis.ceil()));
  }

  /// Fetches a single commit with full details (including diffs/files).
  Future<g.RepositoryCommit?> getCommit(
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
        await pauseForRateLimit(remainingRequests);
        if (verbose) {
          log('[VERBOSE] getting $sha from $repo');
        }
        return await service.getCommit(slug, sha);
      }, retries: 5);
    } catch (e) {
      log('Failed to get commit: Error: $e');
      return null;
    }
  }

  /// Fetches all partial commits for a given repository within the date range.
  Future<List<g.RepositoryCommit>> getCommits(
    String repo,
    DateTime after,
    DateTime before, {
    int? remainingRequests,
  }) async {
    return callWithRetries(() async {
      final List<g.RepositoryCommit> commits = <g.RepositoryCommit>[];
      final g.RepositorySlug slug = g.RepositorySlug.full(repo);
      await pauseForRateLimit(remainingRequests);
      if (verbose) {
        log('[VERBOSE] Listing commits of $repo');
      }
      final stream = service.listCommits(slug, since: after, until: before);
      await for (final commit in stream) {
        commits.add(commit);
      }
      if (verbose) {
        log('[VERBOSE] commit list stream for $repo completed');
      }
      return commits;
    }, retries: 5);
  }

  /// Downloads commits across all configured repositories and filters out bots.
  Future<List<g.RepositoryCommit>> downloadCommitData(Config config) async {
    // Get all the partial commits for all the repos before requesting the complete data.
    final Map<String, List<g.RepositoryCommit>> partialCommits = {};
    for (final String repo in config.repos) {
      log('Downloading commit data for "$repo"\n');
      try {
        partialCommits[repo] = await getCommits(
          repo,
          config.since,
          config.until,
        );
      } catch (e) {
        log('\nFailed to get commits for $repo: Error: $e');
        log(
          '\nrateLimitLimit: ${github.rateLimitLimit} '
          '\nrateLimitRemaining: ${github.rateLimitRemaining} '
          '\nrateLimitReset: ${github.rateLimitReset?.toLocal()}',
        );
        return <g.RepositoryCommit>[];
      }
    }

    final List<g.RepositoryCommit> fullCommits = [];
    final int commitCount = partialCommits.values.fold(0, (c, l) => c + l.length);
    if (verbose) {
      log('[VERBOSE] Downloading full data for $commitCount commits');
    }
    for (final MapEntry(key: repo, value: repoCommits)
        in partialCommits.entries) {
      if (verbose) {
        log('[VERBOSE] ${commitCount - fullCommits.length} commits remaining.');
      }
      for (final commit in repoCommits) {
        final int remainingCommits = commitCount - fullCommits.length;
        final g.RepositoryCommit? fullCommit = await getCommit(
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

    if (verbose) {
      log('[VERBOSE] Got all commit data');
    }

    return fullCommits.where((g.RepositoryCommit commit) {
      if (commit.author == null) {
        log('***\nCommit without author!\n***\n$commit');
        return false;
      }
      final String id = commit.author!.login!;
      return !config.bots.contains(id);
    }).toList();
  }
}
