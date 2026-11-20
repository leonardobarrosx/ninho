package api

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestGiftList(t *testing.T) {
	var recorded map[string]any
	db := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("apikey") != "secret-key" || r.Header.Get("Authorization") != "Bearer secret-key" {
			t.Error("public lists must use the secret key")
		}
		var args map[string]any
		_ = json.NewDecoder(r.Body).Decode(&args)
		switch r.URL.Path {
		case "/rest/v1/rpc/gift_page":
			if args["p_slug"] == "ana-e-pedro" {
				_, _ = w.Write([]byte(`{"title":"Enxoval do Bento","items":[]}`))
				return
			}
			_, _ = w.Write([]byte(`null`))
		case "/rest/v1/rpc/record_gift":
			recorded = args
			if args["p_name"] == "Esgotado" {
				w.WriteHeader(400)
				_, _ = w.Write([]byte(`{"code":"P0001","message":"Item unavailable"}`))
				return
			}
			_, _ = w.Write([]byte(`"` + uid + `"`))
		default:
			t.Errorf("unexpected call %s", r.URL.Path)
		}
	}))
	defer db.Close()
	h := New(Config{SupabaseURL: db.URL, PublishableKey: "public-key", SecretKey: "secret-key", Origins: []string{"https://ninho.example"}})
	call := func(method, path, body, ip string) *httptest.ResponseRecorder {
		var reader io.Reader
		if body != "" {
			reader = strings.NewReader(body)
		}
		r := httptest.NewRequest(method, path, reader)
		r.Header.Set("Origin", "https://ninho.example")
		r.Header.Set("Content-Type", "application/json")
		r.Header.Set("X-Forwarded-For", "6.6.6.6, "+ip)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	if w := call("GET", "/v1/public/lists/Ana-E-Pedro", "", "1.1.1.1"); w.Code != 200 || !strings.Contains(w.Body.String(), "Enxoval do Bento") {
		t.Fatalf("page: %d %s", w.Code, w.Body)
	}
	for _, path := range []string{"/v1/public/lists/outra", "/v1/public/lists/a", "/v1/public/lists/ana--pedro", "/v1/public/lists/ana/x"} {
		if w := call("GET", path, "", "1.1.1.1"); w.Code != 404 {
			t.Errorf("%s: %d", path, w.Code)
		}
	}
	gift := `{"name":" Tia Rosa ","message":"Com carinho","items":[{"goal_id":"` + uid + `","amount_cents":15000}],"free_cents":500}`
	w := call("POST", "/v1/public/lists/ana-e-pedro", gift, "2.2.2.2")
	if w.Code != 201 || !strings.Contains(w.Body.String(), uid) {
		t.Fatalf("gift: %d %s", w.Code, w.Body)
	}
	if recorded["p_name"] != "Tia Rosa" || recorded["p_free_cents"] != float64(500) || recorded["p_slug"] != "ana-e-pedro" {
		t.Fatalf("recorded: %v", recorded)
	}
	for body, want := range map[string]int{
		`{"name":"","items":[],"free_cents":500}`:                                  400,
		`{"name":"Tio","items":[],"free_cents":0}`:                                 400,
		`{"name":"Tio","items":[{"goal_id":"x","amount_cents":1}]}`:                400,
		`{"name":"Tio","free_cents":500,"admin":true}`:                             400,
		`{"name":"Esgotado","items":[{"goal_id":"` + uid + `","amount_cents":1}]}`: 409,
	} {
		if w := call("POST", "/v1/public/lists/ana-e-pedro", body, "3.3.3.3"); w.Code != want {
			t.Errorf("%s: %d %s", body, w.Code, w.Body)
		}
	}
	// The same address gets five tries a minute, whatever it claims to forward for.
	codes := []int{}
	for range 6 {
		codes = append(codes, call("POST", "/v1/public/lists/ana-e-pedro", gift, "4.4.4.4").Code)
	}
	if codes[4] != 201 || codes[5] != 429 {
		t.Fatalf("rate limit: %v", codes)
	}
	if w := call("DELETE", "/v1/public/lists/ana-e-pedro", "", "5.5.5.5"); w.Code != 405 {
		t.Fatalf("delete: %d", w.Code)
	}
	noSecret := New(Config{SupabaseURL: db.URL, PublishableKey: "public-key", Origins: []string{"https://ninho.example"}})
	r := httptest.NewRequest("GET", "/v1/public/lists/ana-e-pedro", nil)
	rec := httptest.NewRecorder()
	noSecret.ServeHTTP(rec, r)
	if rec.Code != 503 {
		t.Fatalf("without the secret key: %d", rec.Code)
	}
}
