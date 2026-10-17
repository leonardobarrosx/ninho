package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

type Config struct {
	SupabaseURL, PublishableKey string
	// SecretKey is used for one call only: deleting the signed-in user with the Auth admin API.
	// Without it, account deletion answers 503 and everything else works.
	SecretKey string
	Origins   []string
	Client    *http.Client
}

func (c Config) Validate() error {
	u, e := url.Parse(c.SupabaseURL)
	if e != nil || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" {
		return errors.New("SUPABASE_URL is invalid")
	}
	if u.Scheme != "https" && !(u.Scheme == "http" && (u.Hostname() == "localhost" || u.Hostname() == "127.0.0.1")) {
		return errors.New("SUPABASE_URL requires HTTPS")
	}
	if c.PublishableKey == "" {
		return errors.New("SUPABASE_PUBLISHABLE_KEY is required")
	}
	if strings.HasPrefix(c.PublishableKey, "sb_secret_") {
		return errors.New("SUPABASE_PUBLISHABLE_KEY must be the publishable key, not a secret key")
	}
	if c.SecretKey != "" && (c.SecretKey == c.PublishableKey || strings.HasPrefix(c.SecretKey, "sb_publishable_")) {
		return errors.New("SUPABASE_SECRET_KEY must be the secret key")
	}
	if len(c.Origins) == 0 {
		return errors.New("ALLOWED_ORIGINS is required")
	}
	for _, o := range c.Origins {
		u, e := url.Parse(strings.TrimSpace(o))
		if e != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") || u.Path != "" || u.RawQuery != "" || u.User != nil {
			return errors.New("origins must be exact URLs without paths or wildcards")
		}
	}
	return nil
}

type quota struct {
	count int
	until time.Time
}
type Server struct {
	cfg    Config
	client *http.Client
	mu     sync.Mutex
	limits map[string]quota
}

var uuid = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)
var fields = map[string]string{
	"households":    "name",
	"babies":        "household_id,name,due_date,birth_date,notes",
	"entries":       "household_id,title,kind,category,amount_cents,start_date,end_date,recurrence,notes",
	"debts":         "household_id,title,creditor,balance_cents,installment_cents,due_day,notes",
	"goals":         "household_id,title,priority,target_cents,saved_cents,quantity,acquired,target_date,notes",
	"measurements":  "household_id,baby_id,measured_at,weight_grams,length_mm,notes",
	"health_events": "household_id,baby_id,title,event_type,event_date,provider,notes,completed",
}

// userKey holds the ID of the user verified by protect in the request context.
type userKey struct{}

var readable = map[string]bool{"households": true, "household_members": true, "babies": true, "entries": true, "settlements": true, "debts": true, "goals": true, "measurements": true, "health_events": true}
var rpcFields = map[string]string{"create_household": "p_name", "create_invite": "p_household_id", "accept_invite": "p_token", "settle_entry": "p_entry_id,p_occurrence,p_paid", "buy_goal": "p_goal_id,p_quantity,p_cost_cents,p_date", "record_health_cost": "p_event_id,p_amount_cents,p_date", "list_members": "p_household_id", "remove_member": "p_household_id,p_user_id", "leave_household": "p_household_id"}

// Exception messages raised by the migrations' functions and triggers, shown to the user in Portuguese.
var dbErrors = map[string]string{
	"Invalid invite":                          "Convite inválido, expirado ou já usado",
	"Family is full":                          "Esta família já tem quatro pessoas",
	"Already a member":                        "Você já faz parte desta família",
	"Family limit reached":                    "Você já participa de cinco famílias",
	"Owner required":                          "Só quem criou a família pode gerar convites",
	"Expense already recorded":                "O custo deste registro já foi lançado",
	"Invalid purchase":                        "Confira a quantidade e o valor da aquisição",
	"Invalid occurrence":                      "Data fora da programação deste lançamento",
	"End date cannot remove paid occurrences": "A data final não pode excluir ocorrências já pagas",
	"Only the owner can remove members":       "Só quem criou a família pode remover pessoas",
	"Owner cannot leave":                      "Quem criou a família não pode sair dela",
	"Not a member":                            "Essa pessoa não faz parte desta família",
	"Close this schedule and create a new entry to preserve paid history": "Há pagamentos registrados. Encerre este lançamento e crie outro para mudar valor, tipo ou início",
}

