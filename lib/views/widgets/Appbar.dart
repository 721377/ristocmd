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
        color: Color.fromARGB(255, 255, 198, 65),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        border: Border.all(color: const Color.fromARGB(255, 218, 218, 218),width:1),
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
             Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color.fromARGB(255, 27, 27, 27).withOpacity(0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 20,
                        color: Color.fromARGB(255, 255, 198, 65),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
          // Left side - Back or Menu button

          // Center - Title
          Expanded(
            child: Center(
              child: title != null
                  ? Text(
                      title!,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                       
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Text(
                      "RISTOCMD",
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                    
                        color: Colors.white,
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
              const Icon(Icons.shopping_basket, color: Color.fromARGB(255, 255, 255, 255), size: 28),
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
