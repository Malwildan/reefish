import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Kept above map-covering sheets so the tile attribution stays visible.
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key});

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xEFFFFFFF),
    borderRadius: BorderRadius.circular(4),
    child: InkWell(
      onTap: () =>
          launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          '© OpenStreetMap contributors',
          style: TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 10,
            color: Color(0xFF102F3A),
          ),
        ),
      ),
    ),
  );
}