func New(c Config) http.Handler {
	client := c.Client
	if client == nil {
		client = &http.Client{Timeout: 12 * time.Second}
	}
	s := &Server{cfg: c, client: client, limits: map[string]quota{}}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) { send(w, 200, map[string]string{"status": "ok"}) })
	mux.Handle("/v1/", s.protect(http.HandlerFunc(s.route)))
	return s.middleware(mux)
}
func (s *Server) middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Vary", "Origin")
		origin := r.Header.Get("Origin")
		if origin != "" {
			allowed := false
			for _, o := range s.cfg.Origins {
				if origin == strings.TrimSpace(o) {
					allowed = true
				}
			}
			if !allowed {
				fail(w, 403, "Origem não permitida")
				return
			}
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(204)
			return
		}
		next.ServeHTTP(w, r)
	})
}
func (s *Server) protect(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if !strings.HasPrefix(auth, "Bearer ") || len(auth) < 20 || len(auth) > 8192 {
			fail(w, 401, "Entre na sua conta para continuar")
			return
		}
		req, _ := http.NewRequestWithContext(r.Context(), http.MethodGet, s.cfg.SupabaseURL+"/auth/v1/user", nil)
		req.Header.Set("Authorization", auth)
		req.Header.Set("apikey", s.cfg.PublishableKey)
		res, err := s.client.Do(req)
		if err != nil {
			fail(w, 503, "Autenticação temporariamente indisponível")
			return
		}
		defer res.Body.Close()
		if res.StatusCode >= 500 {
			fail(w, 503, "Autenticação temporariamente indisponível")
			return
		}
		if res.StatusCode != 200 {
			fail(w, 401, "Sessão expirada. Entre novamente")
			return
		}
		var user struct {
			ID string `json:"id"`
		}
		if json.NewDecoder(io.LimitReader(res.Body, 65536)).Decode(&user) != nil || !uuid.MatchString(user.ID) {
			fail(w, 401, "Sessão inválida")
			return
		}
		if !s.allow(user.ID) {
			w.Header().Set("Retry-After", "60")
			fail(w, 429, "Muitas solicitações. Tente novamente em um minuto")
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), userKey{}, user.ID)))
	})
}
func (s *Server) allow(id string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	if len(s.limits) > 5000 {
		for k, v := range s.limits {
			if now.After(v.until) {
				delete(s.limits, k)
			}
		}
	}
	v := s.limits[id]
	if now.After(v.until) {
		v = quota{until: now.Add(time.Minute)}
	}
	v.count++
	s.limits[id] = v
	return v.count <= 180
}
func (s *Server) route(w http.ResponseWriter, r *http.Request) {
	parts := strings.Split(strings.Trim(strings.TrimPrefix(r.URL.Path, "/v1/"), "/"), "/")
	if len(parts) == 2 && parts[0] == "rpc" {
		s.rpc(w, r, parts[1])
		return
	}
	if len(parts) == 1 && parts[0] == "account" {
		s.deleteAccount(w, r)
		return
	}
	if len(parts) < 2 || len(parts) > 3 || parts[0] != "data" || !readable[parts[1]] {
		fail(w, 404, "Recurso não encontrado")
		return
	}
	table := parts[1]
	id := ""
	if len(parts) == 3 {
		id = parts[2]
		if !uuid.MatchString(id) {
			fail(w, 400, "Identificador inválido")
			return
		}
	}
	q := url.Values{"select": {"*"}}
	if id != "" {
		q.Set("id", "eq."+id)
	}
	switch r.Method {
	case http.MethodGet:
		if id != "" {
			fail(w, 405, "Consulte a lista do recurso")
			return
		}
		if table != "households" {
			house := r.URL.Query().Get("household_id")
			if !uuid.MatchString(house) {
				fail(w, 400, "Selecione uma família")
				return
			}
			q.Set("household_id", "eq."+house)
		}
		offset := 0
		if raw := r.URL.Query().Get("offset"); raw != "" {
			var err error
			offset, err = strconv.Atoi(raw)
			if err != nil || offset < 0 || offset > 1000000 {
				fail(w, 400, "Página inválida")
				return
			}
		}
		q.Set("limit", "200")
		q.Set("offset", strconv.Itoa(offset))
		q.Set("order", "id.asc")
		s.forward(w, r, "/rest/v1/"+table+"?"+q.Encode(), nil)
	case http.MethodPost, http.MethodPatch:
		if fields[table] == "" || table == "households" && r.Method == http.MethodPost {
			fail(w, 405, "Operação não permitida")
			return
		}
		if r.Method == http.MethodPatch && id == "" || r.Method == http.MethodPost && id != "" {
			fail(w, 400, "Rota inválida")
			return
		}
		obj, err := decode(w, r, fields[table])
		if err != nil {
			fail(w, 400, err.Error())
			return
		}
		if r.Method == http.MethodPost {
			h, ok := obj["household_id"].(string)
			if !ok || !uuid.MatchString(h) {
				fail(w, 400, "Família inválida")
				return
			}
		} else {
			if _, ok := obj["household_id"]; ok {
				fail(w, 400, "Não é possível mover registros entre famílias")
				return
			}
		}
		body, _ := json.Marshal(obj)
		s.forward(w, r, "/rest/v1/"+table+"?"+q.Encode(), body)
	case http.MethodDelete:
		if id == "" || fields[table] == "" || table == "households" {
			fail(w, 405, "Operação não permitida")
			return
		}
		s.forward(w, r, "/rest/v1/"+table+"?"+q.Encode(), nil)
	default:
		fail(w, 405, "Método não permitido")
	}
}
func (s *Server) rpc(w http.ResponseWriter, r *http.Request, name string) {
	allowed, ok := rpcFields[name]
	if !ok {
		fail(w, 404, "Operação não encontrada")
		return
	}
	if r.Method != http.MethodPost {
		fail(w, 405, "Use POST")
		return
	}
	obj, err := decode(w, r, allowed)
	if err != nil {
		fail(w, 400, err.Error())
		return
	}
	body, _ := json.Marshal(obj)
	s.forward(w, r, "/rest/v1/rpc/"+name, body)
}

