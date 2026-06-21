// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: constant_identifier_names

import 'dart:io' as io;

const Map<String, String> MONTH_NAMES = {
  '01': 'January',
  '02': 'February',
  '03': 'March',
  '04': 'April',
  '05': 'May',
  '06': 'June',
  '07': 'July',
  '08': 'August',
  '09': 'September',
  '10': 'October',
  '11': 'November',
  '12': 'December',
};

class ParsedCommit {
  final String hash;
  final String name;
  final String email;
  final String date;
  final String message;
  final String login;
  final int additions;
  final int deletions;
  final List<String> filenames;
  String monthYear = 'Unknown';
  List<String> components = const [];

  ParsedCommit({
    required this.hash,
    required this.name,
    required this.email,
    required this.date,
    required this.message,
    required this.login,
    required this.additions,
    required this.deletions,
    required this.filenames,
  });
}

class ParsedReviewOrComment {
  final String authorLogin;
  final String body;
  final bool isReview;

  ParsedReviewOrComment({
    required this.authorLogin,
    required this.body,
    required this.isReview,
  });
}

class ParsedPr {
  final String mergeCommitSha;
  final String title;
  final String authorLogin;
  final List<ParsedReviewOrComment> reviewsAndComments;

  ParsedPr({
    required this.mergeCommitSha,
    required this.title,
    required this.authorLogin,
    required this.reviewsAndComments,
  });
}

class TempContrib {
  String? login;
  String? body;
  final bool isReview;
  TempContrib(this.isReview);
}

ParsedPr parsePrFile(io.File file) {
  final lines = file.readAsLinesSync();
  String prMergeCommitSha = '';
  String prTitle = '';
  String prAuthorLogin = '';
  final List<ParsedReviewOrComment> reviewsAndComments = [];

  String currentSection = '';
  String currentField = '';
  TempContrib? temp;

  bool insideCodeBlock = false;
  StringBuffer codeBlockContent = StringBuffer();

  for (final line in lines) {
    final trimmed = line.trim();

    if (trimmed.startsWith('```')) {
      insideCodeBlock = !insideCodeBlock;
      if (insideCodeBlock) {
        codeBlockContent.clear();
      } else {
        final content = codeBlockContent.toString().trim();
        if (currentSection == 'pull_request') {
          if (currentField == 'title') {
            prTitle = content;
          } else if (currentField == 'merge_commit_sha') {
            prMergeCommitSha = content;
          } else if (currentField == 'user.login') {
            prAuthorLogin = content;
          }
        } else if (currentSection == 'comments' && temp != null) {
          if (currentField == 'comment.user.login') {
            temp.login = content;
          } else if (currentField == 'comment.body') {
            temp.body = content;
          }
        } else if (currentSection == 'reviews' && temp != null) {
          if (currentField == 'review.user.login') {
            temp.login = content;
          } else if (currentField == 'review.body') {
            temp.body = content;
          }
        }
      }
      continue;
    }

    if (insideCodeBlock) {
      codeBlockContent.writeln(line);
      continue;
    }

    if (trimmed.startsWith('# ')) {
      currentSection = trimmed.substring(2).trim();
      currentField = '';
    } else if (trimmed.startsWith('## ')) {
      final header = trimmed.substring(3).trim();
      if (currentSection == 'pull_request') {
        currentField = header;
      } else if (currentSection == 'comments' && header == 'comments') {
        if (temp != null && temp.login != null) {
          reviewsAndComments.add(
            ParsedReviewOrComment(
              authorLogin: temp.login!,
              body: temp.body ?? '',
              isReview: temp.isReview,
            ),
          );
        }
        temp = TempContrib(false);
        currentField = '';
      } else if (currentSection == 'reviews' && header == 'reviews') {
        if (temp != null && temp.login != null) {
          reviewsAndComments.add(
            ParsedReviewOrComment(
              authorLogin: temp.login!,
              body: temp.body ?? '',
              isReview: temp.isReview,
            ),
          );
        }
        temp = TempContrib(true);
        currentField = '';
      }
    } else if (trimmed.startsWith('### ')) {
      final header = trimmed.substring(4).trim();
      if (currentSection == 'pull_request' &&
          currentField == 'user' &&
          header == 'login') {
        currentField = 'user.login';
      } else if (currentSection == 'comments' && temp != null) {
        if (header == 'user') {
          currentField = 'comment.user';
        } else if (header == 'body') {
          currentField = 'comment.body';
        }
      } else if (currentSection == 'reviews' && temp != null) {
        if (header == 'user') {
          currentField = 'review.user';
        } else if (header == 'body') {
          currentField = 'review.body';
        }
      }
    } else if (trimmed.startsWith('#### ')) {
      final header = trimmed.substring(5).trim();
      if (currentSection == 'comments' &&
          currentField == 'comment.user' &&
          header == 'login') {
        currentField = 'comment.user.login';
      } else if (currentSection == 'reviews' &&
          currentField == 'review.user' &&
          header == 'login') {
        currentField = 'review.user.login';
      }
    }
  }

  // Handle last pending item
  if (temp != null && temp.login != null) {
    reviewsAndComments.add(
      ParsedReviewOrComment(
        authorLogin: temp.login!,
        body: temp.body ?? '',
        isReview: temp.isReview,
      ),
    );
  }

  return ParsedPr(
    mergeCommitSha: prMergeCommitSha,
    title: prTitle,
    authorLogin: prAuthorLogin,
    reviewsAndComments: reviewsAndComments,
  );
}

