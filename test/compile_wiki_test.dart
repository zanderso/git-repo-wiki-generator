// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' as io;
import 'package:test/test.dart';
import 'package:git_repo_wiki_generator/compile_wiki.dart';

void main() {
  group('Wiki Compiler Library', () {
    late io.Directory tempDir;
    late io.Directory rawCommitsDir;
    late io.Directory wikiDir;

    setUp(() {
      tempDir = io.Directory.systemTemp.createTempSync('compile_wiki_test_');
      rawCommitsDir = io.Directory('${tempDir.path}/raw_commits')..createSync();
      wikiDir = io.Directory('${tempDir.path}/wiki');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('throws ArgumentError if raw commits directory does not exist', () {
      final nonExistentDir = io.Directory('${tempDir.path}/does_not_exist');
      expect(
        () => compileWiki(nonExistentDir, wikiDir),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('compiles wiki files successfully from raw markdown commits', () {
      // 1. Create mock commit markdown files
      final commit1File = io.File('${rawCommitsDir.path}/hash123abc.md');
      commit1File.writeAsStringSync('''
### name
```
Alice
```

### email
```
alice@example.com
```

### date
```
2026-06-15T10:00:00Z
```

## message
```
Fix all the issues with engine rendering.
```

# author
## login
```
alice_dev
```

## additions
150

## deletions
25

### filename
```
engine/src/render.cc
```
### filename
```
packages/flutter/lib/src/widgets/framework.dart
```
''');

      final commit2File = io.File('${rawCommitsDir.path}/hash456def.md');
      commit2File.writeAsStringSync('''
### name
```
Bob
```

### email
```
bob@example.com
```

### date
```
2026-06-18T14:30:00Z
```

## message
```
Update tooling command line parser.
```

# author
## login
```
bob_tooler
```

## additions
10

## deletions
5

### filename
```
tool/bin/parser.dart
```
''');

      // 2. Run the compiler
      compileWiki(rawCommitsDir, wikiDir);

      // 3. Verify output files exist
      expect(wikiDir.existsSync(), isTrue);

      final masterIndex = io.File('${wikiDir.path}/_Master_Index.md');
      final authorAlice = io.File('${wikiDir.path}/Author_Alice.md');
      final authorBob = io.File('${wikiDir.path}/Author_Bob.md');
      final featureEngine = io.File('${wikiDir.path}/Feature_Engine.md');
      final featurePackages = io.File('${wikiDir.path}/Feature_Packages.md');
      final featureTooling = io.File('${wikiDir.path}/Feature_Tooling.md');
      final timelineJune2026 = io.File('${wikiDir.path}/Timeline_June_2026.md');

      expect(masterIndex.existsSync(), isTrue);
      expect(authorAlice.existsSync(), isTrue);
      expect(authorBob.existsSync(), isTrue);
      expect(featureEngine.existsSync(), isTrue);
      expect(featurePackages.existsSync(), isTrue);
      expect(featureTooling.existsSync(), isTrue);
      expect(timelineJune2026.existsSync(), isTrue);

      // 4. Validate Master Index content
      final masterIndexContent = masterIndex.readAsStringSync();
      expect(
        masterIndexContent,
        contains('Project History Wiki: Master Index'),
      );
      expect(masterIndexContent, contains('**Total Commits** | 2'));
      expect(masterIndexContent, contains('**Total Authors** | 2'));
      expect(masterIndexContent, contains('**Total Components** | 3'));
      expect(
        masterIndexContent,
        contains('[June 2026](Timeline_June_2026.md)'),
      );
      expect(masterIndexContent, contains('[Alice](Author_Alice.md)'));
      expect(masterIndexContent, contains('[Bob](Author_Bob.md)'));
      expect(masterIndexContent, contains('[Engine](Feature_Engine.md)'));
      expect(masterIndexContent, contains('[Packages](Feature_Packages.md)'));
      expect(masterIndexContent, contains('[Tooling](Feature_Tooling.md)'));

      // 5. Validate Author Page content
      final aliceContent = authorAlice.readAsStringSync();
      expect(aliceContent, contains('# Developer Profile: Alice'));
      expect(aliceContent, contains('Total Commits** | 1'));
      expect(aliceContent, contains('Total Additions** | +150 lines'));
      expect(aliceContent, contains('Total Deletions** | -25 lines'));
      expect(aliceContent, contains('Net Code Change** | +125 lines'));
      expect(aliceContent, contains('[June 2026](Timeline_June_2026.md) | 1'));
      expect(aliceContent, contains('[Engine](Feature_Engine.md)'));
      expect(aliceContent, contains('[Packages](Feature_Packages.md)'));
      expect(
        aliceContent,
        contains('Fix all the issues with engine rendering.'),
      );

      // 6. Validate Component Page content
      final engineContent = featureEngine.readAsStringSync();
      expect(engineContent, contains('# Codebase Component: Engine'));
      expect(engineContent, contains('Total Commits** | 1'));
      expect(engineContent, contains('[Alice](Author_Alice.md) | 1'));

      // 7. Validate Timeline Page content
      final timelineContent = timelineJune2026.readAsStringSync();
      expect(timelineContent, contains('# Project Timeline: June 2026'));
      expect(timelineContent, contains('Total Commits** | 2'));
      expect(timelineContent, contains('Active Authors** | 2'));
      expect(timelineContent, contains('[Alice](Author_Alice.md)'));
      expect(timelineContent, contains('[Bob](Author_Bob.md)'));
    });

    test('deterministic sorting tie-breaker works as expected', () {
      // Create two commits on the exact same date. They should sort deterministically by hash.
      final commitA = io.File('${rawCommitsDir.path}/hashAAA.md');
      commitA.writeAsStringSync('''
### name
```
Alice
```
### date
```
2026-06-15T10:00:00Z
```
## message
```
A commit
```
''');

      final commitB = io.File('${rawCommitsDir.path}/hashBBB.md');
      commitB.writeAsStringSync('''
### name
```
Bob
```
### date
```
2026-06-15T10:00:00Z
```
## message
```
B commit
```
''');

      compileWiki(rawCommitsDir, wikiDir);

      final timelineJune2026 = io.File('${wikiDir.path}/Timeline_June_2026.md');
      final timelineContent = timelineJune2026.readAsStringSync();

      // Since date is the same, alphabetical hash sorting dictates hashAAA (A commit) comes before hashBBB (B commit)
      final indexA = timelineContent.indexOf('A commit');
      final indexB = timelineContent.indexOf('B commit');
      expect(indexA, isNot(-1));
      expect(indexB, isNot(-1));
      expect(indexA, lessThan(indexB));
    });

    test('compiles wiki with pull requests and code reviews successfully', () {
      final rawPrsDir = io.Directory('${tempDir.path}/raw_prs')..createSync();

      // Create a commit for Alice
      final commitAlice = io.File('${rawCommitsDir.path}/hash123abc.md');
      commitAlice.writeAsStringSync('''
### name
```
Alice
```
### email
```
alice@example.com
```
### date
```
2026-06-15T10:00:00Z
```
## message
```
Fix all the issues with engine rendering.
```
# author
## login
```
alice_dev
```
## additions
150
## deletions
25
### filename
```
engine/src/render.cc
```
''');

      // Create a commit for Bob
      final commitBob = io.File('${rawCommitsDir.path}/hash456def.md');
      commitBob.writeAsStringSync('''
### name
```
Bob
```
### email
```
bob@example.com
```
### date
```
2026-06-16T12:00:00Z
```
## message
```
Update tooling command line parser.
```
# author
## login
```
bob_reviewer
```
## additions
10
## deletions
5
### filename
```
tool/bin/parser.dart
```
''');

      // Create a PR matching hash123abc
      final prFile = io.File('${rawPrsDir.path}/hash123abc.md');
      prFile.writeAsStringSync('''
# pull_request
## merge_commit_sha
```
hash123abc
```
## title
```
Add awesome feature
```
## user
### login
```
alice_dev
```

# reviews
## reviews
### user
#### login
```
bob_reviewer
```
### body
```
LGTM!
```
## reviews
### user
#### login
```
charlie_reviewer
```
### body
```
Please double check.
```
''');

      // Run compiler with rawPrsDir
      compileWiki(rawCommitsDir, wikiDir, rawPrsDir: rawPrsDir);

      // Verify files
      expect(wikiDir.existsSync(), isTrue);

      final masterIndex = io.File('${wikiDir.path}/_Master_Index.md');
      final authorAlice = io.File('${wikiDir.path}/Author_Alice.md');
      final authorBob = io.File('${wikiDir.path}/Author_Bob.md');
      final authorCharlie = io.File(
        '${wikiDir.path}/Author_charlie_reviewer.md',
      );

      expect(masterIndex.existsSync(), isTrue);
      expect(authorAlice.existsSync(), isTrue);
      expect(authorBob.existsSync(), isTrue);
      expect(authorCharlie.existsSync(), isTrue);

      // Verify Charlie's profile has reviews but no commits
      final charlieContent = authorCharlie.readAsStringSync();
      expect(charlieContent, contains('# Developer Profile: charlie_reviewer'));
      expect(charlieContent, contains('Total Commits** | 0'));
      expect(charlieContent, contains('## Code Review Contributions'));
      expect(charlieContent, contains('Add awesome feature'));
      expect(charlieContent, contains('[Alice](Author_Alice.md)'));

      // Verify Bob's profile has reviews and commits
      final bobContent = authorBob.readAsStringSync();
      expect(bobContent, contains('# Developer Profile: Bob'));
      expect(bobContent, contains('Total Commits** | 1'));
      expect(bobContent, contains('## Code Review Contributions'));
      expect(bobContent, contains('Add awesome feature'));

      // Verify Master Index links Charlie and Bob correctly
      final indexContent = masterIndex.readAsStringSync();
      expect(
        indexContent,
        contains('[charlie_reviewer](Author_charlie_reviewer.md)'),
      );
      expect(indexContent, contains('[Bob](Author_Bob.md)'));
    });
  });

  group('bin/compile_wiki.dart CLI', () {
    late io.Directory tempDir;
    late io.Directory rawCommitsDir;
    late io.Directory wikiDir;

    setUp(() {
      tempDir = io.Directory.systemTemp.createTempSync(
        'compile_wiki_cli_test_',
      );
      rawCommitsDir = io.Directory('${tempDir.path}/raw_commits')..createSync();
      wikiDir = io.Directory('${tempDir.path}/wiki');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('CLI compiles wiki successfully from raw commits', () async {
      final commit = io.File('${rawCommitsDir.path}/hashCLI.md');
      commit.writeAsStringSync('''
### name
```
CLI User
```
### date
```
2026-06-15T10:00:00Z
```
## message
```
CLI test commit
```
''');

      final result = await io.Process.run('dart', [
        'bin/compile_wiki.dart',
        '-i',
        rawCommitsDir.path,
        '-o',
        wikiDir.path,
      ]);

      expect(result.exitCode, equals(0));
      expect(wikiDir.existsSync(), isTrue);
      expect(io.File('${wikiDir.path}/_Master_Index.md').existsSync(), isTrue);
    });
  });
}
