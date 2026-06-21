// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'package:github/github.dart' as g;
import 'package:git_repo_wiki_generator/config.dart';
import 'package:git_repo_wiki_generator/utils.dart';

/// A structured container that aggregates a Pull Request, its review comments, and formal reviews.
class PullRequestData {
  final g.PullRequest pullRequest;
  final List<g.PullRequestComment> comments;
  final List<g.PullRequestReview> reviews;

  PullRequestData({
    required this.pullRequest,
    required this.comments,
    required this.reviews,
  });

  Map<String, dynamic> toJson() {
    return {
      'pull_request': pullRequest.toJson(),
      'comments': comments.map((c) => c.toJson()).toList(),
      'reviews': reviews.map((r) => r.toJson()).toList(),
    };
  }
}

/// A class responsible for downloading and aggregating pull request data (including reviews and review comments).
class PRDownloader {
  final g.GitHub github;
  final g.PullRequestsService service;
  final bool verbose;
  final void Function(String) log;
  final Future<void> Function(Duration) delay;

  PRDownloader({
    required this.github,
    g.PullRequestsService? service,
    this.verbose = false,
    void Function(String)? log,
    Future<void> Function(Duration)? delay,
  }) : service = service ?? g.PullRequestsService(github),
       log = log ?? print,
       delay = delay ?? Future.delayed;

  /// Do not exceed 5000 requests in an hour.
  Future<void> pauseForRateLimit([int? remainingRequests]) async {
    final int? total = github.rateLimitLimit;
    final int? remainingQuota = github.rateLimitRemaining;
    final DateTime? reset = github.rateLimitReset;

    if (total == null || remainingQuota == null || reset == null) {
      return;
    }

    if (remainingRequests != null && remainingRequests < remainingQuota) {
      return;
    }

    final Duration timeUntilReset = reset.difference(DateTime.now());
    if (timeUntilReset.isNegative) {
      return;
    }

    final int millis = timeUntilReset.inMilliseconds;
    final double delayInMillis = remainingQuota == 0
        ? millis.toDouble()
        : millis / remainingQuota;
    if (delayInMillis < 1.0) {
      return;
    }

    log(
      'Rate limit: Waiting ${delayInMillis.ceil()} ms. '
      '($remainingQuota/$total) reset in: $timeUntilReset',
    );
    await delay(Duration(milliseconds: delayInMillis.ceil()));
  }

  /// Lists all pull requests in a given repository.
  Future<List<g.PullRequest>> getPullRequests(
    String repo, {
    String state = 'all',
  }) async {
    return callWithRetries(() async {
      final List<g.PullRequest> prs = [];
      final g.RepositorySlug slug = g.RepositorySlug.full(repo);
      await pauseForRateLimit();
      if (verbose) {
        log('[VERBOSE] Listing pull requests for $repo');
      }
      final Stream<g.PullRequest> stream = service.list(slug, state: state);
      await for (final pr in stream) {
        prs.add(pr);
      }
      return prs;
    }, retries: 5);
  }

  /// Lists review comments on a specific pull request.
  Future<List<g.PullRequestComment>> getPRComments(
    String repo,
    int prNumber,
  ) async {
    return callWithRetries(() async {
      final List<g.PullRequestComment> comments = [];
      final g.RepositorySlug slug = g.RepositorySlug.full(repo);
      await pauseForRateLimit();
      if (verbose) {
        log('[VERBOSE] Listing comments for PR $prNumber in $repo');
      }
      final Stream<g.PullRequestComment> stream = service
          .listCommentsByPullRequest(slug, prNumber);
      await for (final comment in stream) {
        comments.add(comment);
      }
      return comments;
    }, retries: 5);
  }

  /// Lists formal reviews on a specific pull request.
  Future<List<g.PullRequestReview>> getPRReviews(
    String repo,
    int prNumber,
  ) async {
    return callWithRetries(() async {
      final List<g.PullRequestReview> reviews = [];
      final g.RepositorySlug slug = g.RepositorySlug.full(repo);
      await pauseForRateLimit();
      if (verbose) {
        log('[VERBOSE] Listing reviews for PR $prNumber in $repo');
      }
      final Stream<g.PullRequestReview> stream = service.listReviews(
        slug,
        prNumber,
      );
      await for (final review in stream) {
        reviews.add(review);
      }
      return reviews;
    }, retries: 5);
  }

  /// Downloads pull request data across all configured repositories,
  /// filters them by the date range, and excludes bot accounts.
  Future<List<PullRequestData>> downloadPRData(Config config) async {
    final List<PullRequestData> results = [];

    for (final String repo in config.repos) {
      log('Downloading pull request data for "$repo"\n');
      try {
        final List<g.PullRequest> prs = await getPullRequests(repo);

        final filteredPrs = prs.where((pr) {
          if (pr.mergedAt == null) return false;
          final merged = pr.mergedAt!;
          return merged.isAfter(config.since) && merged.isBefore(config.until);
        }).toList();

        if (verbose) {
          log(
            '[VERBOSE] Found ${filteredPrs.length} PRs in date range for $repo',
          );
        }

        for (final pr in filteredPrs) {
          final int? prNumber = pr.number;
          if (prNumber == null) continue;

          final comments = await getPRComments(repo, prNumber);
          final reviews = await getPRReviews(repo, prNumber);

          results.add(
            PullRequestData(
              pullRequest: pr,
              comments: comments,
              reviews: reviews,
            ),
          );
        }
      } catch (e, st) {
        log('\nFailed to get pull requests for $repo:\nError: $e\n$st');
        log(
          '\nrateLimitLimit: ${github.rateLimitLimit} '
          '\nrateLimitRemaining: ${github.rateLimitRemaining} '
          '\nrateLimitReset: ${github.rateLimitReset?.toLocal()}',
        );
      }
    }

    return results.where((PullRequestData data) {
      if (data.pullRequest.user == null) {
        return false;
      }
      final String id = data.pullRequest.user!.login!;
      return !config.bots.contains(id);
    }).toList();
  }
}