class AuthorCodeReviewContribution {
  final String date;
  final String prTitle;
  final String prAuthorName;
  final String contributionType;
  final String prFileCitation;
  final String mergeCommitSha;

  AuthorCodeReviewContribution({
    required this.date,
    required this.prTitle,
    required this.prAuthorName,
    required this.contributionType,
    required this.prFileCitation,
    required this.mergeCommitSha,
  });
}

String sanitizeName(String name) {
  final withUnderscores = name.replaceAll(' ', '_');
  final regExp = RegExp(r'[^a-zA-Z0-9_\-\.]');
  return withUnderscores.replaceAll(regExp, '');
}

String getComponent(String filepath) {
  final parts = filepath.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) {
    return 'Other';
  }
  final top = parts[0].toLowerCase();
  switch (top) {
    case 'engine':
      return 'Engine';
    case 'packages':
      return 'Packages';
    case 'examples':
      return 'Examples';
    case 'samples':
      return 'Samples';
    case 'tool':
      return 'Tooling';
    case 'renderers':
      return 'Renderers';
    case 'dev':
      return 'Dev';
    case 'specification':
      return 'Specification';
    case 'sites':
      return 'Sites';
    case 'third_party':
      return 'Third_Party';
    case 'agent_sdks':
      return 'Agent_SDKs';
    case 'app_dart':
      return 'App_Dart';
    case 'docs':
      return 'Docs';
    default:
      return 'Other';
  }
}

String? extractField(String content, String field) {
  final regExp = RegExp(field + r'\s*[\r\n]+```\s*([\s\S]*?)\s*```');
  final match = regExp.firstMatch(content);
  return match?.group(1)?.trim();
}

String? extractLogin(String content) {
  final regExp = RegExp(
    r'# author\s*[\r\n]+## login\s*[\r\n]+```\s*([\s\S]*?)\s*```',
  );
  final match = regExp.firstMatch(content);
  return match?.group(1)?.trim();
}

int extractInt(String content, String field) {
  final regExp = RegExp(field + r'\s*[\r\n]+(\d+)');
  final match = regExp.firstMatch(content);
  final str = match?.group(1);
  return str != null ? int.parse(str) : 0;
}

List<String> extractFilenames(String content) {
  final regExp = RegExp(r'### filename\s*[\r\n]+```\s*([\s\S]*?)\s*```');
  final List<String> filenames = [];
  for (final match in regExp.allMatches(content)) {
    final val = match.group(1)?.trim();
    if (val != null) {
      filenames.add(val);
    }
  }
  return filenames;
}

ParsedCommit parseCommitFile(io.File file) {
  final content = file.readAsStringSync();
  final hash = io.File(file.path).uri.pathSegments.last.replaceAll('.md', '');
  final name = extractField(content, '### name') ?? '';
  final email = extractField(content, '### email') ?? '';
  final date = extractField(content, '### date') ?? '';
  final message = extractField(content, '## message') ?? '';
  final login = extractLogin(content) ?? '';
  final additions = extractInt(content, '## additions');
  final deletions = extractInt(content, '## deletions');
  final filenames = extractFilenames(content);

  return ParsedCommit(
    hash: hash,
    name: name.isNotEmpty ? name : (login.isNotEmpty ? login : 'Unknown'),
    email: email,
    date: date,
    message: message,
    login: login,
    additions: additions,
    deletions: deletions,
    filenames: filenames,
  );
}

String formatInt(int value, {bool showSign = false}) {
  final absVal = value.abs();
  final regExp = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
  final formattedAbs = absVal.toString().replaceAllMapped(
    regExp,
    (Match m) => '${m[1]},',
  );
  if (value < 0) {
    return '-$formattedAbs';
  } else if (showSign) {
    return '+$formattedAbs';
  } else {
    return formattedAbs;
  }
}

int compareMonthYear(String a, String b) {
  final partsA = a.split('_');
  final partsB = b.split('_');
  if (partsA.isEmpty || partsB.isEmpty) {
    return a.compareTo(b);
  }
  final yearA = partsA.length > 1 ? (int.tryParse(partsA[1]) ?? 0) : 0;
  final yearB = partsB.length > 1 ? (int.tryParse(partsB[1]) ?? 0) : 0;
  if (yearA != yearB) {
    return yearA.compareTo(yearB);
  }
  final monthNameA = partsA[0];
  final monthNameB = partsB[0];
  final monthList = MONTH_NAMES.values.toList();
  final indexA = monthList.indexOf(monthNameA);
  final indexB = monthList.indexOf(monthNameB);
  return indexA.compareTo(indexB);
}

