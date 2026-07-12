import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TtsSettingsScreen extends StatefulWidget {
  const TtsSettingsScreen({super.key});

  @override
  State<TtsSettingsScreen> createState() => _TtsSettingsScreenState();
}

class _TtsSettingsScreenState extends State<TtsSettingsScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  List<Map<String, String>> _voices = [];
  String? _selectedVoiceName;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedVoiceName = prefs.getString('tts_voice_name');

    List<dynamic> voices = await _flutterTts.getVoices;
    
    // Group voices by locale
    List<Map<String, String>> usVoices = [];
    List<Map<String, String>> gbVoices = [];
    List<Map<String, String>> auVoices = [];

    for (var v in voices) {
      if (v is Map) {
        final locale = v['locale']?.toString() ?? '';
        final name = v['name']?.toString() ?? '';
        if (locale.startsWith('en-US')) {
          usVoices.add({'name': name, 'locale': locale});
        } else if (locale.startsWith('en-GB')) {
          gbVoices.add({'name': name, 'locale': locale});
        } else if (locale.startsWith('en-AU')) {
          auVoices.add({'name': name, 'locale': locale});
        }
      }
    }

    // Limit and map names
    List<Map<String, String>> mappedVoices = [];
    
    // US Voices
    for (int i = 0; i < usVoices.length && i < 4; i++) {
      mappedVoices.add({
        'originalName': usVoices[i]['name']!,
        'displayName': 'Voice ${i + 1} (US)',
        'locale': usVoices[i]['locale']!,
      });
    }

    // GB Voices
    for (int i = 0; i < gbVoices.length && i < 4; i++) {
      mappedVoices.add({
        'originalName': gbVoices[i]['name']!,
        'displayName': 'Voice ${i + 1} (GB)',
        'locale': gbVoices[i]['locale']!,
      });
    }

    // AU Voices
    for (int i = 0; i < auVoices.length && i < 2; i++) {
      mappedVoices.add({
        'originalName': auVoices[i]['name']!,
        'displayName': 'Voice ${i + 1} (AU)',
        'locale': auVoices[i]['locale']!,
      });
    }

    if (mounted) {
      setState(() {
        _voices = mappedVoices;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectVoice(Map<String, String> voice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tts_voice_name', voice['originalName']!);
    await prefs.setString('tts_voice_locale', voice['locale']!);
    
    setState(() {
      _selectedVoiceName = voice['originalName'];
    });

    // Test the voice
    await _flutterTts.setVoice({"name": voice['originalName']!, "locale": voice['locale']!});
    await _flutterTts.speak('This is how I sound.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reading Voice'),
        backgroundColor: Colors.white,
      ),
      backgroundColor: Colors.white,
      body: _isLoading 
        ? Center(child: CircularProgressIndicator())
        : ListView.builder(
            itemCount: _voices.length,
            itemBuilder: (context, index) {
              final voice = _voices[index];
              final isSelected = _selectedVoiceName == voice['originalName'];
              return ListTile(
                title: Text('${voice['displayName']}'),
                subtitle: const Text('Tap to select and hear a sample'),
                trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.green) : null,
                onTap: () => _selectVoice(voice),
              );
            },
          ),
    );
  }
}
