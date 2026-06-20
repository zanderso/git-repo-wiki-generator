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
  Map<String, List<ParsedCommit>> authorCommits,
) {
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
  Map<String, List<ParsedCommit>> timelineCommits,
) {
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

  final sortedAuthors = authorCommits.keys.toList()
    ..sort((a, b) {
      final cmp = (authorCommits[b]!.length).compareTo(
        authorCommits[a]!.length,
      );
      if (cmp != 0) return cmp;
      return a.compareTo(b);
    });

  for (final name in sortedAuthors) {
    final authorList = authorCommits[name]!;
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

void compileWiki(io.Directory rawCommitsDir, io.Directory wikiDir) {
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

  // Write Author pages
  print('Generating ${authorCommits.length} author profiles...');
  for (final authorName in authorCommits.keys) {
    final sanName = sanitizeName(authorName);
    final authorMd = generateAuthorPage(authorName, authorCommits);
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
  );
  final masterIndexFilepath = '${wikiDir.path}/_Master_Index.md';
  io.File(masterIndexFilepath).writeAsStringSync(masterIndexMd);

  print('Compilation fully complete!');
}