Map<K, int> countOccurrences<K>(Iterable<K> list) {
  final counts = <K, int>{};
  for (final item in list) {
    counts[item] = (counts[item] ?? 0) + 1;
  }
  return counts;
}

List<MapEntry<K, int>> getSortedCounts<K>(Map<K, int> counts) {
  return counts.entries.toList()..sort((a, b) {
    final cmp = b.value.compareTo(a.value);
    if (cmp != 0) return cmp;
    if (a.key is Comparable) {
      return (a.key as Comparable).compareTo(b.key);
    }
    return 0;
  });
}

String generateAuthorPage(
  String name,
  Map<String, List<ParsedCommit>> authorCommits, [
  List<AuthorCodeReviewContribution> codeReviews = const [],
  Set<String> allDeveloperNames = const {},
]) {
  final commitsList = authorCommits[name] ?? [];
  final totalCommits = commitsList.length;
  final totalAdditions = commitsList.fold<int>(
    0,
    (sum, c) => sum + c.additions,
  );
  final totalDeletions = commitsList.fold<int>(
    0,
    (sum, c) => sum + c.deletions,
  );
  final netChanges = totalAdditions - totalDeletions;

  // Activity by Month
  final monthCounts = <String, int>{};
  final monthAdd = <String, int>{};
  final monthDel = <String, int>{};
  for (final c in commitsList) {
    monthCounts[c.monthYear] = (monthCounts[c.monthYear] ?? 0) + 1;
    monthAdd[c.monthYear] = (monthAdd[c.monthYear] ?? 0) + c.additions;
    monthDel[c.monthYear] = (monthDel[c.monthYear] ?? 0) + c.deletions;
  }

  // Activity by Component
  final compCounts = <String, int>{};
  final compAdd = <String, int>{};
  final compDel = <String, int>{};
  for (final c in commitsList) {
    for (final comp in c.components) {
      compCounts[comp] = (compCounts[comp] ?? 0) + 1;
      compAdd[comp] = (compAdd[comp] ?? 0) + c.additions;
      compDel[comp] = (compDel[comp] ?? 0) + c.deletions;
    }
  }

  final md = StringBuffer();
  md.writeln('# Developer Profile: $name\n');
  md.writeln('> [!NOTE]');
  md.writeln(
    '> This profile has been compiled from the repository\'s git history. It aggregates the impact, habits, and major contributions of **$name**.\n',
  );

  md.writeln('## Impact Summary\n');
  md.writeln('| Metric | Value |');
  md.writeln('| :--- | :--- |');
  md.writeln('| **Total Commits** | $totalCommits |');
  md.writeln('| **Total Additions** | +${formatInt(totalAdditions)} lines |');
  md.writeln('| **Total Deletions** | -${formatInt(totalDeletions)} lines |');
  md.writeln(
    '| **Net Code Change** | ${formatInt(netChanges, showSign: true)} lines |',
  );
  final avgAdd = totalCommits > 0 ? (totalAdditions ~/ totalCommits) : 0;
  final avgDel = totalCommits > 0 ? (totalDeletions ~/ totalCommits) : 0;
  md.writeln('| **Average Impact per Commit** | +$avgAdd / -$avgDel lines |\n');

  md.writeln('## Contribution Habits\n');
  md.writeln('### Monthly Activity Breakdown\n');
  md.writeln('| Month | Commits | Additions | Deletions | Net Change |');
  md.writeln('| :--- | :---: | :---: | :---: | :---: |');

  final sortedMonthsActive = monthCounts.keys.toList()..sort(compareMonthYear);
  for (final my in sortedMonthsActive) {
    final mAdd = monthAdd[my] ?? 0;
    final mDel = monthDel[my] ?? 0;
    final mNet = mAdd - mDel;
    final displayMonth = my.replaceAll('_', ' ');
    md.writeln(
      '| [$displayMonth](Timeline_$my.md) | ${monthCounts[my]} | +${formatInt(mAdd)} | -${formatInt(mDel)} | ${formatInt(mNet, showSign: true)} |',
    );
  }
  md.writeln();

  md.writeln('### Component Focus\n');
  md.writeln('| Component | Commits | Additions | Deletions | Net Change |');
  md.writeln('| :--- | :---: | :---: | :---: | :---: |');
  final sortedComps = compCounts.keys.toList()..sort();
  for (final comp in sortedComps) {
    final cAdd = compAdd[comp] ?? 0;
    final cDel = compDel[comp] ?? 0;
    final cNet = cAdd - cDel;
    md.writeln(
      '| [$comp](Feature_$comp.md) | ${compCounts[comp]} | +${formatInt(cAdd)} | -${formatInt(cDel)} | ${formatInt(cNet, showSign: true)} |',
    );
  }
  md.writeln();

  md.writeln('## Commit Log & Contribution Details\n');
  md.writeln(
    '| Date | Commit / Description | Impact | Components | Citation |',
  );
  md.writeln('| :--- | :--- | :---: | :--- | :---: |');

  final sortedCommits = List<ParsedCommit>.from(commitsList)
    ..sort((a, b) {
      final cmp = b.date.compareTo(a.date);
      if (cmp != 0) return cmp;
      return b.hash.compareTo(a.hash);
    });

  for (final c in sortedCommits) {
    final dateStr = c.date.length >= 10 ? c.date.substring(0, 10) : c.date;
    final lines = c.message.split(RegExp(r'\r?\n'));
    var firstLine = lines.isNotEmpty ? lines[0] : '';
    var safeMsg = firstLine.replaceAll('|', '\\|');
    if (safeMsg.length > 80) {
      safeMsg = '${safeMsg.substring(0, 77)}...';
    }
    final compLinks = c.components
        .map((comp) => '[$comp](Feature_$comp.md)')
        .join(', ');
    final citation = '[[../raw_commits/${c.hash}.md]]';
    md.writeln(
      '| $dateStr | $safeMsg | `+${c.additions}/-${c.deletions}` | $compLinks | $citation |',
    );
  }

  if (codeReviews.isNotEmpty) {
    md.writeln('## Code Review Contributions\n');
    md.writeln(
      '| Date | PR Title | PR Author | Contribution Type | Citation |',
    );
    md.writeln('| :--- | :--- | :--- | :---: | :---: |');

    final sortedReviews = List<AuthorCodeReviewContribution>.from(codeReviews)
      ..sort((a, b) {
        if (a.date == 'Unknown' && b.date == 'Unknown') {
          return a.mergeCommitSha.compareTo(b.mergeCommitSha);
        }
        if (a.date == 'Unknown') return 1;
        if (b.date == 'Unknown') return -1;
        final cmp = b.date.compareTo(a.date);
        if (cmp != 0) return cmp;
        return a.mergeCommitSha.compareTo(b.mergeCommitSha);
      });

    for (final cr in sortedReviews) {
      final safeTitle = cr.prTitle.replaceAll('|', '\\|');
      final sanPrAuthor = sanitizeName(cr.prAuthorName);
      final prAuthorLink = allDeveloperNames.contains(cr.prAuthorName)
          ? '[${cr.prAuthorName}](Author_$sanPrAuthor.md)'
          : cr.prAuthorName;

      md.writeln(
        '| ${cr.date} | $safeTitle | $prAuthorLink | ${cr.contributionType} | ${cr.prFileCitation} |',
      );
    }
    md.writeln();
  }

  return md.toString();
}

