package api

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"regexp"
	"strings"
	"unicode/utf8"
)

// The public gift lists. A family shares /lista/<slug>; that page reads the list and records contributions here,
// without a session. Both calls use the secret key on two database functions that only expose what the page
// shows, and only for a published list of a family with Plus. Ninho handles no money: a contribution records
// what the visitor says they sent by Pix, until the family confirms it.

var giftSlug = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9-]{1,38}[a-zA-Z0-9]$`)

// Messages for the exceptions of record_gift.
var giftErrors = map[string]struct {
	status int
	text   string
}{
	"List unavailable": {404, "Esta lista não está disponível"},
	"Item unavailable": {409, "Um dos itens já foi completado. Atualize a página"},
	"Invalid amount":   {400, "Confira os valores escolhidos"},
	"Invalid gift":     {400, "Confira os itens escolhidos"},
}

type giftRequest struct {
	Name    string `json:"name"`
	Message string `json:"message"`
	Items   []struct {
		GoalID      string `json:"goal_id"`
		AmountCents int64  `json:"amount_cents"`
	} `json:"items"`
	FreeCents int64 `json:"free_cents"`
}

func (s *Server) giftList(w http.ResponseWriter, r *http.Request) {
	slug := strings.ToLower(strings.TrimPrefix(r.URL.Path, "/v1/public/lists/"))
	if !giftSlug.MatchString(slug) || strings.Contains(slug, "--") {
		fail(w, 404, "Lista não encontrada")
		return
	}
	if s.cfg.SecretKey == "" {
		fail(w, 503, "Listas de presentes indisponíveis no momento")
		return
	}
	ip := clientIP(r)
	switch r.Method {
	case http.MethodGet:
		if !s.allowN("list:"+ip, 120) {
			w.Header().Set("Retry-After", "60")
			fail(w, 429, "Muitas solicitações. Tente novamente em um minuto")
			return
		}
		status, body, err := s.adminRPC(r.Context(), "gift_page", map[string]any{"p_slug": slug})
		if err != nil || status != 200 {
			fail(w, 503, "Serviço temporariamente indisponível")
			return
		}
		if bytes.Equal(bytes.TrimSpace(body), []byte("null")) {
			fail(w, 404, "Lista não encontrada")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(200)
		_, _ = w.Write(body)
	case http.MethodPost:
		// A few contributions a minute per address is plenty for a person, and keeps a script from flooding
		// the family with fake gifts.
		if !s.allowN("gift:"+ip, 5) {
			w.Header().Set("Retry-After", "60")
			fail(w, 429, "Muitas tentativas. Tente novamente em um minuto")
			return
		}
		if !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
			fail(w, 400, "Envie JSON")
			return
		}
		dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16384))
		dec.DisallowUnknownFields()
		var g giftRequest
		if dec.Decode(&g) != nil || dec.Decode(&struct{}{}) != io.EOF {
			fail(w, 400, "Dados inválidos")
			return
		}
		g.Name, g.Message = strings.TrimSpace(g.Name), strings.TrimSpace(g.Message)
		if n := utf8.RuneCountInString(g.Name); n < 1 || n > 80 {
			fail(w, 400, "Diga seu nome para a família saber quem presenteou")
			return
		}
		if utf8.RuneCountInString(g.Message) > 600 {
			fail(w, 400, "Use até 600 caracteres no recado")
			return
		}
		if len(g.Items) > 50 || g.FreeCents < 0 || g.FreeCents > 5000000 || len(g.Items) == 0 && g.FreeCents == 0 {
			fail(w, 400, "Escolha ao menos um item ou um valor")
			return
		}
		items := make([]map[string]any, 0, len(g.Items))
		for _, it := range g.Items {
			if !uuid.MatchString(it.GoalID) || it.AmountCents < 1 || it.AmountCents > 5000000 {
				fail(w, 400, "Confira os itens escolhidos")
				return
			}
			items = append(items, map[string]any{"goal_id": it.GoalID, "amount_cents": it.AmountCents})
		}
		status, body, err := s.adminRPC(r.Context(), "record_gift", map[string]any{
			"p_slug": slug, "p_name": g.Name, "p_message": g.Message, "p_items": items, "p_free_cents": g.FreeCents,
		})
		if err != nil || status >= 500 {
			fail(w, 503, "Serviço temporariamente indisponível")
			return
		}
		if status >= 400 {
			var upstream struct{ Code, Message string }
			_ = json.Unmarshal(body, &upstream)
			if known, ok := giftErrors[upstream.Message]; ok && upstream.Code == "P0001" {
				fail(w, known.status, known.text)
				return
			}
			fail(w, 400, "Confira os valores escolhidos")
			return
		}
		var id string
		if json.Unmarshal(body, &id) != nil || !uuid.MatchString(id) {
			fail(w, 503, "Serviço temporariamente indisponível")
			return
		}
		send(w, 201, map[string]string{"id": id})
	default:
		fail(w, 405, "Método não permitido")
	}
}

// adminRPC calls a database function with the secret key and returns its status and body.
func (s *Server) adminRPC(ctx context.Context, name string, args map[string]any) (int, []byte, error) {
	b, _ := json.Marshal(args)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.cfg.SupabaseURL+"/rest/v1/rpc/"+name, bytes.NewReader(b))
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("apikey", s.cfg.SecretKey)
	req.Header.Set("Authorization", "Bearer "+s.cfg.SecretKey)
	req.Header.Set("Content-Type", "application/json")
	res, err := s.client.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer res.Body.Close()
	body, err := io.ReadAll(io.LimitReader(res.Body, 4<<20))
	return res.StatusCode, body, err
}

// clientIP is the address of the visitor. Render's proxy appends the address that reached it to
// X-Forwarded-For, so the last entry is the one a client cannot forge.
func clientIP(r *http.Request) string {
	if f := r.Header.Get("X-Forwarded-For"); f != "" {
		parts := strings.Split(f, ",")
		return strings.TrimSpace(parts[len(parts)-1])
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
