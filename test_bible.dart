void main() {
  final str = "Check out Genesis 1:1";
  final regex = RegExp(
    r'\b((?:[1-3]\s+)?[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s+(\d+):(\d+)(?:-(\d+))?\b',
    caseSensitive: false,
  );
  for (var match in regex.allMatches(str)) {
    print("Match: ${match.group(0)}");
    print("Group 1: ${match.group(1)}");
    print("Group 2: ${match.group(2)}");
    print("Group 3: ${match.group(3)}");
  }
}
