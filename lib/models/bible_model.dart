class BibleModel {
  final String translation;
  final List<BibleBook> books;

  BibleModel({required this.translation, required this.books});

  factory BibleModel.fromJson(String translation, List<dynamic> jsonList) {
    List<BibleBook> books = [];
    for (var bookJson in jsonList) {
      books.add(BibleBook.fromJson(bookJson));
    }
    return BibleModel(translation: translation, books: books);
  }
}

class BibleBook {
  final String name;
  final String abbreviation;
  final List<List<String>>
  chapters; // chapters[0] is chapter 1, chapters[0][0] is verse 1

  BibleBook({
    required this.name,
    required this.abbreviation,
    required this.chapters,
  });

  factory BibleBook.fromJson(Map<String, dynamic> json) {
    List<List<String>> chapters = [];
    if (json['chapters'] != null) {
      for (var chapterList in json['chapters']) {
        List<String> verses = [];
        for (var verseText in chapterList) {
          verses.add(verseText.toString());
        }
        chapters.add(verses);
      }
    }
    return BibleBook(
      name: json['name'] ?? '',
      abbreviation: json['abbrev'] ?? '',
      chapters: chapters,
    );
  }
}
