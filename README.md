# Repo Commit Tracker & Wiki Generator

This tool extracts commit data from GitHub repositories, converts it into beautiful, standardized raw commit markdown files, and compiles them into a highly structured project history Wiki (complete with developer profiles, project timelines, and component focus areas).

---

## 🚀 Usage Workflows

There are two primary ways to run and consume this package depending on your automation needs:

### 1. The All-in-One Automated Pipeline
You can run the entire sequence (fetching, raw translation, and wiki compilation) in a single-shot command using `bin/fetch_data.dart`.

```bash
dart bin/fetch_data.dart -c <config-json> -o <output-jsonl> -d <raw-commits-dir> -w <wiki-dir>
```

- `-c, --config`: Path to your JSON configuration file defining the repositories, date ranges, bot filters, and GitHub authentication token.
- `-o, --output`: Where to write the accumulated raw commit JSONLines (`.jsonl`) data.
- `-d, --output-dir`: The directory where individual commit markdown files will be written.
- `-w, --wiki-dir`: The destination directory where the compiled wiki files and master index will be written.

---

### 2. The Step-by-Step Manual Pipeline
For advanced workflows (such as combining commit datasets from multiple separate runs, offline curation, or custom pipeline steps), you can execute each phase independently using separate command-line utilities.

#### Step 1: Download Commits to JSONLines
Fetch and dump raw commit records from GitHub into a `.jsonl` database:
```bash
dart bin/fetch_data.dart -c config.json -o output.jsonl
```

#### Step 2: Convert JSONL Files to Markdown
Translate one or more `.jsonl` files (including separate invocations from different time ranges or repositories) into individual commit markdown logs under a target directory:
```bash
dart bin/json_to_markdown.dart -d mdout/raw_commits output1.jsonl output2.jsonl
```
*(Note: You can pass any number of input `.jsonl` files to this program.)*

#### Step 3: Compile the Wiki
Aggregate and compile the converted commit markdowns into structured, cross-linked profiles, timelines, and a master index:
```bash
dart bin/compile_wiki.dart -i mdout/raw_commits -o mdout/wiki
```

---

## ⚙️ Configuration File Format

The `bin/fetch_data.dart` script requires a JSON configuration file (specified via the `-c` or `--config` flag). This file defines the GitHub authentication token, target repositories, date range for fetching commits, and a list of bot accounts to filter out.

### Example Configuration

Below is an example of a valid configuration file (e.g., `config.json`):

```json
{
  "token": "github_pat_11ABQMTPY0dx...",
  "since": "2026-06-13",
  "until": "2026-06-19",
  "repos": [
    "flutter/cocoon",
    "flutter/packages"
  ],
  "bots": [
    "dependabot[bot]",
    "github-actions[bot]"
  ]
}
```

### Configuration Fields

| Field | Type | Required | Description |
| :--- | :--- | :---: | :--- |
| `token` | `String` | Yes | Your GitHub Personal Access Token (PAT) used to authenticate API requests and prevent severe rate limiting. Must be non-empty. |
| `since` | `String` | Yes | A non-empty ISO 8601 formatted date/time string (e.g., `"2026-06-13"` or `"2026-06-13T00:00:00Z"`) indicating the start of the timeframe to fetch commits. |
| `until` | `String` | Yes | A non-empty ISO 8601 formatted date/time string indicating the end of the timeframe to fetch commits. |
| `repos` | `List<String>` | Yes | A non-empty list of GitHub repository paths in `"owner/repo"` format (e.g., `"flutter/flutter"`). |
| `bots` | `List<String>` | Yes | A non-empty list of GitHub user login IDs/bot accounts (e.g., `"dependabot[bot]"`) whose commits should be ignored/filtered out. |

---

## 🤖 Querying Wiki Data with Antigravity

Once your project history wiki is generated under your output directory (e.g., `mdout/wiki`), you can utilize **Antigravity** directly to query and write rich analyses about your repository data. 

Because Antigravity possesses deep file-reading and search tools (`grep_search`, `view_file`, etc.), you can simply ask it natural language questions in your chat panel to analyze the wiki.

### Sample Prompts for Antigravity:

* **To Aggregate Stats**:
  > *"Antigravity, please search through the markdown profiles under `mdout/wiki` and find the top three developers with the highest additions and deletions. Present the results in a markdown table."*

* **To Track Component Trends**:
  > *"Analyze the codebase component pages in `mdout/wiki/Feature_*.md` and identify which components received the most tooling-related commits during June 2026."*

* **To Generate Custom Analysis Scripts**:
  > *"Write a custom Dart script to scan all files under `mdout/wiki/Timeline_*.md` and print a CSV showing the number of unique contributors active in each month."*

* **To Summarize Contributions**:
  > *"Review the profile of developer `Alice` in `mdout/wiki/Author_Alice.md` and summarize her primary contributions to the Engine component, highlighting her three highest-impact commits."*
