import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final user = FirebaseAuth.instance.currentUser;

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || user == null) return;

    _messageController.clear();

    await FirebaseFirestore.instance.collection('support_chats').add({
      'senderId': user!.uid,
      'senderName': user!.displayName ?? 'Believer',
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'isReadByAdmin': false,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Help & Support', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 1,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          // FAQ Section at the top
          Container(
            padding: EdgeInsets.symmetric(vertical: 16),
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text('Frequently Asked Questions', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54))),
                ),
                SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      _buildFaqBubble('Direct vs. Indirect Network?'),
                      _buildFaqBubble('How do Insights & Comments work?'),
                      _buildFaqBubble('Cooldown times for members?'),
                      _buildFaqBubble('Why are these mechanics different?'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Chat messages area (stream from support_chats where senderId == user.uid)
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('support_chats')
                  .where('senderId', isEqualTo: user?.uid)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: AppColors.gradientEnd));
                }
                
                final docs = snapshot.data?.docs ?? [];
                
                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text(
                        'Have a question or feedback? Send us a message and we will respond as soon as possible.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final isUserMessage = data['senderId'] == user?.uid && data['adminReply'] != true;
                    final text = data['text'] ?? '';

                    return Align(
                      alignment: isUserMessage ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: EdgeInsets.only(bottom: 12),
                        constraints: const BoxConstraints(maxWidth: 300),
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isUserMessage ? AppColors.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16).copyWith(
                            bottomRight: isUserMessage ? const Radius.circular(0) : const Radius.circular(16),
                            bottomLeft: !isUserMessage ? const Radius.circular(0) : const Radius.circular(16),
                          ),
                        ),
                        child: Text(
                          text,
                          style: TextStyle(
                            color: isUserMessage ? Colors.white : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          
          // Chat Input Area
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(top: BorderSide(color: Theme.of(context).colorScheme.surfaceContainerHighest)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.mic, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Voice recording for support coming soon.')),
                      );
                    },
                  ),
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          hintText: 'Message Support...',
                          border: InputBorder.none,
                        ),
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.send, color: AppColors.gradientEnd),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaqBubble(String question) {
    return GestureDetector(
      onTap: () => _triggerFaqResponse(question),
      child: Container(
        margin: EdgeInsets.only(right: 8),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Text(
          question,
          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87)),
        ),
      ),
    );
  }

  Future<void> _triggerFaqResponse(String question) async {
    if (user == null) return;
    
    String answer = '';
    
    if (question.contains('Direct vs. Indirect Network')) {
      answer = "In Braid, your Direct Network consists of the friends you have explicitly added and connected with. Your Indirect Network includes the friends of those friends (2nd and 3rd-degree connections). This encourages meaningful, organic discovery of people within trusted circles rather than randomly suggesting strangers.";
    } else if (question.contains('How do Insights & Comments work')) {
      answer = "When you publish an Insight, your direct contacts can view it. If a mutual friend (someone you don't know directly, but who is friends with the author) comments on an Insight, you will see their comment and their chosen username. This allows you to interact and comment on the same Insight safely, bridging the gap between mutuals without requiring a direct connection!";
    } else if (question.contains('Cooldown times')) {
      answer = "When you part ways with a group or a past member, Braid enforces a 30-day cooldown period before you can re-engage with them. This is designed to prevent impulsive behavior, encourage intentional relationships, and reduce toxicity, mimicking how time and space work in real life.";
    } else if (question.contains('Why are these mechanics different')) {
      answer = "Braid is built differently from traditional social media. Traditional platforms optimize for endless scrolling, viral addiction, and connecting you with as many strangers as possible. Braid optimizes for intentional, meaningful relationships. Mechanics like network boundaries and cooldowns exist to make your connections feel grounded, safe, and deliberate.";
    } else {
      answer = "Thank you for your question. We have received it and will get back to you shortly.";
    }

    // First log the user's question as a message
    await FirebaseFirestore.instance.collection('support_chats').add({
      'senderId': user!.uid,
      'senderName': user!.displayName ?? 'Believer',
      'text': question,
      'createdAt': FieldValue.serverTimestamp(),
      'isReadByAdmin': true,
      'isFaqRequest': true,
    });

    // Then simulate a brief typing delay and insert the automated admin response
    await Future.delayed(const Duration(milliseconds: 600));

    await FirebaseFirestore.instance.collection('support_chats').add({
      'senderId': 'admin',
      'senderName': 'Braid Support',
      'text': answer,
      'createdAt': FieldValue.serverTimestamp(),
      'adminReply': true,
    });
  }
}
