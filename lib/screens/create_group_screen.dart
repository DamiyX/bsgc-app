import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/chat_service.dart';
import 'study_room_screen.dart';
import '../theme.dart';
import 'package:flutter/services.dart';

class CreateGroupScreen extends StatefulWidget {
  final ChatService chatService;

  const CreateGroupScreen({super.key, required this.chatService});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  String _groupName = '';
  String _groupType = 'Bible'; // 'Bible' or 'Devotional'

  String? _selectedBook;
  String? _selectedTopic;
  final TextEditingController _customTopicController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;

  bool _isLoading = false;

  final List<String> _commonTopics = [
    'Holiness',
    'Righteousness',
    'Love',
    'Marriage',
    'Joy',
    'Salvation',
    'Tithe',
  ];

  final List<String> _bibleBooks = [
    'Genesis',
    'Exodus',
    'Leviticus',
    'Numbers',
    'Deuteronomy',
    'Joshua',
    'Judges',
    'Ruth',
    '1 Samuel',
    '2 Samuel',
    '1 Kings',
    '2 Kings',
    '1 Chronicles',
    '2 Chronicles',
    'Ezra',
    'Nehemiah',
    'Esther',
    'Job',
    'Psalms',
    'Proverbs',
    'Ecclesiastes',
    'Song of Solomon',
    'Isaiah',
    'Jeremiah',
    'Lamentations',
    'Ezekiel',
    'Daniel',
    'Hosea',
    'Joel',
    'Amos',
    'Obadiah',
    'Jonah',
    'Micah',
    'Nahum',
    'Habakkuk',
    'Zephaniah',
    'Haggai',
    'Zechariah',
    'Malachi',
    'Matthew',
    'Mark',
    'Luke',
    'John',
    'Acts',
    'Romans',
    '1 Corinthians',
    '2 Corinthians',
    'Galatians',
    'Ephesians',
    'Philippians',
    'Colossians',
    '1 Thessalonians',
    '2 Thessalonians',
    '1 Timothy',
    '2 Timothy',
    'Titus',
    'Philemon',
    'Hebrews',
    'James',
    '1 Peter',
    '2 Peter',
    '1 John',
    '2 John',
    '3 John',
    'Jude',
    'Revelation',
  ];

  final Map<String, int> _bibleChapters = {
    'Genesis': 50,
    'Exodus': 40,
    'Leviticus': 27,
    'Numbers': 36,
    'Deuteronomy': 34,
    'Joshua': 24,
    'Judges': 21,
    'Ruth': 4,
    '1 Samuel': 31,
    '2 Samuel': 24,
    '1 Kings': 22,
    '2 Kings': 25,
    '1 Chronicles': 29,
    '2 Chronicles': 36,
    'Ezra': 10,
    'Nehemiah': 13,
    'Esther': 10,
    'Job': 42,
    'Psalms': 150,
    'Proverbs': 31,
    'Ecclesiastes': 12,
    'Song of Solomon': 8,
    'Isaiah': 66,
    'Jeremiah': 52,
    'Lamentations': 5,
    'Ezekiel': 48,
    'Daniel': 12,
    'Hosea': 14,
    'Joel': 3,
    'Amos': 9,
    'Obadiah': 1,
    'Jonah': 4,
    'Micah': 7,
    'Nahum': 3,
    'Habakkuk': 3,
    'Zephaniah': 3,
    'Haggai': 2,
    'Zechariah': 14,
    'Malachi': 4,
    'Matthew': 28,
    'Mark': 16,
    'Luke': 24,
    'John': 21,
    'Acts': 28,
    'Romans': 16,
    '1 Corinthians': 16,
    '2 Corinthians': 13,
    'Galatians': 6,
    'Ephesians': 6,
    'Philippians': 4,
    'Colossians': 4,
    '1 Thessalonians': 5,
    '2 Thessalonians': 3,
    '1 Timothy': 6,
    '2 Timothy': 4,
    'Titus': 3,
    'Philemon': 1,
    'Hebrews': 13,
    'James': 5,
    '1 Peter': 5,
    '2 Peter': 3,
    '1 John': 5,
    '2 John': 1,
    '3 John': 1,
    'Jude': 1,
    'Revelation': 22,
  };

