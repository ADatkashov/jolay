import 'package:flutter/material.dart';

import 'buttons.dart';
import 'icons.dart';
import 'tokens.dart';

class AppNavItem {
  final IconData icon, selectedIcon;
  final String label;
  final Key? key;
  const AppNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.key,
  });
}

/// Bottom navigation: 3–5 destinations, label always visible, yellow indicator, hairline top border.
/// One pattern for both apps — customer: Home · Activity · Wallet · Profile; driver: Home · Earnings · History · Profile.
class AppBottomNavigationBar extends StatelessWidget {
  final List<AppNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  const AppBottomNavigationBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final i in items)
            NavigationDestination(
              key: i.key,
              icon: Icon(i.icon),
              selectedIcon: Icon(i.selectedIcon),
              label: i.label,
            ),
        ],
      ),
    );
  }
}

/// Screen header. Use as `Scaffold.appBar` (it is a [PreferredSizeWidget]); a back button appears when the route can pop.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showBack;
  final VoidCallback? onBack;
  final String backLabel;
  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.showBack = true,
    this.onBack,
    this.backLabel = 'Back',
  });

  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 64 : 76);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final canPop = showBack && (onBack != null || Navigator.canPop(context));
    return Material(
      color: context.palette.background,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: preferredSize.height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                if (canPop) ...[
                  AppIconButton(
                    icon: AppIcons.back,
                    tooltip: backLabel,
                    style: AppIconButtonStyle.outlined,
                    onPressed: onBack ?? () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 8),
                ] else
                  const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: t.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: t.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Big in-page title for tab roots (Activity, Wallet, Profile …) where no back button is wanted.
class ScreenTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const ScreenTitle(this.title, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.gutter,
      20,
      AppSpacing.gutter,
      12,
    ),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Grouped list section (title + a bordered list of rows).
class SettingsGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const SettingsGroup({super.key, this.title, required this.children});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              title!,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: p.textSecondary),
            ),
          ),
        Material(
          color: p.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardR,
            side: BorderSide(color: p.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 56, color: p.divider),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A row for [SettingsGroup]: icon, title, optional trailing (chevron by default).
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final c = destructive ? p.error : p.textPrimary;
    return Semantics(
      button: onTap != null,
      label: subtitle == null ? title : '$title, $subtitle',
      excludeSemantics: onTap != null,
      onTap: onTap,
      child: InkWell(
        borderRadius: AppRadius.cardR,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: AppIconSize.lg,
                  color: destructive ? p.error : p.textSecondary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: t.titleSmall?.copyWith(
                          color: c,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null) Text(subtitle!, style: t.bodySmall),
                    ],
                  ),
                ),
                trailing ??
                    (onTap == null
                        ? const SizedBox.shrink()
                        : Icon(AppIcons.chevron, color: p.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
