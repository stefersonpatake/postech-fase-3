package main

import "testing"

func TestGetDeterministicBucket(t *testing.T) {
	first := getDeterministicBucket("user-123enable-new-dashboard")

	if first != getDeterministicBucket("user-123enable-new-dashboard") {
		t.Error("a mesma entrada deve cair sempre no mesmo bucket")
	}

	for _, input := range []string{"", "a", "user-1flag", "user-2flag", "outro-usuario-qualquer"} {
		if b := getDeterministicBucket(input); b < 0 || b > 99 {
			t.Errorf("bucket de %q = %d, fora do intervalo 0-99", input, b)
		}
	}
}

func TestRunEvaluationLogic(t *testing.T) {
	app := &App{}
	flag := func(enabled bool) *Flag { return &Flag{Name: "nova-tela", IsEnabled: enabled} }
	percentage := func(enabled bool, value interface{}) *TargetingRule {
		return &TargetingRule{FlagName: "nova-tela", IsEnabled: enabled, Rules: Rule{Type: "PERCENTAGE", Value: value}}
	}

	tests := []struct {
		name string
		info *CombinedFlagInfo
		want bool
	}{
		{"flag inexistente", &CombinedFlagInfo{}, false},
		{"flag desligada", &CombinedFlagInfo{Flag: flag(false)}, false},
		{"flag ligada sem regra", &CombinedFlagInfo{Flag: flag(true)}, true},
		{"regra desligada libera para todos", &CombinedFlagInfo{Flag: flag(true), Rule: percentage(false, 0.0)}, true},
		{"100% dos usuários", &CombinedFlagInfo{Flag: flag(true), Rule: percentage(true, 100.0)}, true},
		{"0% dos usuários", &CombinedFlagInfo{Flag: flag(true), Rule: percentage(true, 0.0)}, false},
		{"valor da regra não numérico", &CombinedFlagInfo{Flag: flag(true), Rule: percentage(true, "cinquenta")}, false},
		{"tipo de regra desconhecido", &CombinedFlagInfo{Flag: flag(true), Rule: &TargetingRule{IsEnabled: true, Rules: Rule{Type: "OUTRO"}}}, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := app.runEvaluationLogic(tt.info, "user-123"); got != tt.want {
				t.Errorf("resultado = %t, esperado %t", got, tt.want)
			}
		})
	}
}

func TestRunEvaluationLogicIsStablePerUser(t *testing.T) {
	app := &App{}
	info := &CombinedFlagInfo{
		Flag: &Flag{Name: "nova-tela", IsEnabled: true},
		Rule: &TargetingRule{IsEnabled: true, Rules: Rule{Type: "PERCENTAGE", Value: 50.0}},
	}

	first := app.runEvaluationLogic(info, "user-123")
	for i := 0; i < 10; i++ {
		if app.runEvaluationLogic(info, "user-123") != first {
			t.Fatal("o mesmo usuário deve receber sempre a mesma decisão")
		}
	}
}
