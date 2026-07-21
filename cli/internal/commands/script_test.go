package commands

import "testing"

func TestParsePoint(t *testing.T) {
	point, err := parsePoint("1000.5, 260")
	if err != nil {
		t.Fatalf("parsePoint() error = %v", err)
	}
	if point.X != 1000.5 || point.Y != 260 {
		t.Fatalf("parsePoint() = %+v", point)
	}
}

func TestScriptRetriesRequireConfirmation(t *testing.T) {
	_, err := (scriptFlags{retries: 1}).options("click", "enemy_1")
	if err == nil {
		t.Fatal("script options should reject retries without confirmation")
	}
}
