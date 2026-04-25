import 'package:flutter/material.dart';
import '../../models/filter_options.dart';

class FilterBottomSheet extends StatefulWidget {
  final FilterOptions initialFilters;

  const FilterBottomSheet({
    super.key,
    required this.initialFilters,
  });

  @override
  FilterBottomSheetState createState() => FilterBottomSheetState();
}

class FilterBottomSheetState extends State<FilterBottomSheet> {
  late FilterOptions _currentFilters;

  final List<String> _allEventTypes = ['Hackathon', 'Competition', 'Internship', 'Workshop'];
  final List<String> _allTeamSizes = ['Individual', '2-4 Members', '5+ Members'];

  @override
  void initState() {
    super.initState();
    _currentFilters = widget.initialFilters;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: 16),
            Text('Filters', style: theme.textTheme.headlineSmall),
            SizedBox(height: 16),
            _buildFilterSection(
              context,
              title: 'Event Type',
              options: _allEventTypes,
              selectedOptions: _currentFilters.eventTypes,
              onSelected: (type) {
                setState(() {
                  if (_currentFilters.eventTypes.contains(type)) {
                    _currentFilters.eventTypes.remove(type);
                  } else {
                    _currentFilters.eventTypes.add(type);
                  }
                });
              },
            ),
            _buildFilterSection(
              context,
              title: 'Team Size',
              options: _allTeamSizes,
              selectedOptions: _currentFilters.teamSizes,
              onSelected: (size) {
                setState(() {
                  if (_currentFilters.teamSizes.contains(size)) {
                    _currentFilters.teamSizes.remove(size);
                  } else {
                    _currentFilters.teamSizes.add(size);
                  }
                });
              },
            ),
            // More filter sections can be added here
            SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _currentFilters = const FilterOptions();
                      });
                    },
                    child: Text('Clear All'),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context, _currentFilters);
                    },
                    child: Text('Apply Filters'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection(
      BuildContext context, {
        required String title,
        required List<String> options,
        required Set<String> selectedOptions,
        required ValueChanged<String> onSelected,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: 8),
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: options.map((option) {
            final isSelected = selectedOptions.contains(option);
            return FilterChip(
              label: Text(option),
              selected: isSelected,
              onSelected: (selected) => onSelected(option),
              selectedColor: Theme.of(context).colorScheme.primaryContainer,
              checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
            );
          }).toList(),
        ),
        SizedBox(height: 16),
      ],
    );
  }
}