// deleteAccount erases the signed-in user with the Auth admin API, the only call made with the secret key.
// The ID comes from the session protect verified, never from the request. Before the user row goes, the
// trigger from 202610170001_account_deletion.sql hands shared families over and erases the others.
func (s *Server) deleteAccount(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		fail(w, 405, "Use DELETE")
		return
	}
	if s.cfg.SecretKey == "" {
		fail(w, 503, "A exclusão de conta não está disponível agora. Tente mais tarde")
		return
	}
	id, _ := r.Context().Value(userKey{}).(string)
	if !uuid.MatchString(id) {
		fail(w, 401, "Sessão inválida")
		return
	}
	req, err := http.NewRequestWithContext(r.Context(), http.MethodDelete, s.cfg.SupabaseURL+"/auth/v1/admin/users/"+id, nil)
	if err != nil {
		fail(w, 500, "Não foi possível preparar a operação")
		return
	}
	req.Header.Set("apikey", s.cfg.SecretKey)
	req.Header.Set("Authorization", "Bearer "+s.cfg.SecretKey)
	res, err := s.client.Do(req)
	if err != nil {
		fail(w, 503, "Não foi possível excluir a conta agora. Tente novamente")
		return
	}
	defer res.Body.Close()
	// 404: the user is already gone, which is what was asked for.
	if res.StatusCode >= 300 && res.StatusCode != 404 {
		slog.Error("account deletion failed", "status", res.StatusCode)
		fail(w, 503, "Não foi possível excluir a conta agora. Tente novamente")
		return
	}
	w.WriteHeader(204)
}
func decode(w http.ResponseWriter, r *http.Request, allowed string) (map[string]any, error) {
	if !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
		return nil, errors.New("Envie JSON")
	}
	r.Body = http.MaxBytesReader(w, r.Body, 65536)
	dec := json.NewDecoder(r.Body)
	dec.UseNumber()
	var obj map[string]any
	if err := dec.Decode(&obj); err != nil || len(obj) == 0 {
		return nil, errors.New("Dados inválidos ou muito grandes")
	}
	var extra any
	if dec.Decode(&extra) != io.EOF {
		return nil, errors.New("JSON inválido")
	}
	for k, v := range obj {
		if !strings.Contains(","+allowed+",", ","+k+",") {
			return nil, fmt.Errorf("Campo não permitido: %s", k)
		}
		switch v.(type) {
		case string, json.Number, bool, nil:
		default:
			return nil, errors.New("Valor inválido")
		}
	}
	return obj, nil
}
func (s *Server) forward(w http.ResponseWriter, r *http.Request, path string, body []byte) {
	req, err := http.NewRequestWithContext(r.Context(), r.Method, s.cfg.SupabaseURL+path, bytes.NewReader(body))
	if err != nil {
		fail(w, 500, "Não foi possível preparar a operação")
		return
	}
	req.Header.Set("Authorization", r.Header.Get("Authorization"))
	req.Header.Set("apikey", s.cfg.PublishableKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=representation")
	res, err := s.client.Do(req)
	if err != nil {
		fail(w, 503, "Não foi possível acessar seus dados. Tente novamente")
		return
	}
	defer res.Body.Close()
	if res.StatusCode >= 400 {
		status := res.StatusCode
		if status >= 500 {
			status = 503
		}
		msg := "Verifique os campos e o acesso à família"
		if status == 409 {
			msg = "Registro já existe ou está vinculado a outros dados"
		}
		if status == 401 {
			msg = "Sessão expirada"
		}
		if status == 503 {
			msg = "Serviço temporariamente indisponível"
		}
		var upstream struct{ Code, Message string }
		if status == 400 && json.NewDecoder(io.LimitReader(res.Body, 65536)).Decode(&upstream) == nil && upstream.Code == "P0001" {
			if known, ok := dbErrors[upstream.Message]; ok {
				msg = known
			}
		}
		fail(w, status, msg)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(res.StatusCode)
	_, _ = io.Copy(w, io.LimitReader(res.Body, 8<<20))
}
func send(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
func fail(w http.ResponseWriter, status int, msg string) {
	send(w, status, map[string]string{"error": msg})
}
