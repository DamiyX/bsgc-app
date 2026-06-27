import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../services/chat_service.dart';
import '../models/group_model.dart';
import 'study_room_screen.dart';
import '../theme.dart';

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
    'Holiness', 'Righteousness', 'Love', 'Marriage', 'Joy', 'Salvation', 'Tithe'
  ];

  final List<String> _bibleBooks = [
    'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy', 'Joshua', 'Judges', 'Ruth',
    '1 Samuel', '2 Samuel', '1 Kings', '2 Kings', '1 Chronicles', '2 Chronicles', 'Ezra',
    'Nehemiah', 'Esther', 'Job', 'Psalms', 'Proverbs', 'Ecclesiastes', 'Song of Solomon',
    'Isaiah', 'Jeremiah', 'Lamentations', 'Ezekiel', 'Daniel', 'Hosea', 'Joel', 'Amos',
    'Obadiah', 'Jonah', 'Micah', 'Nahum', 'Habakkuk', 'Zephaniah', 'Haggai', 'Zechariah',
    'Malachi', 'Matthew', 'Mark', 'Luke', 'John', 'Acts', 'Romans', '1 Corinthians',
    '2 Corinthians', 'Galatians', 'Ephesians', 'Philippians', 'Colossians',
    '1 Thessalonians', '2 Thessalonians', '1 Timothy', '2 Timothy', 'Titus', 'Philemon',
    'Hebrews', 'James', '1 Peter', '2 Peter', '1 John', '2 John', '3 John', 'Jude', 'Revelation'
  ];
  
  final Map<String, int> _bibleChapters = {
    'Genesis': 50, 'Exodus': 40, 'Leviticus': 27, 'Numbers': 36, 'Deuteronomy': 34,
    'Joshua': 24, 'Judges': 21, 'Ruth': 4, '1 Samuel': 31, '2 Samuel': 24,
    '1 Kings': 22, '2 Kings': 25, '1 Chronicles': 29, '2 Chronicles': 36, 'Ezra': 10,
    'Nehemiah': 13, 'Esther': 10, 'Job': 42, 'Psalms': 150, 'Proverbs': 31,
    'Ecclesiastes': 12, 'Song of Solomon': 8, 'Isaiah': 66, 'Jeremiah': 52,
    'Lamentations': 5, 'Ezekiel': 48, 'Daniel': 12, 'Hosea': 14, 'Joel': 3,
    'Amos': 9, 'Obadiah': 1, 'Jonah': 4, 'Micah': 7, 'Nahum': 3, 'Habakkuk': 3,
    'Zephaniah': 3, 'Haggai': 2, 'Zechariah': 14, 'Malachi': 4, 'Matthew': 28,
    'Mark': 16, 'Luke': 24, 'John': 21, 'Acts': 28, 'Romans': 16, '1 Corinthians': 16,
    '2 Corinthians': 13, 'Galatians': 6, 'Ephesians': 6, 'Philippians': 4,
    'Colossians': 4, '1 Thessalonians': 5, '2 Thessalonians': 3, '1 Timothy': 6,
    '2 Timothy': 4, 'Titus': 3, 'Philemon': 1, 'Hebrews': 13, 'James': 5,
    '1 Peter': 5, '2 Peter': 3, '1 John': 5, '2 John': 1, '3 John': 1,
    'Jude': 1, 'Revelation': 22
  };

  void _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
            ),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select start and end dates.')));
      return;
    }
    
    if (_groupType == 'Bible' && _selectedBook == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a Bible book.')));
      return;
    }
    
    final finalTopic = _groupType == 'Topic' 
        ? (_customTopicController.text.isNotEmpty ? _customTopicController.text : _selectedTopic)
        : null;
        
    if (_groupType == 'Topic' && (finalTopic == null || finalTopic.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select or enter a topic.')));
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
        totalChapters: _groupType == 'Bible' ? _bibleChapters[_selectedBook]! : 0,
        startDate: _startDate,
        endDate: _endDate,
      );

      if (mounted) {
        Navigator.pop(context);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => StudyRoomScreen(group: group)),
        );
        
        // Prompt to share
        final inviteLink = "https://bsgc.app/join/${group.id}";
        final message = "Hey! Join my Bible study group '${group.name}' on BSGC App.\n\nTap here to join: $inviteLink";
        Share.share(message);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Add Plan', style: TextStyle(color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black87))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Group Name',
                        border: OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.black87)),
                      ),
                      validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                      onChanged: (val) => _groupName = val,
                    ),
                    const SizedBox(height: 24),

                    const Text('Plan Type', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    
                    _buildPlanTypeCard(
                      title: 'Bible',
                      description: 'Choose one or more Bible books to read in your preferred order',
                      icon: Icons.menu_book,
                      isSelected: _groupType == 'Bible',
                      onTap: () => setState(() => _groupType = 'Bible'),
                    ),
                    const SizedBox(height: 12),
                    _buildPlanTypeCard(
                      title: 'Topic',
                      description: 'Choose a topic to center your group discussion around',
                      icon: Icons.lightbulb_outline,
                      isSelected: _groupType == 'Topic',
                      onTap: () => setState(() => _groupType = 'Topic'),
                    ),
                    const SizedBox(height: 24),

                    if (_groupType == 'Bible') ...[
                      const Text('Select Book', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                        value: _selectedBook,
                        hint: const Text('Choose a Bible Book'),
                        items: _bibleBooks.map((book) {
                          return DropdownMenuItem(value: book, child: Text(book));
                        }).toList(),
                        onChanged: (val) => setState(() => _selectedBook = val),
                      ),
                    ] else ...[
                      const Text('Select Topic', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                        value: _selectedTopic,
                        hint: const Text('Choose a Topic'),
                        items: _commonTopics.map((topic) {
                          return DropdownMenuItem(value: topic, child: Text(topic));
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedTopic = val;
                            _customTopicController.clear();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      const Text('Or type your own topic:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _customTopicController,
                        decoration: const InputDecoration(
                          hintText: 'Custom topic',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) {
                          if (val.isNotEmpty && _selectedTopic != null) {
                            setState(() => _selectedTopic = null);
                          }
                        },
                      ),
                    ],

                    const SizedBox(height: 24),
                    const Text('Duration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: Colors.black12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      leading: const Icon(Icons.calendar_today, color: Colors.black87),
                      title: Text(
                        _startDate == null || _endDate == null
                            ? 'Select Start & End Date'
                            : '${DateFormat('MMM d, yyyy').format(_startDate!)} - ${DateFormat('MMM d, yyyy').format(_endDate!)}',
                      ),
                      onTap: _selectDateRange,
                    ),

                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _createGroup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.check),
                        label: const Text('Create Group & Invite', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 24),
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: isSelected ? AppColors.primary : Colors.black12, width: isSelected ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? AppColors.primary.withValues(alpha: 0.05) : Colors.white,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: isSelected ? AppColors.primary : Colors.black54, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppColors.primary : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(color: Colors.black54),
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
