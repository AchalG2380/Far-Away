import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../../../core/theme.dart';

class InventoryItem {
  final String id;
  final String name;
  final String price;
  final bool available;

  InventoryItem({
    required this.id,
    required this.name,
    required this.price,
    required this.available,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: json['id'],
      name: json['name'],
      price: json['price'],
      available: json['available'],
    );
  }

  String toChatMessage() => 'I would like: $name ($price)';
}

class InventoryPanel extends StatefulWidget {
  final Function(String message) onItemSelected;

  const InventoryPanel({super.key, required this.onItemSelected});

  @override
  State<InventoryPanel> createState() => _InventoryPanelState();
}

class _InventoryPanelState extends State<InventoryPanel> {
  List<InventoryItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    final String data = await rootBundle.loadString('assets/inventory.json');
    final Map<String, dynamic> json = jsonDecode(data);
    setState(() {
      _items = (json['items'] as List)
          .map((e) => InventoryItem.fromJson(e))
          .toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 420,
      decoration: BoxDecoration(
        color: AppTheme.vanillaBeige,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: AppTheme.clayDark, width: 1.8),
        boxShadow: [
          BoxShadow(
            color: AppTheme.clay.withOpacity(0.4),
            blurRadius: 32,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.clayDark.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Available Items',
              style: GoogleFonts.outfit(
                color: AppTheme.inkBlack,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          Divider(
              color: AppTheme.clay.withOpacity(0.5), height: 1, thickness: 1),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.inkMuted,
                      strokeWidth: 2,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return _ItemTile(
                        item: item,
                        onTap: item.available
                            ? () {
                                widget.onItemSelected(item.toChatMessage());
                                Navigator.pop(context);
                              }
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final InventoryItem item;
  final VoidCallback? onTap;

  const _ItemTile({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool available = item.available;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: available ? AppTheme.buttercream : AppTheme.vanillaBeige,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: available
                ? AppTheme.clayDark
                : AppTheme.clay.withOpacity(0.4),
            width: 1.5,
          ),
          boxShadow: available
              ? [
                  BoxShadow(
                    color: AppTheme.clay.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: GoogleFonts.outfit(
                      color: available
                          ? AppTheme.inkBlack
                          : AppTheme.inkMuted.withOpacity(0.5),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.price,
                    style: GoogleFonts.outfit(
                      color: available
                          ? AppTheme.inkMuted
                          : AppTheme.inkMuted.withOpacity(0.3),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (!available)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.clay.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.clay.withOpacity(0.3), width: 1),
                ),
                child: Text(
                  'Unavailable',
                  style: GoogleFonts.outfit(
                      color: AppTheme.inkMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              )
            else
              Icon(Icons.arrow_forward_ios,
                  color: AppTheme.inkMuted.withOpacity(0.4), size: 14),
          ],
        ),
      ),
    );
  }
}