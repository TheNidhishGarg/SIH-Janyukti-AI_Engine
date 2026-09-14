// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';

class StatusCard extends StatelessWidget {
  const StatusCard({
    Key? key,
    required this.count,
    required this.label,
    required this.icon,
    required this.color,
  }) : super(key: key);

  final int count;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withOpacity(.055),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: color.withOpacity(.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: color.withOpacity(.13),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const Spacer(),
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF101B42),
                ),
              ),
            ],
          ),
          Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF596579),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
