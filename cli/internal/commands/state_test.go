package commands

import (
	"strings"
	"testing"
)

func TestStateExpressionIncludesNamespacedTestState(t *testing.T) {
	if !strings.Contains(stateExpression, "state.test_state = window.godotTestState || {}") {
		t.Fatal("state expression must expose window.godotTestState")
	}
}
