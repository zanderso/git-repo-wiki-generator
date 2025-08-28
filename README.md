### First

Put your GitHub API Key in `bin/dash_commit_counts.dart` in the global
`githubApiKey` at the top of the file.

### Flutter example:
```
dart run bin/dash_commit_counts.dart --members github_ids.lst --output 2025-08-27-flutter-summary.csv --raw-output 2025-08-27-flutter-raw.json
```

### Dart example:
```
dart run bin/dash_commit_counts.dart --members github_ids.lst --output 2025-08-27-dart-summary.csv --raw-output 2025-08-27-dart-raw.json --dart
```

### Inputs / outputs

- `github_ids.lst` is an input file. It is a newline separated list of "members" of the project,
  used to distinguish commits between "members" and "non-members".
- `2025-08-27-flutter-summary.csv` is an output file. It is a csv file formatted as:
  `github_id, number of commits, lines added, lines deleted`. There is an empty entry
  (`,,,`) dilineating the "member" data from the "non-member" data that follows it.
- `2025-08-27-flutter-raw.json` is an output file. It is the raw data about commits
  from the GitHub API calls, formatted as json.

### Notes

GitHub has been making changes to how it enforces rate limits. This program is not
100% resilient to it. Authenticated access is limited to 5000 API calls per hour.
The program tries to stay under that, which causes it to run quite slowly.

It's probably possible to get it to make fewer API calls if you don't care about the
lines added/deleted in each commit, and only care about the number of commits.
You'd do that by changing `downloadCommitData` to short-circuit fetching
the `fullCommit`, and just use the `partialCommit` instead.

After running this program, the usual next step is to take data from the summary csv
and load it into a spreadsheet for further analysis.
