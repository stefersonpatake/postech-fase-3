package main

import (
	"strings"
	"testing"
)

func TestGenerateAPIKey(t *testing.T) {
	key, err := generateAPIKey()
	if err != nil {
		t.Fatalf("erro inesperado: %v", err)
	}
	if !strings.HasPrefix(key, "tm_key_") {
		t.Errorf("chave sem o prefixo tm_key_: %q", key)
	}
	// prefixo (7) + 32 bytes em hexadecimal (64)
	if len(key) != 71 {
		t.Errorf("tamanho da chave = %d, esperado 71", len(key))
	}

	other, _ := generateAPIKey()
	if key == other {
		t.Error("duas chaves geradas em sequência não podem ser iguais")
	}
}

func TestHashAPIKey(t *testing.T) {
	hash := hashAPIKey("tm_key_abc")

	if len(hash) != 64 {
		t.Errorf("tamanho do hash = %d, esperado 64 (SHA-256 em hexadecimal)", len(hash))
	}
	if hash != hashAPIKey("tm_key_abc") {
		t.Error("o hash da mesma chave deve ser sempre igual")
	}
	if hash == hashAPIKey("tm_key_abd") {
		t.Error("chaves diferentes não podem ter o mesmo hash")
	}
}
