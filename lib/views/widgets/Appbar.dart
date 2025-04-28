import 'package:flutter/material.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final bool showBackButton;
  final int cartItemCount;
  final VoidCallback? onCartPressed;
  final VoidCallback? onMenuPressed;

  const CustomAppBar({
    Key? key,
    this.title,
    this.showBackButton = false,
    this.cartItemCount = 0,
    this.onCartPressed,
    this.onMenuPressed,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 60);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 20,
        bottom: 24,
        left: 16,
        right: 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left side - Back or Menu button
          if (showBackButton)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.of(context).pop(),
            )
          else
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.black),
              onPressed: onMenuPressed,
            ),

          // Center - Title
          Expanded(
            child: Center(
              child: title != null
                  ? Text(
                      title!,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Text(
                      "RISTOCMD",
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
            ),
          ),

          // Right side - Cart with badge
          _buildCartWithBadge(context),
        ],
      ),
    );
  }

   Widget _buildCartWithBadge(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCartPressed,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(8.0), // Enlarge touch area
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.shopping_basket, color: Colors.black, size: 28),
              if (cartItemCount > 0)
                Positioned(
                  right: -7,
                  top: -9,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 19,
                      minHeight: 19,
                    ),
                    child: Center(
                      child: Text(
                        cartItemCount > 9 ? '9+' : cartItemCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

}
