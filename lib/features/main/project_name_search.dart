List<String> filterProjectNames(Iterable<String> projectNames, String keyword) {
  final normalizedKeyword = keyword.trim().toLowerCase();
  final uniqueNames = <String>{};

  for (final projectName in projectNames) {
    final name = projectName.trim();
    if (name.isEmpty) continue;
    if (normalizedKeyword.isEmpty ||
        name.toLowerCase().contains(normalizedKeyword)) {
      uniqueNames.add(name);
    }
  }

  return uniqueNames.toList(growable: false);
}
