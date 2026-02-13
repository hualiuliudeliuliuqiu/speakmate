import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/scenario.dart';

class ScenarioCard extends StatelessWidget {
  final Scenario scenario;
  final VoidCallback onTap;
  final Color color;
  final Color lightColor;

  const ScenarioCard({
    super.key,
    required this.scenario,
    required this.onTap,
    this.color = AppTheme.primary,
    this.lightColor = AppTheme.primaryMuted,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: AppTheme.border.withValues(alpha: 0.5), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon with colored background
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: lightColor,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    scenario.icon,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingMd),
                Text(
                  scenario.title,
                  style: AppTheme.headingSm.copyWith(fontSize: 15),
                ),
                const SizedBox(height: AppTheme.spacingXs),
                Expanded(
                  child: Text(
                    scenario.description,
                    style: AppTheme.caption.copyWith(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Arrow indicator
                Align(
                  alignment: Alignment.bottomRight,
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: color.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
