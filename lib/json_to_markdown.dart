// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

bool isNothing(dynamic d) {
  return switch (d) {
    num _ => false,
    String s => s.isEmpty,
    bool _ => false,
    Null _ => true,
    List l => l.isEmpty,
    Map m => m.isEmpty,
    _ => false,
  };
}

bool pathMatch(String filter, String path) {
  if (path.startsWith(filter)) {
    return true;
  }

  if (filter.startsWith(path)) {
    return true;
  }

  return false;
}

void jsonObjectToMarkdown(
  Map<String, dynamic> jsonData,
  StringBuffer output, {
  int depth = 1,
  String path = '',
  List<String> includeFilter = const [],
  List<String> excludeFilter = const [],
}) {
 for (final String key in jsonData.keys) {
  if (isNothing(jsonData[key])) {
    continue;
  }
  if (includeFilter.isNotEmpty &&
      !includeFilter.any((String f) => pathMatch(f, '$path.$key'))) {
    continue;
  }
  if (excludeFilter.isNotEmpty &&
      excludeFilter.any((String f) => pathMatch(f, '$path.$key'))) {
    continue;
  }
  final String pounds = '#'*depth;
  output.writeln('$pounds $key');
  output.writeln();
  switch (jsonData[key]) {
    case num x:
      output.writeln(x.toString());
    case String s:
      // Treat all strings as code.
      output.writeln('```');
      output.writeln(s);
      output.writeln('```');
    case bool b:
      output.writeln(b.toString());
    case Null n:
      output.writeln(n.toString());
    case List l:
      if (l.isEmpty) {
        break;
      }
      switch (l.first) {
        case Map<String, dynamic> _:
          for (int i = 0; i < l.length; i++) {
            jsonObjectToMarkdown(
              {key: l[i]},
              output,
              depth:
              depth+1,
              path: '$path.$key',
              includeFilter: includeFilter,
              excludeFilter: excludeFilter,
            );
          }
        default:
          jsonListToMarkdown(l, output);
      }
    case Map<String, dynamic> j:
      jsonObjectToMarkdown(
        j,
        output,
        depth: depth+1,
        path: '$path.$key',
        includeFilter: includeFilter,
        excludeFilter: excludeFilter,
      );
    default:
      output.writeln(jsonData[key]);
  }
  output.writeln();
 }
}

void jsonListToMarkdown(
  List<dynamic> jsonData,
  StringBuffer output, {
  int depth = 1,
}) {
  for (final e in jsonData) {
    switch (e) {
      case List<dynamic> l:
        jsonListToMarkdown(l, output, depth: depth+1);
      default:
        final String indent = ' '*depth;
        output.writeln('$indent- ${e.toString()}');
    }
  }
}
