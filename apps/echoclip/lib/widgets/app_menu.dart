part of '../main.dart';

/// Shared anchored menu for value pickers and contextual actions.
class AppMenuButton<T> extends StatefulWidget {
  const AppMenuButton({
    super.key,
    required this.itemBuilder,
    required this.onSelected,
    this.initialValue,
    this.enabled = true,
    this.tooltip,
    this.icon,
    this.child,
    this.childBuilder,
    this.matchAnchorWidth = false,
  });

  final PopupMenuItemBuilder<T> itemBuilder;
  final ValueChanged<T> onSelected;
  final T? initialValue;
  final bool enabled;
  final String? tooltip;
  final Widget? icon;
  final Widget? child;
  final Widget Function(BuildContext context, bool open)? childBuilder;
  final bool matchAnchorWidth;

  @override
  State<AppMenuButton<T>> createState() => _AppMenuButtonState<T>();
}

class _AppMenuButtonState<T> extends State<AppMenuButton<T>> {
  final _focusNode = FocusNode();
  final _anchorKey = GlobalKey();
  bool _open = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _showMenu() async {
    if (_open || !widget.enabled) return;
    final items = widget.itemBuilder(context);
    if (items.isEmpty) return;
    final navigator = Navigator.of(context);
    final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
    Rect anchorRect() {
      final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
      return box != null && box.attached
          ? box.localToGlobal(Offset.zero, ancestor: overlay) & box.size
          : Rect.zero;
    }

    final initialAnchor = anchorRect();
    final hasSelection = items.whereType<AppMenuItem<T>>().any(
      (item) =>
          item.checked == true ||
          (widget.initialValue != null && item.value == widget.initialValue),
    );
    var focused = false;
    final menuItems = <PopupMenuEntry<T>>[
      for (final item in items)
        if (item is AppMenuItem<T>)
          AppMenuItem<T>(
            key: item.key,
            value: item.value,
            enabled: item.enabled,
            checked:
                item.checked ??
                (widget.initialValue == null
                    ? null
                    : item.value == widget.initialValue),
            autofocus: !hasSelection && !focused && item.enabled
                ? (focused = true)
                : false,
            child: item.child!,
          )
        else
          item,
    ];
    final route = _AppMenuRoute<T>(
      items: menuItems,
      anchor: () {
        final current = anchorRect();
        return current == Rect.zero ? initialAnchor : current;
      },
      matchAnchorWidth: widget.matchAnchorWidth,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      label: MaterialLocalizations.of(context).popupMenuLabel,
      dismissLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
    setState(() => _open = true);
    final value = await navigator.push(route);
    if (!mounted) return;
    setState(() => _open = false);
    _focusNode.requestFocus();
    if (value != null) widget.onSelected(value);
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.childBuilder?.call(context, _open) ?? widget.child;
    return Semantics(
      key: _anchorKey,
      expanded: _open,
      child: child == null
          ? IconButton(
              focusNode: _focusNode,
              tooltip: widget.tooltip,
              onPressed: widget.enabled ? _showMenu : null,
              icon: widget.icon ?? const Icon(Icons.more_vert),
            )
          : Tooltip(
              message:
                  widget.tooltip ??
                  MaterialLocalizations.of(context).showMenuTooltip,
              child: InkWell(
                focusNode: _focusNode,
                onTap: widget.enabled ? _showMenu : null,
                canRequestFocus: widget.enabled,
                borderRadius: BorderRadius.circular(12),
                child: child,
              ),
            ),
    );
  }
}

/// A route keeps native back/escape dismissal and focus isolation. The layout
/// measures the menu before placing it, so short menus stay next to the field
/// and long menus open above it when there is more room there.
class _AppMenuRoute<T> extends PopupRoute<T> {
  _AppMenuRoute({
    required this.items,
    required this.anchor,
    required this.matchAnchorWidth,
    required this.themes,
    required this.label,
    required this.dismissLabel,
    required this.reduceMotion,
  }) : super(requestFocus: true);

