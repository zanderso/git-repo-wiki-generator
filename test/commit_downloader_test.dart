// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'package:test/test.dart';
import 'package:test/fake.dart';
import 'package:github/github.dart' as g;
import 'package:git_repo_wiki_generator/commit_downloader.dart';
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

class FakeRepositoriesService extends Fake implements g.RepositoriesService {
  final List<g.RepositoryCommit> Function(
    g.RepositorySlug slug,
    DateTime since,
    DateTime until,
  )
  onListCommits;
  final g.RepositoryCommit Function(g.RepositorySlug slug, String sha)
  onGetCommit;
  final g.GitHub _github;

  FakeRepositoriesService({
    required g.GitHub github,
    required this.onListCommits,
    required this.onGetCommit,
  }) : _github = github;

  @override
  g.GitHub get github => _github;

  @override
  Stream<g.RepositoryCommit> listCommits(
    g.RepositorySlug slug, {
    String? sha,
    String? path,
    String? author,
    String? committer,
    DateTime? since,
    DateTime? until,
  }) {
    final commits = onListCommits(slug, since!, until!);
    return Stream.fromIterable(commits);
  }

  @override
  Future<g.RepositoryCommit> getCommit(
    g.RepositorySlug slug,
    String sha,
  ) async {
    return onGetCommit(slug, sha);
  }
}

void main() {
  group('CommitDownloader', () {
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

    test('downloads commits and filters out bots', () async {
      final fakeGithub = FakeGitHub(
        rateLimitLimit: 5000,
        rateLimitRemaining: 4999,
        rateLimitReset: DateTime.now().add(const Duration(hours: 1)),
      );

      final mockCommits = [
        g.RepositoryCommit.fromJson({
          'sha': 'sha_user',
          'author': {'login': 'dev_user'},
          'commit': {
            'message': 'regular commit',
            'author': {
              'name': 'Dev User',
              'email': 'dev@example.com',
              'date': '2026-06-15T10:00:00Z',
            },
          },
        }),
        g.RepositoryCommit.fromJson({
          'sha': 'sha_bot',
          'author': {'login': 'dependabot[bot]'},
          'commit': {
            'message': 'dependency bump',
            'author': {
              'name': 'Dependabot',
              'email': 'bot@example.com',
              'date': '2026-06-16T10:00:00Z',
            },
          },
        }),
      ];

      final fakeService = FakeRepositoriesService(
        github: fakeGithub,
        onListCommits: (slug, since, until) {
          expect(slug.fullName, equals('owner/repo'));
          return mockCommits;
        },
        onGetCommit: (slug, sha) {
          return mockCommits.firstWhere((c) => c.sha == sha);
        },
      );

      final downloader = CommitDownloader(
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

      final result = await downloader.downloadCommitData(config!);

      // Verify bots are filtered out
      expect(result.length, equals(1));
      expect(result[0].sha, equals('sha_user'));
      expect(result[0].author?.login, equals('dev_user'));

      // Check log output
      expect(
        logs,
        anyElement(contains('Downloading commit data for "owner/repo"')),
      );
      expect(logs, anyElement(contains('Got all commit data')));
    });

    test('handles exceptions by logging and returning empty', () async {
      final fakeGithub = FakeGitHub();
      final fakeService = FakeRepositoriesService(
        github: fakeGithub,
        onListCommits: (slug, since, until) {
          throw Exception('API error');
        },
        onGetCommit: (slug, sha) {
          fail('Should not be called');
        },
      );

      final downloader = CommitDownloader(
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
      final result = await downloader.downloadCommitData(config!);

      expect(result, isEmpty);
      expect(
        logs,
        anyElement(
          contains(
            'Failed to get commits for owner/repo: Error: Exception: API error',
          ),
        ),
      );
    });

    test('handles rate limit pausing correctly', () async {
      final resetTime = DateTime.now().add(const Duration(minutes: 30));
      final fakeGithub = FakeGitHub(
        rateLimitLimit: 100,
        rateLimitRemaining: 5,
        rateLimitReset: resetTime,
      );

      final fakeService = FakeRepositoriesService(
        github: fakeGithub,
        onListCommits: (slug, since, until) => [],
        onGetCommit: (slug, sha) => fail('no commits'),
      );

      final downloader = CommitDownloader(
        github: fakeGithub,
        service: fakeService,
        log: testLog,
        delay: testDelay,
      );

      // Trigger rate limit check with more remainingRequests (e.g. 10) than remainingQuota (5)
      await downloader.pauseForRateLimit(10);

      expect(delays.length, equals(1));
      expect(delays[0].inMilliseconds, greaterThan(0));
      expect(logs, anyElement(contains('Rate limit: Waiting')));
    });
  });
}
