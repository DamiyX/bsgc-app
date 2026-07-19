import 'package:flutter/material.dart';
import '../theme.dart';

class AboutPlatformScreen extends StatelessWidget {
  const AboutPlatformScreen({super.key});

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 12.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.gradientEnd,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget _buildPhilosophyCard(BuildContext context, String title, String body) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'About the Platform',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  margin: const EdgeInsets.only(bottom: 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/icon2.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              Text(
                'Braid is a platform built to recreate the intimate fellowship of the early church in a digital space. We believe that spiritual growth should not be limited to a "Sunday-to-Sunday" schedule, where connection only happens one day a week.\n\nThis is why we provide a continuous digital ecosystem for believers to interact and study the Bible together all week long. As the scripture says, "Iron sharpeneth iron," and here we come together to sharpen ourselves throughout the week rather than remaining isolated.\n\nWe study together to stay accountable, aiming for true spiritual transformation and growth. Rather than just casually identifying as believers, our mission is to actually be doers of the word who practicalize our faith daily.',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                  height: 1.6,
                ),
              ),
              _buildSectionTitle(context, 'How We Grow Together'),
              _buildPhilosophyCard(
                context,
                'The Braid Philosophy',
                'The core purpose of our name is to represent the idea of letting everyone grow together. Just as a braid weaves different stems together to form something stronger, we entangle ourselves to learn the word of God and pray together.',
              ),
              _buildPhilosophyCard(
                context,
                'Intentional Accountability',
                'By limiting core study groups to 12 people, we ensure everyone remains truly accountable to one another without getting lost in a crowd.',
              ),
              _buildPhilosophyCard(
                context,
                'Continuous Outreach',
                'To prevent stagnation, members cannot recreate a group with the exact same people for 30 days after a cycle ends. This naturally encourages you to reach out to other believers and new converts, fostering a culture of continuous evangelism.',
              ),
              _buildPhilosophyCard(
                context,
                'Shared Revelations via Insights',
                'Step outside your immediate group chat and share your biblical insights with your entire contact list. When you comment on a friend\'s post, their other friends can see and reply to you, linking the body of Christ together.',
              ),
              _buildPhilosophyCard(
                context,
                'Capture the Word',
                'Document your private study, easily publish your notes as Insights to bless others, or curate a personal library by saving powerful Insights posted by fellow believers.',
              ),
              _buildPhilosophyCard(
                context,
                'Kingdom Network',
                'Build a spiritual family tree by inviting new believers, keeping track of the people you bring into the platform.',
              ),
              const SizedBox(height: 40),
              Center(
                child: Text(
                  '"Fellowship beyond Sundays. Weaving believers together."',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
