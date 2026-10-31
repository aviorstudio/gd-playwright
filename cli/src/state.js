JSON.stringify(function() {
	var events = window.godotEvents || [];
	var els = window.godotElements || {};
	var vp = window.godotElementsViewport || null;
	var state = {};

	// Live element data (always available)
	var allKeys = Object.keys(els);
	var visibleKeys = allKeys.filter(function(k) { return els[k].visible; });
	state.elements = {
		total: allKeys.length,
		visible: visibleKeys.length
	};
	state.viewport = vp;
	state.event_count = events.length;
	state.test_state = window.godotTestState || {};

	// Group latest event of each type (game-agnostic)
	var latest = {};
	for (var i = events.length - 1; i >= 0; i--) {
		var e = events[i];
		if (!latest[e.event]) {
			latest[e.event] = e;
		}
	}
	state.latest_events = latest;

	return state;
}())