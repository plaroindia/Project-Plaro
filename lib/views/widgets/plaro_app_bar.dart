import 'package:flutter/material.dart';

class PlaroAppBar extends StatelessWidget implements PreferredSizeWidget {
  final ValueChanged<String>? onSearch;
  final VoidCallback? onFilter;

  const PlaroAppBar({
    super.key,
    this.onSearch,
    this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();
    return AppBar(
      title: Text("Discover"),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: "Search...",
                    prefixIcon: Icon(Icons.search),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                      icon: Icon(Icons.clear),
                      onPressed: () {
                        controller.clear();
                        if (onSearch != null) onSearch!("");
                      },
                    )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: onSearch,
                ),
              ),
              IconButton(
                icon: Icon(Icons.filter_list),
                onPressed: onFilter,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight * 2);
}