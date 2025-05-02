import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:ristocmd/services/productlist.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class CategoriesPage extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final Map<String, dynamic> tavolo;
  final void Function(String tableId, String status)? onUpdateTableStatus;

  const CategoriesPage({
    required this.categories,
    required this.tavolo,
    required this.onUpdateTableStatus,
    Key? key,
  }) : super(key: key);

  @override
  _CategoriesPageState createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage>
    with SingleTickerProviderStateMixin {
  late Map<String, dynamic> _selectedCategory;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final Map<int, Widget> _productListCache = {};
  final double drawerWidth = 280.0;
  bool isDrawerOpen = false;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.categories.first;
    _loadCategoryOrder();
  }

  Future<void> _loadCategoryOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final savedOrder = prefs.getString('categoryOrder');
    if (savedOrder != null) {
      final List<dynamic> orderList = jsonDecode(savedOrder);
      setState(() {
        widget.categories.sort((a, b) {
          return orderList.indexOf(a['id']) - orderList.indexOf(b['id']);
        });
      });
    }
  }

  Future<void> _saveCategoryOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final categoryOrder = widget.categories.map((e) => e['id']).toList();
    await prefs.setString('categoryOrder', jsonEncode(categoryOrder));
  }

  void _selectCategory(Map<String, dynamic> category) {
    if (_selectedCategory['id'] != category['id']) {
      setState(() {
        _selectedCategory = category;
      });
    }
    _getProductListForCategory(category);
    Navigator.of(context).pop(); // Close drawer after selection
  }

  Widget _getProductListForCategory(Map<String, dynamic> category) {
    final categoryId = category['id'] as int;
    if (!_productListCache.containsKey(categoryId)) {
      _productListCache[categoryId] = ProductList(
        tavolo: widget.tavolo,
        category: category,
        onUpdateTableStatus: widget.onUpdateTableStatus,
        onBackPressed: () {},
        key: ValueKey(categoryId),
      );
    }
    return _productListCache[categoryId]!;
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final movedCategory = widget.categories.removeAt(oldIndex);
    widget.categories.insert(newIndex, movedCategory);
    _saveCategoryOrder();
    setState(() {});
  }

  String capitalize(String s) =>
      s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : s;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main scaffold
        Scaffold(
          key: _scaffoldKey,
          drawerEnableOpenDragGesture: true,
          onDrawerChanged: (isOpened) {
            setState(() {
              isDrawerOpen = isOpened;
            });
          },
          drawerEdgeDragWidth: 20,
          drawer: SizedBox(
            width: drawerWidth,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.only(top: 50, left: 16, right: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Categories',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ReorderableListView(
                      onReorder: _onReorder,
                      dragStartBehavior: DragStartBehavior.down,
                      children:
                          List.generate(widget.categories.length, (index) {
                        final category = widget.categories[index];
                        final categoryId = category['id'] as int;
                        final bool isSelected =
                            _selectedCategory['id'] == categoryId;

                        return Container(
                          key: ValueKey(categoryId),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: isSelected
                              ? const EdgeInsets.symmetric(
                                  vertical: 5, horizontal: 8)
                              : EdgeInsets.zero,
                          decoration: isSelected
                              ? BoxDecoration(
                                  border: Border.all(
                                      color: Colors.orange, width: 1),
                                  borderRadius: BorderRadius.circular(16),
                                )
                              : null,
                          child: ListTile(
                            title: Text(
                              capitalize(category['des']),
                              style: TextStyle(
                                fontSize: 18,
                                fontFamily: 'Roboto',
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color:
                                    isSelected ? Colors.orange : Colors.black,
                              ),
                            ),
                            onTap: () => _selectCategory(category),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: _getProductListForCategory(_selectedCategory),
        ),

        // Floating button that animates with drawer state
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          bottom: MediaQuery.of(context).padding.bottom + 24,
          left: isDrawerOpen
              ? drawerWidth - 20
              : 10, // Adjusted position for bigger button
          child: GestureDetector(
            onTap: () {
              if (!isDrawerOpen) {
                _scaffoldKey.currentState?.openDrawer();
              } else {
                _scaffoldKey.currentState?.closeDrawer();
              }
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(
                  16), // Increased padding for bigger button
              child: Icon(
                Icons.local_dining,
                color: Colors.orange,
                size: 40, // Increased icon size
              ),
            ),
          ),
        ),
      ],
    );
  }
}
