import 'package:flutter/material.dart';

class ProductVariant {
  static Future<List<Map<String, dynamic>>?> showVariantSelection({
    required BuildContext context,
    required Map<String, dynamic> product,
    List<Map<String, dynamic>> initialVariants = const [],
  }) async {
    // This should be replaced with your actual variant fetching logic
    final availableVariants = [
      {'id': 1, 'des': 'Extra Panna', 'prezzo': 0.50},
      {'id': 2, 'des': 'Extra Cioccolato', 'prezzo': 0.50},
      {'id': 3, 'des': 'Senza Zucchero', 'prezzo': 0.00},
    ];

    List<Map<String, dynamic>> selectedVariants = List.from(initialVariants);

    return await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Seleziona Varianti'),
              content: SingleChildScrollView(
                child: Column(
                  children: availableVariants.map((variant) {
                    final isSelected = selectedVariants.any((v) => v['id'] == variant['id']);
                    return CheckboxListTile(
                      title: Text('${variant['des']} (+${variant['prezzo']}€)'),
                      value: isSelected,
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            selectedVariants.add(variant);
                          } else {
                            selectedVariants.removeWhere((v) => v['id'] == variant['id']);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text('ANNULLA'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, selectedVariants),
                  child: Text('CONFERMA'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