  final List<PopupMenuEntry<T>> items;
  final Rect Function() anchor;
  final bool matchAnchorWidth;
  final CapturedThemes themes;
  final String label;
  final String dismissLabel;
  final bool reduceMotion;
  final _scrollController = ScrollController();

  @override
  bool get barrierDismissible => true;
  @override
  Color? get barrierColor => null;
  @override
  String get barrierLabel => dismissLabel;
  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 200);
  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 140);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return themes.wrap(
      LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          final bounds = Rect.fromLTRB(
            media.padding.left + 12,
            media.padding.top + 12,
            math.max(
              media.padding.left + 12,
              constraints.maxWidth - media.padding.right - 12,
            ),
            math.max(
              media.padding.top + 12,
              constraints.maxHeight -
                  math.max(media.padding.bottom, media.viewInsets.bottom) -
                  12,
            ),
          );
          final target = anchor();
          final desiredWidth = matchAnchorWidth
              ? target.width.clamp(200.0, 480.0)
              : (media.textScaler.scale(1) >= 1.5 ? 320.0 : 260.0);
          final width = math.min(desiredWidth, bounds.width);
          final height = math.min(360.0, bounds.height * .55);
          final curve = animation.drive(CurveTween(curve: Curves.easeOutCubic));
          return FocusTraversalGroup(
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
              },
              child: Actions(
                actions: {
                  DismissIntent: CallbackAction<DismissIntent>(
                    onInvoke: (_) {
                      navigator?.pop();
                      return null;
                    },
                  ),
                },
                child: CustomSingleChildLayout(
                  delegate: _AppMenuLayout(
                    anchor: target,
                    bounds: bounds,
                    textDirection: Directionality.of(context),
                  ),
                  child: FadeTransition(
                    opacity: curve,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: .97, end: 1).animate(curve),
                      alignment: target.center.dy > bounds.center.dy
                          ? Alignment.bottomCenter
                          : Alignment.topCenter,
                      child: Material(
                        type: MaterialType.card,
                        color: Colors.white,
                        surfaceTintColor: Colors.transparent,
                        shadowColor: const Color(0x18233E32),
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xFFDDE6E0)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: width,
                            maxWidth: width,
                            maxHeight: height,
                          ),
                          child: Semantics(
                            role: SemanticsRole.menu,
                            scopesRoute: true,
                            namesRoute: true,
                            explicitChildNodes: true,
                            label: label,
                            child: Scrollbar(
                              controller: _scrollController,
                              thumbVisibility: true,
                              radius: const Radius.circular(3),
                              thickness: 3,
                              child: SingleChildScrollView(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(6),
                                child: ListBody(children: items),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AppMenuLayout extends SingleChildLayoutDelegate {
  const _AppMenuLayout({
    required this.anchor,
    required this.bounds,
    required this.textDirection,
  });
  final Rect anchor;
  final Rect bounds;
  final TextDirection textDirection;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(bounds.size);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final below = bounds.bottom - anchor.bottom - 8;
    final above = anchor.top - bounds.top - 8;
    final y = below >= childSize.height || below >= above
        ? anchor.bottom + 8
        : anchor.top - childSize.height - 8;
    final x = textDirection == TextDirection.rtl
        ? anchor.right - childSize.width
        : anchor.left;
    return Offset(
      x.clamp(
        bounds.left,
        math.max(bounds.left, bounds.right - childSize.width),
      ),
      y.clamp(
        bounds.top,
        math.max(bounds.top, bounds.bottom - childSize.height),
      ),
    );
  }

  @override
  bool shouldRelayout(covariant _AppMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      bounds != oldDelegate.bounds ||
      textDirection != oldDelegate.textDirection;
}

class AppMenuChevron extends StatelessWidget {
  const AppMenuChevron({super.key, required this.open});
  final bool open;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
    turns: open ? .5 : 0,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    child: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
  );
}

class AppMenuItem<T> extends PopupMenuItem<T> {
  const AppMenuItem({
    super.key,
    super.value,
    super.enabled,
    required super.child,
    this.checked,
    this.autofocus = false,
  });
  final bool? checked;
  final bool autofocus;

  @override
  PopupMenuItemState<T, AppMenuItem<T>> createState() => _AppMenuItemState<T>();
}

class _AppMenuItemState<T> extends PopupMenuItemState<T, AppMenuItem<T>> {
  @override
  void initState() {
    super.initState();
    if (widget.checked == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Scrollable.ensureVisible(context, alignment: .5);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.checked == true;
    final color = !widget.enabled
        ? Theme.of(context).disabledColor
        : selected
        ? const Color(0xFF246B56)
        : const Color(0xFF314D40);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Semantics(
          role: SemanticsRole.menuItem,
          button: true,
          enabled: widget.enabled,
          selected: widget.checked,
          child: Material(
            color: selected ? const Color(0xFFE5F1EA) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.enabled ? handleTap : null,
              canRequestFocus: widget.enabled,
              autofocus: widget.enabled && (selected || widget.autofocus),
              borderRadius: BorderRadius.circular(10),
              hoverColor: const Color(0x0F426D58),
              focusColor: const Color(0x1F426D58),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: IconTheme.merge(
                    data: IconThemeData(color: color, size: 20),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: color,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      child: Row(
                        children: [
                          Expanded(child: widget.child!),
                          if (widget.checked != null) ...[
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 20,
                              child: selected
                                  ? const Icon(Icons.check_rounded, size: 20)
                                  : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A field-style trigger with the same menu as every other picker in the app.
class AppDropdownField<T> extends StatefulWidget {
  const AppDropdownField({
    super.key,
    required this.initialValue,
    required this.items,
    required this.onChanged,
    required this.decoration,
    this.isExpanded = true,
  });
  final T initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final bool isExpanded;

  bool get enabled => onChanged != null && items.isNotEmpty;

  @override
  State<AppDropdownField<T>> createState() => _AppDropdownFieldState<T>();
}

class _AppDropdownFieldState<T> extends State<AppDropdownField<T>> {
  late T _value = widget.initialValue;

  @override
  void didUpdateWidget(covariant AppDropdownField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      _value = widget.initialValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.items
        .where((item) => item.value == _value)
        .firstOrNull;
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: Color(0xFFD3DFD9)),
    );
    return AppMenuButton<T>(
      enabled: widget.enabled,
      tooltip: widget.decoration.labelText,
      matchAnchorWidth: true,
      initialValue: _value,
      onSelected: (value) {
        setState(() => _value = value);
        widget.onChanged?.call(value);
      },
      itemBuilder: (_) => [
        for (final item in widget.items)
          AppMenuItem<T>(
            value: item.value,
            enabled: item.enabled,
            // Closed fields may truncate long device names. The menu wraps
            // them so the full option remains readable, including large type.
            child: item.child is Text && (item.child as Text).data != null
                ? Text((item.child as Text).data!)
                : item.child,
          ),
      ],
      childBuilder: (context, open) => InputDecorator(
        isFocused: open,
        decoration: widget.decoration.copyWith(
          enabled: widget.enabled,
          filled: true,
          fillColor: widget.enabled
              ? const Color(0xFFF6F8F7)
              : const Color(0xFFF1F4F2),
          border: border,
          enabledBorder: border,
          disabledBorder: border.copyWith(
            borderSide: const BorderSide(color: Color(0xFFE0E7E3)),
          ),
          focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: Color(0xFF789C8B), width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          suffixIcon: AppMenuChevron(open: open),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: 14,
            color: widget.enabled
                ? const Color(0xFF314D40)
                : Theme.of(context).disabledColor,
          ),
          child: selected?.child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
