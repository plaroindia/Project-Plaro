enum EventSortOrder { relevance, date, popularity }

class FilterOptions {
  final Set<String> eventTypes; // e.g., {'Hackathon', 'Competition'}
  final Set<String> teamSizes; // e.g., {'Individual', '2-4 members'}
  final EventSortOrder sortOrder;

  const FilterOptions({
    this.eventTypes = const {},
    this.teamSizes = const {},
    this.sortOrder = EventSortOrder.relevance,
  });

  FilterOptions copyWith({
    Set<String>? eventTypes,
    Set<String>? teamSizes,
    EventSortOrder? sortOrder,
  }) {
    return FilterOptions(
      eventTypes: eventTypes ?? this.eventTypes,
      teamSizes: teamSizes ?? this.teamSizes,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}