String generateComponentPage(
  String comp,
  Map<String, List<ParsedCommit>> componentCommits,
) {
  final commitsList = componentCommits[comp] ?? [];
  final totalCommits = commitsList.length;
  final totalAdditions = commitsList.fold<int>(
    0,
    (sum, c) => sum + c.additions,
  );
  final totalDeletions = commitsList.fold<int>(
    0,
    (sum, c) => sum + c.deletions,
  );
  final netChanges = totalAdditions - totalDeletions;

  // Key Contributors
  final authorCounts = countOccurrences(commitsList.map((c) => c.name));
  final authorAdd = <String, int>{};
  final authorDel = <String, int>{};
  for (final c in commitsList) {
    authorAdd[c.name] = (authorAdd[c.name] ?? 0) + c.additions;
    authorDel[c.name] = (authorDel[c.name] ?? 0) + c.deletions;
  }

  // Activity by Month
  final monthCounts = countOccurrences(commitsList.map((c) => c.monthYear));
  final monthAdd = <String, int>{};
  final monthDel = <String, int>{};
  for (final c in commitsList) {
    monthAdd[c.monthYear] = (monthAdd[c.monthYear] ?? 0) + c.additions;
    monthDel[c.monthYear] = (monthDel[c.monthYear] ?? 0) + c.deletions;
  }

  final md = StringBuffer();
  md.writeln('# Codebase Component: $comp\n');
  md.writeln('> [!NOTE]');
  md.writeln(
    '> This page aggregates high-level analysis and detailed chronological logs of how the **$comp** part of the codebase evolved over time.\n',
  );

  md.writeln('## Component Statistics\n');
  md.writeln('| Metric | Value |');
  md.writeln('| :--- | :--- |');
  md.writeln('| **Total Commits** | $totalCommits |');
  md.writeln('| **Total Additions** | +${formatInt(totalAdditions)} lines |');
  md.writeln('| **Total Deletions** | -${formatInt(totalDeletions)} lines |');
  md.writeln(
    '| **Net Code Change** | ${formatInt(netChanges, showSign: true)} lines |\n',
  );

  md.writeln('## Key Contributors / Core Developers\n');
  md.writeln(
    'The following developers have made the most significant impact on this component:\n',
  );
  md.writeln('| Developer | Commits | Additions | Deletions | Net Change |');
  md.writeln('| :--- | :---: | :---: | :---: | :---: |');

  final sortedAuthors = getSortedCounts(authorCounts);
  for (final entry in sortedAuthors) {
    final name = entry.key;
    final count = entry.value;
    final aAdd = authorAdd[name] ?? 0;
    final aDel = authorDel[name] ?? 0;
    final aNet = aAdd - aDel;
    final sanName = sanitizeName(name);
    md.writeln(
      '| [$name](Author_$sanName.md) | $count | +${formatInt(aAdd)} | -${formatInt(aDel)} | ${formatInt(aNet, showSign: true)} |',
    );
  }
  md.writeln();

  md.writeln('## Activity Timeline\n');
  md.writeln('| Month | Commits | Additions | Deletions | Net Change |');
  md.writeln('| :--- | :---: | :---: | :---: | :---: |');

  final sortedMonthsActive = monthCounts.keys.toList()..sort(compareMonthYear);
  for (final my in sortedMonthsActive) {
    final mAdd = monthAdd[my] ?? 0;
    final mDel = monthDel[my] ?? 0;
    final mNet = mAdd - mDel;
    final displayMonth = my.replaceAll('_', ' ');
    md.writeln(
      '| [$displayMonth](Timeline_$my.md) | ${monthCounts[my]} | +${formatInt(mAdd)} | -${formatInt(mDel)} | ${formatInt(mNet, showSign: true)} |',
    );
  }
  md.writeln();

  md.writeln('## Detailed History of Changes\n');
  md.writeln('| Date | Author | Description / Change | Impact | Citation |');
  md.writeln('| :--- | :--- | :--- | :---: | :---: |');

  final sortedCommits = List<ParsedCommit>.from(commitsList)
    ..sort((a, b) {
      final cmp = b.date.compareTo(a.date);
      if (cmp != 0) return cmp;
      return b.hash.compareTo(a.hash);
    });

  for (final c in sortedCommits) {
    final dateStr = c.date.length >= 10 ? c.date.substring(0, 10) : c.date;
    final sanName = sanitizeName(c.name);
    final lines = c.message.split(RegExp(r'\r?\n'));
    var firstLine = lines.isNotEmpty ? lines[0] : '';
    var safeMsg = firstLine.replaceAll('|', '\\|');
    if (safeMsg.length > 80) {
      safeMsg = '${safeMsg.substring(0, 77)}...';
    }
    final citation = '[[../raw_commits/${c.hash}.md]]';
    md.writeln(
      '| $dateStr | [${c.name}](Author_$sanName.md) | $safeMsg | `+${c.additions}/-${c.deletions}` | $citation |',
    );
  }

  return md.toString();
}

