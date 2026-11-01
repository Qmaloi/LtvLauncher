import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../models/link_card.dart';
import '../providers/apps_service.dart';
import '../providers/link_cards_service.dart';
import '../providers/settings_service.dart';
import 'category_container_common.dart';

class LinkCardsSection extends StatelessWidget {
  final Category category;
  final bool isFirstSection;

  const LinkCardsSection({
    super.key,
    required this.category,
    this.isFirstSection = false,
  });

  @override
  Widget build(BuildContext context) {
    final cards = context.select<LinkCardsService, List<LinkCard>>(
      (service) => service.cardsForCategory(category.id),
    );
    final showTitle = context.select<SettingsService, bool>((service) => service.showCategoryTitles);
    final showCount = context.select<SettingsService, bool>((service) => service.showCategoryAppCount);

    final content = cards.isEmpty
        ? categoryContainerEmptyState(context)
        : _buildGrid(context, cards);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Row(
              children: [
                Text(
                  category.name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        shadows: const [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 8)],
                      ),
                ),
                if (showCount) ...[
                  const SizedBox(width: 8),
                  Text('•  ${cards.length}', style: const TextStyle(color: Colors.white54)),
                ],
              ],
            ),
          ),
        content,
      ],
    );
  }

  Widget _buildRow(BuildContext context, List<LinkCard> cards) => SizedBox(
        height: category.rowHeight.toDouble(),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: cards.length,
          itemBuilder: (_, index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: LinkCardTile(
              card: cards[index],
              width: category.rowHeight * 16 / 9,
              autofocus: isFirstSection && index == 0,
            ),
          ),
        ),
      );

  Widget _buildGrid(BuildContext context, List<LinkCard> cards) => GridView.builder(
        clipBehavior: Clip.none,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: category.columnsCount,
          childAspectRatio: 16 / 9,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
        ),
        itemCount: cards.length,
        itemBuilder: (_, index) => LinkCardTile(
          card: cards[index],
          autofocus: isFirstSection && index == 0,
        ),
      );
}

class LinkCardTile extends StatefulWidget {
  final LinkCard card;
  final bool autofocus;
  final double? width;

  const LinkCardTile({
    super.key,
    required this.card,
    this.autofocus = false,
    this.width,
  });

  @override
  State<LinkCardTile> createState() => _LinkCardTileState();
}

class _LinkCardTileState extends State<LinkCardTile> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    await context.read<AppsService>().openUrl(widget.card.targetUrl);
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = context.select<SettingsService, Color>((service) => service.accentColor);

    final tile = Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          _open();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return AnimatedScale(
            scale: hasFocus ? 1.06 : 1.0,
            duration: const Duration(milliseconds: 160),
            child: Material(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              elevation: hasFocus ? 12 : 0,
              child: InkWell(
                onTap: _open,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.card.imageUrl.isNotEmpty)
                      Image.network(
                        widget.card.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _fallback(context),
                      )
                    else
                      _fallback(context),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withOpacity(0.82)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 8,
                      child: Text(
                        widget.card.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
                      ),
                    ),
                    if (hasFocus)
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: accentColor, width: 3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    return widget.width == null ? AspectRatio(aspectRatio: 16 / 9, child: tile) : SizedBox(width: widget.width, child: tile);
  }

  Widget _fallback(BuildContext context) => Container(
        color: Colors.white10,
        child: Center(
          child: Icon(Icons.link, size: 40, color: Theme.of(context).colorScheme.primary),
        ),
      );
}
