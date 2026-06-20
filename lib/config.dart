// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io' as io;

class Config {
  Config._({
    required this.token,
    required this.repos,
    required this.bots,
    required this.since,
    required this.until,
  });

  /// Parses configuration from a JSON map.
  static (Config?, String?) fromMap(Map<String, dynamic> configData) {
    final token = configData[tokenKey];
    if (token is! String || token.isEmpty) {
      return (null, '"token" field must be a non-empty string.');
    }

    final sinceStr = configData[sinceKey];
    if (sinceStr is! String || sinceStr.isEmpty) {
      return (null, '"since" field must be a non-empty string.');
    }
    final DateTime since;
    try {
      since = DateTime.parse(sinceStr);
    } on FormatException catch (e) {
      return (null, '$sinceStr is not a valid date string: $e');
    }

    final untilStr = configData[untilKey];
    if (untilStr is! String || untilStr.isEmpty) {
      return (null, '"until" field must be a non-empty string.');
    }
    final DateTime until;
    try {
      until = DateTime.parse(untilStr);
    } on FormatException catch (e) {
      return (null, '$untilStr is not a valid date string: $e');
    }

    final reposRaw = configData[reposKey];
    if (reposRaw is! List || reposRaw.isEmpty) {
      return (null, '"repos" field must be a non-empty list of strings.');
    }
    if (reposRaw.any((e) => e is! String)) {
      return (null, '"repos" field must be a non-empty list of strings.');
    }
    final List<String> repos = List<String>.from(reposRaw);

    final botsRaw = configData[botsKey];
    if (botsRaw is! List || botsRaw.isEmpty) {
      return (null, '"bots" field must be a non-empty list of strings.');
    }
    if (botsRaw.any((e) => e is! String)) {
      return (null, '"bots" field must be a non-empty list of strings.');
    }
    final List<String> bots = List<String>.from(botsRaw);

    return (
      Config._(
        token: token,
        since: since,
        until: until,
        repos: repos,
        bots: bots,
      ),
      null,
    );
  }

  /// Parses configuration from a JSON string.
  static (Config?, String?) fromJson(String jsonStr) {
    try {
      final configData = json.decode(jsonStr);
      if (configData is! Map<String, dynamic>) {
        return (null, 'Root of JSON configuration must be a map.');
      }
      return fromMap(configData);
    } on FormatException catch (e) {
      return (null, 'Not valid json: $e');
    }
  }

  /// Parses configuration from a file path.
  static (Config?, String?) fromFile(String path) {
    final io.File configFile = io.File(path);
    final String content;
    try {
      content = configFile.readAsStringSync();
    } catch (e) {
      return (null, 'Failed to read file $path: $e');
    }

    try {
      final configData = json.decode(content);
      if (configData is! Map<String, dynamic>) {
        return (
          null,
          '$path is not valid json: Root of JSON configuration must be a map.',
        );
      }
      final (config, err) = fromMap(configData);
      if (err != null) {
        return (null, err);
      }
      return (config, null);
    } on FormatException catch (e) {
      return (null, '$path is not valid json: $e');
    }
  }

  final String token;
  final List<String> repos;
  final List<String> bots;
  final DateTime since;
  final DateTime until;

  static const String tokenKey = 'token';
  static const String sinceKey = 'since';
  static const String untilKey = 'until';
  static const String reposKey = 'repos';
  static const String botsKey = 'bots';

  @override
  String toString() {
    return 'Config($token, $repos, $bots, $since, $until)';
  }
}
