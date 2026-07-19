import 'package:flutter/material.dart';
import '../theme.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  Widget _buildTopicHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0, left: 16.0, right: 16.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.gradientEnd,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget _buildFaqItem(BuildContext context, String question, String answer) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent, // removes the border inside ExpansionTile
        ),
        child: ExpansionTile(
          title: Text(
            question,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          iconColor: AppColors.gradientEnd,
          collapsedIconColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          childrenPadding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
          children: [
            Text(
              answer,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Frequently Asked Questions',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40.0, top: 8.0),
        children: [
          _buildTopicHeader(context, 'Topic 1: The Core Group Mechanics & Constraints'),
          _buildFaqItem(
            context,
            '1. Why is my group chat limited to only 12 people?',
            'Braid prioritizes genuine connection and intimate fellowship. By limiting groups to a maximum of 12 people, we ensure everyone remains truly accountable to one another without getting lost in a crowd.',
          ),
          _buildFaqItem(
            context,
            '2. Why did my group suddenly expire or split?',
            'Once a group reaches its limit and a study cycle ends, it splits to welcome new friends. This organic multiplication prevents spiritual stagnation and continuously expands the kingdom by allowing you to add new believers.',
          ),
          _buildFaqItem(
            context,
            '3. Why can\'t I just add my exact same friends back into a new group right away?',
            'To encourage continuous outreach, Braid uses a 30-day rule. Members cannot recreate a group with the exact same people for 30 days after a cycle ends. This naturally encourages you to reach out to other believers and new converts in your contacts.',
          ),
          _buildFaqItem(
            context,
            '4. Why does Braid limit the number of groups I can be in at once?',
            'We want to minimize the amount of group chats you are in because if you are in too many, you cannot be truly accountable to everybody. Braid focuses on deep spiritual growth, not casual, overwhelming chatter.',
          ),
          _buildFaqItem(
            context,
            '5. Do we need a pastor or church leader to lead our Braid group?',
            'No. Braid is a movement to empower everyday believers to take charge of their relationship with God. True growth happens when believers actively study the Word and admonish one another, rather than just relying on the physical church as a crutch.',
          ),
          _buildFaqItem(
            context,
            '6. What are we supposed to do in our group chats?',
            'Groups are meant for active Bible study. You can pick a chapter or book of the Bible for the week, deliberate on what you have learned, share personal insights, and help each other grow spiritually.',
          ),

          _buildTopicHeader(context, 'Topic 2: Insights Feed & Cross-Network Connectivity'),
          _buildFaqItem(
            context,
            '7. What is the "Insights" feed?',
            'Insights is a feature where anyone studying their Bible can share what they have learned with everyone in their contacts, completely outside of their immediate group chat. It allows you to share daily spiritual revelations with your wider network.',
          ),
          _buildFaqItem(
            context,
            '8. Why can I only direct-message people in my specific group?',
            'Braid is fundamentally built on intimate group fellowship. You cannot interact or chat directly with contacts unless you are in the same active group. However, you can interact with your wider contacts through the Insights comment section.',
          ),
          _buildFaqItem(
            context,
            '9. How did someone I don\'t even know comment on my Insight?',
            'Braid fosters communication through mutual friends in the faith. If a mutual friend comments on your post, their connections can see that comment and reply, allowing believers who don\'t know each other to connect organically.',
          ),
          _buildFaqItem(
            context,
            '10. Can I comment on a comment?',
            'Yes! In the Insights feed, you can reply directly to other people\'s comments. The comment threads act as meeting grounds, linking the body of Christ together through shared revelations.',
          ),

          _buildTopicHeader(context, 'Topic 3: Personal Notes & Spiritual Journaling'),
          _buildFaqItem(
            context,
            '11. Are my Notes public for everyone to see?',
            'No, the Notes feature allows you to type down your own personal notes while studying or at church, and they remain private even if you don\'t want to post them in your group chat.',
          ),
          _buildFaqItem(
            context,
            '12. Can I share my private Notes or save someone else\'s Insight?',
            'Absolutely. You can convert your private notes and publish them as Insights for your contacts to see. You can also save another user\'s Insight directly into your Notes if you find it meaningful, curating a personal spiritual library.',
          ),

          _buildTopicHeader(context, 'Topic 4: The Kingdom Network & Vision'),
          _buildFaqItem(
            context,
            '13. What is the Kingdom Network or Family Tree?',
            'It is a system to track your spiritual impact, operating similar to a family tree. When you invite new believers into the platform, they are placed under your tree, helping you build a network of people you are actively mentoring and growing with.',
          ),
          _buildFaqItem(
            context,
            '14. Is the Family Tree just about getting followers like other social media apps?',
            'No, Braid goes beyond just collecting followers for popularity. It is about keeping track of the specific people you bring into the platform so you can use it as a tool for evangelism and nurturing new converts.',
          ),
          _buildFaqItem(
            context,
            '15. Why is the app called "Braid"?',
            'The name comes from the act of braiding, where different stems come together to form something stronger. Believers entangle themselves to learn the Word of God and pray together, reflecting the biblical principle of "iron sharpens iron".',
          ),
          _buildTopicHeader(context, 'Topic 5: Navigating the 30-Day Rule & Connections'),
          _buildFaqItem(
            context,
            '16. How do I communicate with my close friends during the 30-day waitlist period?',
            'While you cannot recreate an active group chat with the exact same members for 30 days, you are not entirely cut off. You can still continuously interact with them by reading and commenting on their daily posts in the Insights feed.',
          ),
          _buildFaqItem(
            context,
            '17. Why do groups expire in the first place?',
            'Groups naturally conclude their cycles to prevent believers from getting too comfortable in one specific circle for years without reaching out to others. This mechanic ensures you are always incentivized to share the Word, invite new people, and continuously grow.',
          ),
          _buildFaqItem(
            context,
            '18. How do I find new people to form a group with after a cycle ends?',
            'You are encouraged to reach out to other believers in your contacts who are already on the app, invite new friends to the platform, or nurture new converts. As you do this over time, you will naturally build a wide network of believers who are free to join your future study cycles.',
          ),

          _buildTopicHeader(context, 'Topic 6: The Braid Ecosystem vs. Traditional Apps'),
          _buildFaqItem(
            context,
            '19. What makes Braid different from starting a Bible study group on WhatsApp or Telegram?',
            'Existing social apps are general-purpose and filled with everyday distractions. Braid is uniquely built as a dedicated digital space for spiritual growth, featuring forced organic multiplication, the 30-day rule to prevent stagnation, and targeted tools like Insights and Notes.',
          ),
          _buildFaqItem(
            context,
            '20. Why use the Braid "Notes" feature instead of my phone\'s default notes app?',
            'Braid integrates your spiritual journaling directly into your fellowship ecosystem. Unlike a standard notes app, Braid allows you to seamlessly convert your private thoughts into public Insights to bless your contacts, or directly save another user\'s powerful Insight into your own private library.',
          ),

          _buildTopicHeader(context, 'Topic 7: Evangelism & Expanding the Kingdom'),
          _buildFaqItem(
            context,
            '21. Can I use Braid to invite and talk to non-believers or new converts?',
            'Yes! Braid serves as an excellent tool for evangelism and follow-up. You can invite new converts to the platform, add them to a group to actively mentor and nurture their spiritual growth, and track your impact through the Kingdom Network family tree.',
          ),
          _buildFaqItem(
            context,
            '22. Does the 30-day waitlist mean I have to stop studying my Bible for a month?',
            'Not at all! Your daily personal study should always continue. The waitlist simply means you need to form a new group with different people, keeping the community expanding and breaking the habit of isolated or stagnant fellowship.',
          ),

          _buildTopicHeader(context, 'Topic 8: Privacy and Visibility'),
          _buildFaqItem(
            context,
            '23. Who exactly can see the Insights I publish?',
            'Your Insights are visible to anyone on the Braid platform who has your contact information. This allows you to share your daily spiritual revelations with a wider network of friends outside of your immediate 12-person group chat.',
          ),
          _buildFaqItem(
            context,
            '24. Can I save an Insight from someone else that really spoke to me?',
            'Yes, if you see an Insight from a friend or a mutual connection that is highly meaningful to you, you can save it directly into your personal Notes or repost it.',
          ),
          _buildFaqItem(
            context,
            '25. What happens if a mutual friend comments on my Insight?',
            'When someone comments on your post, that comment becomes visible to their connections as well. This creates a digital meeting ground, allowing second-tier networks—believers who might not know each other directly—to connect and interact organically through a shared spiritual revelation.',
          ),

          _buildTopicHeader(context, 'Topic 9: Group Extensions & Study Focus'),
          _buildFaqItem(
            context,
            '26. Our study time is almost up, but we aren\'t ready to disband yet. Can we extend our group?',
            'Yes! We understand that some studies take a bit more time. To prevent your fellowship from ending abruptly, you have the option to extend your group\'s duration before it expires. However, if your set duration elapses and you choose not to extend, the group will disband, and the 30-day waitlist will begin.',
          ),
          _buildFaqItem(
            context,
            '27. How many times can we extend our group chat?',
            'You can extend your current group a maximum of three times. After the third extension, the group will be forced to disband, and the standard 30-day waitlist rule will apply. This gives you extra time to dive deep into your studies while still ensuring the group eventually multiplies to welcome new believers.',
          ),
          _buildFaqItem(
            context,
            '28. If we extend our group, do we have to keep studying the exact same thing?',
            'Not at all! When you extend your group, you have the opportunity to change your current study focus. For example, if you just spent a month studying the topic of Marriage, you can extend the group and update your new focus to Love or Parenthood.',
          ),
          _buildFaqItem(
            context,
            '29. Can we switch from studying a Book of the Bible to studying a general Topic during an extension?',
            'No, you cannot switch between study types. If your group was initially created as a "Book" study (e.g., Genesis), you can only change to another book (e.g., Revelation) when you extend. To switch from a Book study to a Topic study, you will need to finish your current cycle and create a brand-new group.',
          ),
          _buildFaqItem(
            context,
            '30. What happens if our group is canceled or we forget to extend?',
            'Once a group reaches the end of its duration and is not extended, or if the group is manually canceled, it cannot be revived. The group will permanently close, and you will not be able to recreate a group with those exact same members until the 30-day cooldown period has passed.',
          ),
        ],
      ),
    );
  }
}