String generateTimelinePage(
  String my,
  Map<String, List<ParsedCommit>> timelineCommits,
) {
  final commitsList = timelineCommits[my] ?? [];
  final displayMonth = my.replaceAll('_', ' ');
  final totalCommits = commitsList.length;
  final totalAdditions = commitsList.fold<int>(
    0,
    (sum, c) => sum + c.additions,
  );
  final totalDeletions = commitsList.fold<int>(
    0,
    (sum, c) => sum + c.deletions,
  );
  final netChanges = totalAdditions - totalDeletions;

  // Active Authors
  final authorCounts = countOccurrences(commitsList.map((c) => c.name));
  final authorAdd = <String, int>{};
  final authorDel = <String, int>{};
  for (final c in commitsList) {
    authorAdd[c.name] = (authorAdd[c.name] ?? 0) + c.additions;
    authorDel[c.name] = (authorDel[c.name] ?? 0) + c.deletions;
  }

  // Active Components
  final compCounts = <String, int>{};
  final compAdd = <String, int>{};
  final compDel = <String, int>{};
  for (final c in commitsList) {
    for (final comp in c.components) {
      compCounts[comp] = (compCounts[comp] ?? 0) + 1;
      compAdd[comp] = (compAdd[comp] ?? 0) + c.additions;
      compDel[comp] = (compDel[comp] ?? 0) + c.deletions;
    }
  }

  final md = StringBuffer();
  md.writeln('# Project Timeline: $displayMonth\n');
  md.writeln('> [!NOTE]');
  md.writeln(
    '> This page contains a chronological summary of the major changes, bug fixes, and features introduced in **$displayMonth**.\n',
  );

  md.writeln('## $displayMonth Statistics\n');
  md.writeln('| Metric | Value |');
  md.writeln('| :--- | :--- |');
  md.writeln('| **Total Commits** | $totalCommits |');
  md.writeln('| **Active Authors** | ${authorCounts.length} |');
  md.writeln('| **Total Additions** | +${formatInt(totalAdditions)} lines |');
  md.writeln('| **Total Deletions** | -${formatInt(totalDeletions)} lines |');
  md.writeln(
    '| **Net Code Change** | ${formatInt(netChanges, showSign: true)} lines |\n',
  );

  md.writeln('## Component Focus Breakdown\n');
  md.writeln('| Component | Commits | Additions | Deletions | Net Change |');
  md.writeln('| :--- | :---: | :---: | :---: | :---: |');
  final sortedComps = compCounts.keys.toList()..sort();
  for (final comp in sortedComps) {
    final cAdd = compAdd[comp] ?? 0;
    final cDel = compDel[comp] ?? 0;
    final cNet = cAdd - cDel;
    md.writeln(
      '| [$comp](Feature_$comp.md) | ${compCounts[comp]} | +${formatInt(cAdd)} | -${formatInt(cDel)} | ${formatInt(cNet, showSign: true)} |',
    );
  }
  md.writeln();

  md.writeln('## Active Contributors\n');
  md.writeln('| Contributor | Commits | Additions | Deletions | Net Change |');
  md.writeln('| :--- | :---: | :---: | :---: | :---: |');
  final sortedAuthors = getSortedCounts(authorCounts);
  for (final entry in sortedAuthors) {
    final name = entry.key;
    final count = entry.value;
    final aAdd = authorAdd[name] ?? 0;
    final aDel = authorDel[name] ?? 0;
    final aNet = aAdd - aDel;
    final sanName = sanitizeName(name);
    md.writeln(
      '| [$name](Author_$sanName.md) | $count | +${formatInt(aAdd)} | -${formatInt(aDel)} | ${formatInt(aNet, showSign: true)} |',
    );
  }
  md.writeln();

  md.writeln('## Chronological Log of Changes\n');
  md.writeln(
    '| Date | Author | Component(s) | Description / Commit Message | Impact | Citation |',
  );
  md.writeln('| :--- | :--- | :--- | :--- | :---: | :---: |');

  final sortedCommits = List<ParsedCommit>.from(commitsList)
    ..sort((a, b) {
      final cmp = a.date.compareTo(b.date);
      if (cmp != 0) return cmp;
      return a.hash.compareTo(b.hash);
    });

  for (final c in sortedCommits) {
    final dateStr = c.date.length >= 10 ? c.date.substring(0, 10) : c.date;
    final sanName = sanitizeName(c.name);
    final compLinks = c.components
        .map((comp) => '[$comp](Feature_$comp.md)')
        .join(', ');
    final lines = c.message.split(RegExp(r'\r?\n'));
    var firstLine = lines.isNotEmpty ? lines[0] : '';
    var safeMsg = firstLine.replaceAll('|', '\\|');
    if (safeMsg.length > 70) {
      safeMsg = '${safeMsg.substring(0, 67)}...';
    }
    final citation = '[[../raw_commits/${c.hash}.md]]';
    md.writeln(
      '| $dateStr | [${c.name}](Author_$sanName.md) | $compLinks | $safeMsg | `+${c.additions}/-${c.deletions}` | $citation |',
    );
  }

  return md.toString();
}