  void _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(Duration(days: 365 * 5)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.gradientEnd,
              secondary: AppColors.gradientEnd,
              surface: Colors.white,
              onPrimary: Colors.white,
              onSurface: Theme.of(context).colorScheme.onSurface,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  void _createGroup() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select start and end dates.')),
      );
      return;
    }

    if (_groupType == 'Bible' && _selectedBook == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a Bible book.')),
      );
      return;
    }

    final finalTopic = _groupType == 'Topic'
        ? (_customTopicController.text.isNotEmpty
              ? _customTopicController.text
              : _selectedTopic)
        : null;

    if (_groupType == 'Topic' && (finalTopic == null || finalTopic.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or enter a topic.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final group = await widget.chatService.createGroup(
        name: _groupName,
        description: '',
        groupType: _groupType,
        topic: finalTopic,
        studyBook: _groupType == 'Bible' ? _selectedBook : null,
        totalChapters: _groupType == 'Bible'
            ? _bibleChapters[_selectedBook]!
            : (_endDate!.difference(_startDate!).inDays + 1),
        startDate: _startDate,
        endDate: _endDate,
      );

      if (mounted) {
        setState(() => _isLoading = false);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => StudyRoomScreen(
              group: group,
              showAddMemberPrompt: true, // Auto-popup Add Member
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Add Plan', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87))),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87)),      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: AppColors.gradientEnd),
            )
          : SingleChildScrollView(
              padding: EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      cursorColor: Theme.of(context).colorScheme.onSurface,
                      style: TextStyle(fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Group Name',
                        labelStyle: TextStyle(color: AppColors.primary),
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.gradientEnd.withValues(alpha: 0.5)),
                        ),
                      ),
                      validator: (val) =>
                          val == null || val.isEmpty ? 'Required' : null,
                      onChanged: (val) => _groupName = val,
                    ),
                    SizedBox(height: 24),

                    Text(
                      'Plan Type',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),

                    _buildPlanTypeCard(
                      title: 'Bible',
                      description:
                          'Choose one or more Bible books to read in your preferred order',
                      icon: Icons.menu_book,
                      isSelected: _groupType == 'Bible',
                      onTap: () => setState(() => _groupType = 'Bible'),
                    ),
                    SizedBox(height: 12),
                    _buildPlanTypeCard(
                      title: 'Topic',
                      description:
                          'Choose a topic to center your group discussion around',
                      icon: Icons.lightbulb_outline,
                      isSelected: _groupType == 'Topic',
                      onTap: () => setState(() => _groupType = 'Topic'),
                    ),
                    SizedBox(height: 24),

                    if (_groupType == 'Bible') ...[
                      Text(
                        'Select Book',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.gradientEnd.withValues(alpha: 0.5)),
                          ),
                        ),
                        initialValue: _selectedBook,
                        hint: Text('Choose a Bible Book'),
                        items: _bibleBooks.map((book) {
                          return DropdownMenuItem(
                            value: book,
                            child: Text(book),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _selectedBook = val),
                      ),
                    ] else ...[
                      Text(
                        'Select Topic',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.gradientEnd.withValues(alpha: 0.5)),
                          ),
                        ),
                        initialValue: _selectedTopic,
                        hint: Text('Choose a Topic'),
                        items: _commonTopics.map((topic) {
                          return DropdownMenuItem(
                            value: topic,
                            child: Text(topic),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedTopic = val;
                            _customTopicController.clear();
                          });
                        },
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Or type your own topic:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      TextFormField(
                        controller: _customTopicController,
                        cursorColor: Theme.of(context).colorScheme.onSurface,
                        decoration: InputDecoration(
                          hintText: 'Custom topic',
                          border: const OutlineInputBorder(),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.gradientEnd.withValues(alpha: 0.5)),
                          ),
                        ),
                        onChanged: (val) {
                          if (val.isNotEmpty && _selectedTopic != null) {
                            setState(() => _selectedTopic = null);
                          }
                        },
                      ),
                    ],

                    SizedBox(height: 24),
                    Text(
                      'Duration',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      leading: Icon(
                        Icons.calendar_today,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
                      ),
                      title: Text(
                        _startDate == null || _endDate == null
                            ? 'Select Start & End Date'
                            : '${DateFormat('MMM d, yyyy').format(_startDate!)} - ${DateFormat('MMM d, yyyy').format(_endDate!)}',
                      ),
                      onTap: _selectDateRange,
                    ),

                    SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _createGroup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gradientEnd,
                          foregroundColor: Colors.white,
                        ),
                        icon: Icon(Icons.check),
                        label: Text(
                          'Create Group & Invite',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                    SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPlanTypeCard({
    required String title,
    required String description,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? AppColors.primary : Theme.of(context).colorScheme.onSurface,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.05)
              : Theme.of(context).colorScheme.surface,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primary : Theme.of(context).colorScheme.onSurfaceVariant,
              size: 28,
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppColors.primary : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
