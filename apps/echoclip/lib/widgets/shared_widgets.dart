part of '../main.dart';

class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE0E7E3)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.alignActionsWithTitle = false,
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool alignActionsWithTitle;

  @override
  Widget build(BuildContext context) {
    final titleWidget = Text(
      title,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: const Color(0xFF233E32),
      ),
    );
    Widget withSubtitle(Widget primary) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        primary,
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6A7D73)),
          ),
        ],
      ],
    );
    final heading = withSubtitle(titleWidget);
    if (actions.isEmpty) return heading;
    return LayoutBuilder(
      builder: (context, constraints) {
        final controls = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: actions,
        );
        if (constraints.maxWidth < (alignActionsWithTitle ? 280 : 440) ||
            MediaQuery.textScalerOf(context).scale(1) >= 1.5) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              const SizedBox(height: 12),
              if (alignActionsWithTitle)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: controls,
                )
              else
                controls,
            ],
          );
        }
        if (alignActionsWithTitle && !_isDesktopPlatform) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: heading),
              const SizedBox(width: 16),
              controls,
            ],
          );
        }
        final row = Row(
          crossAxisAlignment: _isDesktopPlatform
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Expanded(child: alignActionsWithTitle ? titleWidget : heading),
            const SizedBox(width: 16),
            controls,
          ],
        );
        return alignActionsWithTitle ? withSubtitle(row) : row;
      },
    );
  }
}

class _SurfaceIcon extends StatelessWidget {
  const _SurfaceIcon(this.icon, {this.active = false});
  final IconData icon;
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: active ? const Color(0xFFDCEDE5) : const Color(0xFFEDF3EF),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, size: 21, color: const Color(0xFF426D58)),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.icon});
  final String title;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (icon != null) ...[_SurfaceIcon(icon!), const SizedBox(width: 12)],
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: const Color(0xFF243E33),
          ),
        ),
      ),
    ],
  );
}

class _PageEmptyState extends StatelessWidget {
  const _PageEmptyState({
    required this.icon,
    required this.title,
    this.description,
  });
  final IconData icon;
  final String title;
  final String? description;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Color(0xFFEAF1ED),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 32, color: const Color(0xFF789485)),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: const Color(0xFF243E33)),
        ),
        if (description != null) ...[
          const SizedBox(height: 8),
          Text(
            description!,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF718378)),
          ),
        ],
      ],
    ),
  );
}