String generateMasterIndex(
  List<ParsedCommit> commits,
  Map<String, List<ParsedCommit>> authorCommits,
  Map<String, List<ParsedCommit>> componentCommits,
  Map<String, List<ParsedCommit>> timelineCommits, {
  Set<String> allDeveloperNames = const {},
  Map<String, List<AuthorCodeReviewContribution>> developerReviews = const {},
}) {
  final totalCommits = commits.length;
  final totalAuthors = authorCommits.length;
  final totalComponents = componentCommits.length;
  final totalAdditions = commits.fold<int>(0, (sum, c) => sum + c.additions);
  final totalDeletions = commits.fold<int>(0, (sum, c) => sum + c.deletions);
  final netChanges = totalAdditions - totalDeletions;

  final md = StringBuffer();
  md.writeln('# Project History Wiki: Master Index\n');
  md.writeln('> [!TIP]');
  md.writeln(
    '> Welcome to the Project History Wiki! This is the main entry point linking all aggregations. From here, you can browse chronological timelines, developer profiles, and codebase area evolution logs.\n',
  );

  md.writeln('## Repository High-Level Statistics\n');
  md.writeln('| Metric | Value | Description |');
  md.writeln('| :--- | :---: | :--- |');
  md.writeln(
    '| **Total Commits** | ${formatInt(totalCommits)} | Total number of recorded changes |',
  );
  md.writeln(
    '| **Total Authors** | ${formatInt(totalAuthors)} | Unique contributors to the codebase |',
  );
  md.writeln(
    '| **Total Components** | ${formatInt(totalComponents)} | Logically separated codebase areas |',
  );
  md.writeln(
    '| **Total Additions** | +${formatInt(totalAdditions)} | Lines of code added |',
  );
  md.writeln(
    '| **Total Deletions** | -${formatInt(totalDeletions)} | Lines of code deleted |',
  );
  md.writeln(
    '| **Net Code Change** | ${formatInt(netChanges, showSign: true)} | Overall growth of the codebase |\n',
  );

  md.writeln('## 📅 Project Timelines\n');
  md.writeln(
    'Browse the chronological history and major milestones of the project month by month:\n',
  );
  md.writeln('| Timeline Period | Commits | Activity Summary |');
  md.writeln('| :--- | :---: | :--- |');

  final sortedMonths = timelineCommits.keys.toList()..sort(compareMonthYear);
  for (final my in sortedMonths) {
    final displayMonth = my.replaceAll('_', ' ');
    final mCommits = timelineCommits[my]!.length;
    final mAdd = timelineCommits[my]!.fold<int>(
      0,
      (sum, c) => sum + c.additions,
    );
    final mDel = timelineCommits[my]!.fold<int>(
      0,
      (sum, c) => sum + c.deletions,
    );
    md.writeln(
      '| **[$displayMonth](Timeline_$my.md)** | $mCommits | `+${formatInt(mAdd)}/-${formatInt(mDel)}` changes |',
    );
  }
  md.writeln();

  md.writeln('## 🧩 Codebase Components\n');
  md.writeln(
    'Explore how different areas and logical components of the repository evolved over time:\n',
  );
  md.writeln(
    '| Component / Area | Commits | Code Impact | Core Contributors |',
  );
  md.writeln('| :--- | :---: | :---: | :--- |');

  final sortedComps = componentCommits.keys.toList()..sort();
  for (final comp in sortedComps) {
    final compList = componentCommits[comp]!;
    final cCommits = compList.length;
    final cAdd = compList.fold<int>(0, (sum, c) => sum + c.additions);
    final cDel = compList.fold<int>(0, (sum, c) => sum + c.deletions);

    // Find top 3 contributors
    final cAuthors = countOccurrences(compList.map((c) => c.name));
    final topAuthors = getSortedCounts(cAuthors)
        .take(3)
        .map((entry) {
          final sanName = sanitizeName(entry.key);
          return '[${entry.key}](Author_$sanName.md)';
        })
        .join(', ');

    md.writeln(
      '| **[$comp](Feature_$comp.md)** | $cCommits | `+${formatInt(cAdd)}/-${formatInt(cDel)}` | $topAuthors |',
    );
  }
  md.writeln();

  md.writeln('## 👥 Key Contributors & Authors\n');
  md.writeln(
    'Profile and impact of each developer who contributed to this project:\n',
  );
  md.writeln(
    '| Developer / Contributor | Commits | Total Additions | Total Deletions | Net Change |',
  );
  md.writeln('| :--- | :---: | :---: | :---: | :---: |');

  final sortedAuthors =
      (allDeveloperNames.isNotEmpty
            ? allDeveloperNames.toList()
            : authorCommits.keys.toList())
        ..sort((a, b) {
          final commitsA = authorCommits[a]?.length ?? 0;
          final commitsB = authorCommits[b]?.length ?? 0;
          final cmp = commitsB.compareTo(commitsA);
          if (cmp != 0) return cmp;
          final reviewsA = developerReviews[a]?.length ?? 0;
          final reviewsB = developerReviews[b]?.length ?? 0;
          final cmpReviews = reviewsB.compareTo(reviewsA);
          if (cmpReviews != 0) return cmpReviews;
          return a.compareTo(b);
        });

  for (final name in sortedAuthors) {
    final authorList = authorCommits[name] ?? [];
    final aCommits = authorList.length;
    final aAdd = authorList.fold<int>(0, (sum, c) => sum + c.additions);
    final aDel = authorList.fold<int>(0, (sum, c) => sum + c.deletions);
    final aNet = aAdd - aDel;
    final sanName = sanitizeName(name);
    md.writeln(
      '| **[$name](Author_$sanName.md)** | $aCommits | +${formatInt(aAdd)} | -${formatInt(aDel)} | ${formatInt(aNet, showSign: true)} |',
    );
  }

  return md.toString();
}

