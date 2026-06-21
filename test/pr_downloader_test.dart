// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'package:test/test.dart';
import 'package:test/fake.dart';
import 'package:github/github.dart' as g;
import 'package:git_repo_wiki_generator/pr_downloader.dart';
import 'package:git_repo_wiki_generator/config.dart';

class FakeGitHub extends Fake implements g.GitHub {
  @override
  int? rateLimitLimit;

  @override
  int? rateLimitRemaining;

  @override
  DateTime? rateLimitReset;

  FakeGitHub({
    this.rateLimitLimit,
    this.rateLimitRemaining,
    this.rateLimitReset,
  });
}

class FakePullRequestsService extends Fake implements g.PullRequestsService {
  final List<g.PullRequest> Function(g.RepositorySlug slug, String state)
  onListPRs;
  final List<g.PullRequestComment> Function(g.RepositorySlug slug, int number)
  onListComments;
  final List<g.PullRequestReview> Function(g.RepositorySlug slug, int number)
  onListReviews;
  final g.GitHub _github;

  FakePullRequestsService({
    required g.GitHub github,
    required this.onListPRs,
    required this.onListComments,
    required this.onListReviews,
  }) : _github = github;

  @override
  g.GitHub get github => _github;

  @override
  Stream<g.PullRequest> list(
    g.RepositorySlug slug, {
    int? pages,
    String? base,
    String direction = 'desc',
    String? head,
    String sort = 'created',
    String state = 'open',
  }) {
    return Stream.fromIterable(onListPRs(slug, state));
  }

  @override
  Stream<g.PullRequestComment> listCommentsByPullRequest(
    g.RepositorySlug slug,
    int number,
  ) {
    return Stream.fromIterable(onListComments(slug, number));
  }

  @override
  Stream<g.PullRequestReview> listReviews(g.RepositorySlug slug, int number) {
    return Stream.fromIterable(onListReviews(slug, number));
  }
}

void main() {
  group('PRDownloader', () {
    late List<String> logs;
    late List<Duration> delays;

    void testLog(String message) {
      logs.add(message);
    }

    Future<void> testDelay(Duration duration) async {
      delays.add(duration);
    }

    setUp(() {
      logs = [];
      delays = [];
    });

    test(
      'downloads PRs, comments, reviews, and filters by date and bots',
      () async {
        final fakeGithub = FakeGitHub(
          rateLimitLimit: 5000,
          rateLimitRemaining: 4999,
          rateLimitReset: DateTime.now().add(const Duration(hours: 1)),
        );

        final prs = [
          g.PullRequest.fromJson({
            'number': 101,
            'title': 'Add PR Downloader Feature',
            'state': 'closed',
            'created_at': '2026-06-15T12:00:00Z',
            'merged_at': '2026-06-15T12:00:00Z',
            'user': {'login': 'dev_user'},
          }),
          g.PullRequest.fromJson({
            'number': 102,
            'title': 'Bot PR',
            'state': 'open',
            'created_at': '2026-06-16T12:00:00Z',
            'merged_at': '2026-06-16T12:00:00Z',
            'user': {'login': 'dependabot[bot]'},
          }),
          g.PullRequest.fromJson({
            'number': 103,
            'title': 'Out of range PR',
            'state': 'open',
            'created_at': '2026-06-01T12:00:00Z',
            'merged_at': '2026-06-01T12:00:00Z',
            'user': {'login': 'dev_user'},
          }),
          g.PullRequest.fromJson({
            'number': 104,
            'title': 'Unmerged PR',
            'state': 'open',
            'created_at': '2026-06-15T12:00:00Z',
            'user': {'login': 'dev_user'},
          }),
        ];

        final comments = [
          g.PullRequestComment.fromJson({
            'id': 1,
            'body': 'Great change!',
            'path': 'lib/pr_downloader.dart',
          }),
        ];

        final reviews = [
          g.PullRequestReview.fromJson({
            'id': 2,
            'state': 'APPROVED',
            'user': {'login': 'reviewer_user'},
          }),
        ];

        final fakeService = FakePullRequestsService(
          github: fakeGithub,
          onListPRs: (slug, state) {
            expect(slug.fullName, equals('owner/repo'));
            return prs;
          },
          onListComments: (slug, number) {
            expect(number, equals(101));
            return comments;
          },
          onListReviews: (slug, number) {
            expect(number, equals(101));
            return reviews;
          },
        );

        final downloader = PRDownloader(
          github: fakeGithub,
          service: fakeService,
          verbose: true,
          log: testLog,
          delay: testDelay,
        );

        final configMap = {
          'token': 'test_token',
          'since': '2026-06-13T00:00:00Z',
          'until': '2026-06-19T23:59:59Z',
          'repos': ['owner/repo'],
          'bots': ['dependabot[bot]'],
        };

        final (config, err) = Config.fromMap(configMap);
        expect(err, isNull);
        expect(config, isNotNull);

        final result = await downloader.downloadPRData(config!);

        // Should only contain PR 101 because:
        // - PR 102 is by a bot
        // - PR 103 is out of the date range (since 2026-06-13, until 2026-06-19)
        // - PR 104 is unmerged (no merged_at)
        expect(result.length, equals(1));
        expect(result[0].pullRequest.number, equals(101));
        expect(result[0].pullRequest.user?.login, equals('dev_user'));
        expect(result[0].comments.length, equals(1));
        expect(result[0].comments[0].body, equals('Great change!'));
        expect(result[0].reviews.length, equals(1));
        expect(result[0].reviews[0].state, equals('APPROVED'));

        expect(
          logs,
          anyElement(
            contains('Downloading pull request data for "owner/repo"'),
          ),
        );
      },
    );

    test('handles exceptions by logging and returning empty', () async {
      final fakeGithub = FakeGitHub();
      final fakeService = FakePullRequestsService(
        github: fakeGithub,
        onListPRs: (slug, state) {
          throw Exception('Pulls API failure');
        },
        onListComments: (slug, number) => fail('no comments'),
        onListReviews: (slug, number) => fail('no reviews'),
      );

      final downloader = PRDownloader(
        github: fakeGithub,
        service: fakeService,
        log: testLog,
        delay: testDelay,
      );

      final configMap = {
        'token': 'test_token',
        'since': '2026-06-13T00:00:00Z',
        'until': '2026-06-19T23:59:59Z',
        'repos': ['owner/repo'],
        'bots': ['bot'],
      };

      final (config, err) = Config.fromMap(configMap);
      final result = await downloader.downloadPRData(config!);

      expect(result, isEmpty);
      expect(
        logs,
        anyElement(
          contains(
            'Failed to get pull requests for owner/repo:\nError: Exception: Pulls API failure',
          ),
        ),
      );
    });

    test('handles rate limiting pausing correctly', () async {
      final resetTime = DateTime.now().add(const Duration(minutes: 15));
      final fakeGithub = FakeGitHub(
        rateLimitLimit: 100,
        rateLimitRemaining: 2,
        rateLimitReset: resetTime,
      );

      final fakeService = FakePullRequestsService(
        github: fakeGithub,
        onListPRs: (slug, state) => [],
        onListComments: (slug, number) => [],
        onListReviews: (slug, number) => [],
      );

      final downloader = PRDownloader(
        github: fakeGithub,
        service: fakeService,
        log: testLog,
        delay: testDelay,
      );

      await downloader.pauseForRateLimit(5);

      expect(delays.length, equals(1));
      expect(delays[0].inMilliseconds, greaterThan(0));
      expect(logs, anyElement(contains('Rate limit: Waiting')));
    });
  });
}
