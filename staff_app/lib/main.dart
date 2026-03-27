import 'dart:async';

import 'package:flutter/material.dart';

const String kBrandName = 'HEAVENECTION';
const Color kPrimary = Color(0xFF4D5C90);
const Color kPrimaryDark = Color(0xFF2E385E);
const Color kSoft = Color(0xFFE9ECF7);
const Color kBg = Color(0xFFF6F7FC);
const Color kGreen = Color(0xFF2D9D68);
const Color kOrange = Color(0xFFF0A53A);
const Color kRed = Color(0xFFD76666);

void main() => runApp(const HeavenectionApp());

class HeavenectionApp extends StatelessWidget {
  const HeavenectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: kBrandName,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kPrimary,
          primary: kPrimary,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: kPrimaryDark,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: kPrimaryDark,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      home: const HeavenectionHome(),
    );
  }
}

class HeavenectionHome extends StatefulWidget {
  const HeavenectionHome({super.key});

  @override
  State<HeavenectionHome> createState() => _HeavenectionHomeState();
}

class _HeavenectionHomeState extends State<HeavenectionHome> {
  final phone = TextEditingController();
  final password = TextEditingController();
  final leads = <Map<String, String>>[
    {
      'name': 'Priya Nair',
      'phone': '+91 98765 20145',
      'status': 'New',
      'note': 'Morning call preferred.',
    },
    {
      'name': 'Harish Kumar',
      'phone': '+91 99880 55421',
      'status': 'Call Back',
      'note': 'Call after 5 PM.',
    },
    {
      'name': 'Anjali Verma',
      'phone': '+91 91230 66745',
      'status': 'Interested',
      'note': 'Send pricing details.',
    },
  ];

  bool loggedIn = false;
  bool working = true;
  int tab = 0;
  int leadIndex = 0;
  String callStatus = 'Call Back';
  Duration elapsed = Duration.zero;
  Timer? timer;

  @override
  void dispose() {
    phone.dispose();
    password.dispose();
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!loggedIn) return _login();
    final lead = leads[leadIndex];
    final pages = [_dashboard(), _leads(), _call(lead)];

    return Scaffold(
      appBar: AppBar(
        title: const BrandWordmark(
          titleSize: 18,
          subtitle: 'CallTrack',
          subtitleSize: 11,
          markSize: 36,
        ),
      ),
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Leads',
          ),
          NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call),
            label: 'Call',
          ),
        ],
      ),
    );
  }

  Widget _login() {
    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kSoft, Colors.white, kSoft.withValues(alpha: 0.45)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: BrandWordmark(
                      centered: true,
                      titleSize: 30,
                      subtitle: 'CallTrack',
                      subtitleSize: 14,
                      markSize: 90,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Heavenection calling workspace for daily operations.',
                    style: TextStyle(fontSize: 17, color: Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: () => setState(() => loggedIn = true),
                    icon: const Icon(Icons.login),
                    label: const Text('Login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dashboard() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [kPrimaryDark, kPrimary]),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandWordmark(
                titleSize: 22,
                subtitle: 'Daily Overview',
                subtitleSize: 12,
                markSize: 48,
                onDark: true,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  working ? 'Work is active' : 'Work is not started',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Today at a glance',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Start work, review leads, and track daily activity.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: working
                    ? null
                    : () => setState(() => working = true),
                icon: const Icon(Icons.play_circle_fill),
                label: const Text('Start Work'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: working
                    ? () => setState(() => working = false)
                    : null,
                style: ElevatedButton.styleFrom(backgroundColor: kRed),
                icon: const Icon(Icons.stop_circle),
                label: const Text('End Work'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          'Today summary',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Row(
          children: const [
            Expanded(
              child: InfoCard(
                title: 'Hours',
                value: '05h 12m',
                color: kPrimary,
                icon: Icons.schedule,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: InfoCard(
                title: 'Calls',
                value: '31',
                color: kOrange,
                icon: Icons.call,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: InfoCard(
                title: 'Result',
                value: '9 interested',
                color: kGreen,
                icon: Icons.trending_up,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          onPressed: () => setState(() => tab = 1),
          icon: const Icon(Icons.people),
          label: const Text('Open Lead List'),
        ),
      ],
    );
  }

  Widget _leads() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const Text(
          'Assigned leads',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Today\'s calling queue and lead assignments.',
          style: TextStyle(fontSize: 16.5, color: Colors.black54),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < leads.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: kSoft,
                        foregroundColor: kPrimary,
                        child: Text(leads[i]['name']![0]),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              leads[i]['name']!,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              leads[i]['phone']!,
                              style: const TextStyle(
                                fontSize: 16.5,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      StatusPill(label: leads[i]['status']!),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(leads[i]['note']!, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () => setState(() {
                      leadIndex = i;
                      callStatus = leads[i]['status'] == 'Interested'
                          ? 'Interested'
                          : 'Call Back';
                      tab = 2;
                    }),
                    icon: const Icon(Icons.call),
                    label: const Text('Open Call Screen'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _call(Map<String, String> lead) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const Text(
          'Call screen',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Track call time and update the result after each call.',
          style: TextStyle(fontSize: 16.5, color: Colors.black54),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lead['name']!,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                lead['phone']!,
                style: const TextStyle(fontSize: 17, color: Colors.black54),
              ),
              const SizedBox(height: 6),
              Text(lead['note']!, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: kSoft,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Live timer',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _fmt(elapsed),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _startCall,
                      icon: const Icon(Icons.phone_forwarded),
                      label: const Text('Call'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _endCall,
                      style: ElevatedButton.styleFrom(backgroundColor: kRed),
                      icon: const Icon(Icons.call_end),
                      label: const Text('End Call'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Call result',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: ['Interested', 'Not Interested', 'No Answer', 'Call Back']
              .map(
                (item) => ChoiceChip(
                  selected: callStatus == item,
                  onSelected: (_) => setState(() => callStatus = item),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 6,
                    ),
                    child: Text(
                      item,
                      style: TextStyle(
                        color: callStatus == item ? Colors.white : kPrimaryDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  void _startCall() {
    timer?.cancel();
    setState(() => elapsed = Duration.zero);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => elapsed += const Duration(seconds: 1));
    });
  }

  void _endCall() {
    timer?.cancel();
    setState(() {
      leads[leadIndex]['status'] = callStatus;
      elapsed = Duration.zero;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${leads[leadIndex]['name']} marked as $callStatus'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    super.key,
    required this.titleSize,
    required this.subtitle,
    required this.subtitleSize,
    required this.markSize,
    this.centered = false,
    this.onDark = false,
  });

  final double titleSize;
  final String subtitle;
  final double subtitleSize;
  final double markSize;
  final bool centered;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final titleColor = onDark ? Colors.white : kPrimaryDark;
    final subtitleColor = onDark ? Colors.white70 : Colors.black54;

    return Row(
      mainAxisAlignment: centered
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      mainAxisSize: centered ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Image.asset(
          'assets/branding/heavenection_mark.png',
          width: markSize,
          height: markSize,
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: centered
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                kBrandName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: titleColor,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: subtitleColor,
                  fontSize: subtitleSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = switch (label) {
      'Interested' => kGreen,
      'Call Back' => kOrange,
      'No Answer' => kRed,
      _ => kPrimary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