void compileWiki(
  io.Directory rawCommitsDir,
  io.Directory wikiDir, {
  io.Directory? rawPrsDir,
}) {
  print('Ensuring output directory exists: ${wikiDir.path}');
  wikiDir.createSync(recursive: true);

  print('Reading and parsing raw commits...');
  if (!rawCommitsDir.existsSync()) {
    print('Raw commits directory does not exist!');
    throw ArgumentError(
      'Raw commits directory does not exist: ${rawCommitsDir.path}',
    );
  }

  final rawFiles =
      rawCommitsDir
          .listSync()
          .whereType<io.File>()
          .where((f) => f.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  print('Found ${rawFiles.length} raw commit files.');

  final List<ParsedCommit> commits = [];
  for (final file in rawFiles) {
    try {
      commits.add(parseCommitFile(file));
    } catch (e) {
      print('Error parsing ${file.path}: $e');
    }
  }

  // Sort chronologically
  commits.sort((a, b) {
    final cmp = a.date.compareTo(b.date);
    if (cmp != 0) return cmp;
    return a.hash.compareTo(b.hash);
  });

  final Map<String, List<ParsedCommit>> authorCommits = {};
  final Map<String, List<ParsedCommit>> componentCommits = {};
  final Map<String, List<ParsedCommit>> timelineCommits = {};

  print('Grouping and organizing parsed records...');
  for (final c in commits) {
    // Group by Author
    authorCommits.putIfAbsent(c.name, () => []).add(c);

    // Parse date to month_year
    if (c.date.isNotEmpty) {
      final ymMatch = RegExp(r'^(\d{4})-(\d{2})').firstMatch(c.date);
      if (ymMatch != null) {
        final year = ymMatch.group(1)!;
        final monthNum = ymMatch.group(2)!;
        final monthName = MONTH_NAMES[monthNum] ?? 'Unknown';
        final monthYear = '${monthName}_$year';
        timelineCommits.putIfAbsent(monthYear, () => []).add(c);
        c.monthYear = monthYear;
      } else {
        c.monthYear = 'Unknown';
      }
    } else {
      c.monthYear = 'Unknown';
    }

    // Group by Component
    final components = <String>{};
    for (final fname in c.filenames) {
      components.add(getComponent(fname));
    }
    if (components.isEmpty) {
      components.add('Other');
    }

    c.components = components.toList()..sort();
    for (final comp in components) {
      componentCommits.putIfAbsent(comp, () => []).add(c);
    }
  }

  // Build lookup mapping to match PR merge commit to git commits
  final Map<String, ParsedCommit> commitLookup = {
    for (final c in commits) c.hash: c,
  };

  // Group commits by login to find the primary display name for each login
  final Map<String, String> loginToDisplayName = {};
  for (final c in commits) {
    if (c.login.isNotEmpty && c.name.isNotEmpty) {
      loginToDisplayName[c.login] = c.name;
    }
  }

  // Parse raw PRs and build code review contributions
  final Map<String, List<AuthorCodeReviewContribution>> developerReviews = {};
  final List<ParsedPr> prs = [];
  if (rawPrsDir != null && rawPrsDir.existsSync()) {
    print('Reading and parsing raw PRs from ${rawPrsDir.path}...');
    final rawPrFiles =
        rawPrsDir
            .listSync()
            .whereType<io.File>()
            .where((f) => f.path.endsWith('.md'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    print('Found ${rawPrFiles.length} raw PR files.');
    for (final file in rawPrFiles) {
      try {
        prs.add(parsePrFile(file));
      } catch (e) {
        print('Error parsing PR file ${file.path}: $e');
      }
    }

    for (final pr in prs) {
      final prAuthorName = loginToDisplayName[pr.authorLogin] ?? pr.authorLogin;
      final matchingCommit = commitLookup[pr.mergeCommitSha];
      final dateStr = matchingCommit != null
          ? (matchingCommit.date.length >= 10
                ? matchingCommit.date.substring(0, 10)
                : matchingCommit.date)
          : 'Unknown';

      final Map<String, Set<String>> prContribTypesForThisPr = {};
      for (final contrib in pr.reviewsAndComments) {
        final contribName =
            loginToDisplayName[contrib.authorLogin] ?? contrib.authorLogin;
        final type = contrib.isReview ? 'Review' : 'Comment';
        prContribTypesForThisPr.putIfAbsent(contribName, () => {}).add(type);
      }

      prContribTypesForThisPr.forEach((contribName, types) {
        String typeStr = 'Comment';
        if (types.contains('Review') && types.contains('Comment')) {
          typeStr = 'Review & Comment';
        } else if (types.contains('Review')) {
          typeStr = 'Review';
        }

        final citation = '[[../raw_prs/${pr.mergeCommitSha}.md]]';
        final contribObj = AuthorCodeReviewContribution(
          date: dateStr,
          prTitle: pr.title,
          prAuthorName: prAuthorName,
          contributionType: typeStr,
          prFileCitation: citation,
          mergeCommitSha: pr.mergeCommitSha,
        );

        developerReviews.putIfAbsent(contribName, () => []).add(contribObj);
      });
    }
  }

  final allDeveloperNames = <String>{
    ...authorCommits.keys,
    ...developerReviews.keys,
  };

  // Write Author pages
  print('Generating ${allDeveloperNames.length} author profiles...');
  for (final authorName in allDeveloperNames) {
    final sanName = sanitizeName(authorName);
    final reviews = developerReviews[authorName] ?? [];
    final authorMd = generateAuthorPage(
      authorName,
      authorCommits,
      reviews,
      allDeveloperNames,
    );
    final filepath = '${wikiDir.path}/Author_$sanName.md';
    io.File(filepath).writeAsStringSync(authorMd);
  }

  // Write Component pages
  print('Generating ${componentCommits.length} codebase component pages...');
  for (final comp in componentCommits.keys) {
    final compMd = generateComponentPage(comp, componentCommits);
    final filepath = '${wikiDir.path}/Feature_$comp.md';
    io.File(filepath).writeAsStringSync(compMd);
  }

  // Write Timeline pages
  print('Generating ${timelineCommits.length} monthly timelines...');
  for (final my in timelineCommits.keys) {
    final timelineMd = generateTimelinePage(my, timelineCommits);
    final filepath = '${wikiDir.path}/Timeline_$my.md';
    io.File(filepath).writeAsStringSync(timelineMd);
  }

  // Write Master Index
  print('Generating Master Index...');
  final masterIndexMd = generateMasterIndex(
    commits,
    authorCommits,
    componentCommits,
    timelineCommits,
    allDeveloperNames: allDeveloperNames,
    developerReviews: developerReviews,
  );
  final masterIndexFilepath = '${wikiDir.path}/_Master_Index.md';
  io.File(masterIndexFilepath).writeAsStringSync(masterIndexMd);

  print('Compilation fully complete!');
}
