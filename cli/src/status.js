JSON.stringify((function() {
				var els = window.godotElements || {};
				var allKeys = Object.keys(els);
				var visibleCount = allKeys.filter(function(k) { return els[k].visible; }).length;
				return {
					element_count: allKeys.length,
					visible_count: visibleCount,
					event_count: (window.godotEvents || []).length,
					has_viewport: window.godotElementsViewport != null,
					viewport: window.godotElementsViewport || null
				};
			})())