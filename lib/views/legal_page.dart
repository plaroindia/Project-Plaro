import 'package:flutter/material.dart';

/// Single page that shows either Terms of Service or Privacy Policy.
/// Pass [showTerms: true] for T&C, [showTerms: false] for Privacy.
class LegalPage extends StatefulWidget {
  final bool showTerms;
  const LegalPage({super.key, required this.showTerms});

  @override
  State<LegalPage> createState() => _LegalPageState();
}

class _LegalPageState extends State<LegalPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this, initialIndex: widget.showTerms ? 0 : 1);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Legal',
            style: TextStyle(color: theme.colorScheme.onSurface,
                fontSize: 18, fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tab,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
          indicatorColor: theme.colorScheme.primary,
          indicatorWeight: 2,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [Tab(text: 'Terms of Service'), Tab(text: 'Privacy Policy')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _LegalContent(sections: _termsContent, isDark: isDark),
          _LegalContent(sections: _privacyContent, isDark: isDark),
        ],
      ),
    );
  }
}

class _LegalContent extends StatelessWidget {
  final List<_Section> sections;
  final bool isDark;
  const _LegalContent({required this.sections, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        // Last updated notice
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Last updated: April 2025',
            style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 24),
        ...sections.map((s) => _SectionWidget(section: s, isDark: isDark)),
      ],
    );
  }
}

class _SectionWidget extends StatelessWidget {
  final _Section section;
  final bool isDark;
  const _SectionWidget({required this.section, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(section.title,
            style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.3)),
        const SizedBox(height: 8),
        Text(section.body,
            style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.65),
                fontSize: 13,
                height: 1.7)),
      ]),
    );
  }
}

class _Section {
  final String title;
  final String body;
  const _Section(this.title, this.body);
}

// ─── Content ──────────────────────────────────────────────────────────────────

const _termsContent = [
  _Section(
    '1. Acceptance of Terms',
    'By creating an account or using Plaro ("the App"), you agree to be bound by these Terms of Service. If you do not agree to these terms, do not use the App. These terms apply to all users, including visitors, registered users, and contributors of content.',
  ),
  _Section(
    '2. Description of Service',
    'Plaro is a learning and content platform that lets users create, share, and interact with educational content in the form of Posts, Bytes (short videos), and Taikens (interactive experiences). The App is intended for users aged 13 and above.',
  ),
  _Section(
    '3. User Accounts',
    'You are responsible for maintaining the confidentiality of your account credentials. You agree to provide accurate information when creating your account and to update it as needed. You must not share your account or allow others to use it. We reserve the right to suspend or terminate accounts that violate these terms.',
  ),
  _Section(
    '4. User-Generated Content',
    'You retain ownership of the content you create and share on Plaro. By posting content, you grant Plaro a non-exclusive, royalty-free, worldwide license to display, distribute, and promote that content within the App. You are solely responsible for ensuring your content does not violate any laws or third-party rights.',
  ),
  _Section(
    '5. Prohibited Conduct',
    'You agree not to post content that is illegal, harmful, threatening, abusive, harassing, defamatory, or otherwise objectionable. You may not use the App to spam, distribute malware, impersonate others, or engage in any activity that disrupts the App or its users. Violations may result in immediate account termination.',
  ),
  _Section(
    '6. Intellectual Property',
    'All original content, branding, logos, and software associated with Plaro are the property of Plaro and its licensors. You may not copy, modify, distribute, or reverse-engineer any part of the platform without our explicit written permission.',
  ),
  _Section(
    '7. Termination',
    'We may suspend or terminate your access to Plaro at any time, with or without notice, if you violate these Terms or for any other reason at our sole discretion. You may also delete your account at any time through the Settings page.',
  ),
  _Section(
    '8. Disclaimer of Warranties',
    'Plaro is provided on an "as is" and "as available" basis without any warranties of any kind, either express or implied. We do not guarantee that the App will be uninterrupted, error-free, or free of viruses or other harmful components.',
  ),
  _Section(
    '9. Limitation of Liability',
    'To the fullest extent permitted by applicable law, Plaro and its team shall not be liable for any indirect, incidental, special, consequential, or punitive damages arising from your use of or inability to use the App.',
  ),
  _Section(
    '10. Changes to These Terms',
    'We may update these Terms from time to time. We will notify you of significant changes by updating the date at the top of this page. Your continued use of the App after changes are posted constitutes your acceptance of the revised terms.',
  ),
  _Section(
    '11. Contact',
    'If you have any questions about these Terms, please reach out to us through the Help & FAQ section in the App or via our website.',
  ),
];

const _privacyContent = [
  _Section(
    '1. Information We Collect',
    'We collect information you provide directly, such as your name, email address, profile picture, and content you post. We also collect usage data automatically, including device information, IP address, pages visited, and interaction timestamps, to improve the App experience.',
  ),
  _Section(
    '2. How We Use Your Information',
    'We use your information to operate and improve the App, personalise your experience, send you notifications (if enabled), enforce our Terms of Service, and comply with legal obligations. We do not sell your personal data to third parties.',
  ),
  _Section(
    '3. Data Storage',
    'Your data is stored securely using Supabase, a trusted backend-as-a-service provider. Data is stored on servers hosted by reputable cloud providers with industry-standard security practices, including encryption at rest and in transit.',
  ),
  _Section(
    '4. Sharing of Information',
    'We do not share your personal information with third parties except in the following cases: with your consent; to comply with legal requirements; to protect the rights and safety of Plaro, our users, or the public; or in connection with a merger, acquisition, or sale of assets.',
  ),
  _Section(
    '5. Cookies and Tracking',
    'The App may use cookies and similar technologies to maintain session state and improve performance. You can control cookie settings through your device settings, though disabling them may affect certain App features.',
  ),
  _Section(
    '6. Your Rights',
    'Depending on your location, you may have the right to access, correct, or delete your personal data. You can update your profile information at any time in the App. To request full data deletion, use the Delete Account option in Settings, or contact us through the Help section.',
  ),
  _Section(
    '7. Data Retention',
    'We retain your personal data for as long as your account is active or as needed to provide services. After account deletion, we may retain certain anonymised data for analytics purposes, but personal identifiers are removed.',
  ),
  _Section(
    '8. Children\'s Privacy',
    'Plaro is not directed at children under the age of 13. We do not knowingly collect personal information from children under 13. If we become aware that a child under 13 has provided us with personal data, we will take steps to delete that information promptly.',
  ),
  _Section(
    '9. Third-Party Services',
    'The App integrates with third-party services such as Google Sign-In. These services have their own privacy policies, and we encourage you to review them. We are not responsible for the privacy practices of third-party services.',
  ),
  _Section(
    '10. Security',
    'We take reasonable technical and organisational measures to protect your data against unauthorised access, alteration, disclosure, or destruction. However, no method of transmission over the internet is 100% secure, and we cannot guarantee absolute security.',
  ),
  _Section(
    '11. Changes to This Policy',
    'We may update this Privacy Policy from time to time. We will notify you of significant changes by updating the date at the top of this document. Continued use of the App after changes are posted constitutes acceptance of the revised policy.',
  ),
  _Section(
    '12. Contact',
    'If you have questions or concerns about this Privacy Policy or how your data is handled, please contact us through the Help & FAQ section in the App or via our website.',
  ),
];