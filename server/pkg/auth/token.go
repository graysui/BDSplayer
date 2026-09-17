package auth

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// TokenInfo holds OAuth2 credentials
type TokenInfo struct {
	AccessToken  string    `json:"access_token"`
	RefreshToken string    `json:"refresh_token"`
	ExpiresIn    int64     `json:"expires_in"`
	Scope        string    `json:"scope,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
}

func (t *TokenInfo) IsExpired() bool {
	if t.AccessToken == "" {
		return true
	}
	// Expire 10 minutes early to ensure safety
	return time.Now().After(t.CreatedAt.Add(time.Duration(t.ExpiresIn-600) * time.Second))
}

type TokenManager struct {
	mu         sync.RWMutex
	token      *TokenInfo
	clientID   string
	configPath string
}

func NewTokenManager(clientID string, configPath string) *TokenManager {
	if configPath == "" {
		home, _ := os.UserHomeDir()
		configPath = filepath.Join(home, ".config", "share-player", "auth.json")
	}
	tm := &TokenManager{
		clientID:   clientID,
		configPath: configPath,
	}
	_ = tm.Load()
	return tm
}

func (tm *TokenManager) GetAccessToken() (string, error) {
	tm.mu.RLock()
	if tm.token != nil && !tm.token.IsExpired() {
		token := tm.token.AccessToken
		tm.mu.RUnlock()
		return token, nil
	}
	tm.mu.RUnlock()

	// Needs refresh
	return tm.RefreshToken()
}

func (tm *TokenManager) SetToken(token *TokenInfo) error {
	tm.mu.Lock()
	defer tm.mu.Unlock()
	token.CreatedAt = time.Now()
	tm.token = token
	return tm.saveLocked()
}

func (tm *TokenManager) RefreshToken() (string, error) {
	tm.mu.Lock()
	defer tm.mu.Unlock()

	if tm.token == nil || tm.token.RefreshToken == "" {
		return "", fmt.Errorf("no refresh token available, user must log in")
	}

	endpoint := "https://openapi.baidu.com/oauth/2.0/token"
	data := url.Values{
		"grant_type":    {"refresh_token"},
		"refresh_token": {tm.token.RefreshToken},
		"client_id":     {tm.clientID},
	}

	resp, err := http.PostForm(endpoint, data)
	if err != nil {
		return "", fmt.Errorf("refresh token request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("refresh token failed with status %d", resp.StatusCode)
	}

	var newTok struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
		ExpiresIn    int64  `json:"expires_in"`
		Error        string `json:"error"`
		ErrorDesc    string `json:"error_description"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&newTok); err != nil {
		return "", fmt.Errorf("failed to decode refresh response: %w", err)
	}

	if newTok.Error != "" {
		return "", fmt.Errorf("oauth error: %s (%s)", newTok.Error, newTok.ErrorDesc)
	}

	tm.token.AccessToken = newTok.AccessToken
	if newTok.RefreshToken != "" {
		tm.token.RefreshToken = newTok.RefreshToken
	}
	tm.token.ExpiresIn = newTok.ExpiresIn
	tm.token.CreatedAt = time.Now()

	_ = tm.saveLocked()
	return tm.token.AccessToken, nil
}

func (tm *TokenManager) Load() error {
	tm.mu.Lock()
	defer tm.mu.Unlock()

	data, err := os.ReadFile(tm.configPath)
	if err != nil {
		return err
	}

	var tok TokenInfo
	if err := json.Unmarshal(data, &tok); err != nil {
		return err
	}
	tm.token = &tok
	return nil
}

func (tm *TokenManager) saveLocked() error {
	if tm.token == nil {
		return nil
	}
	dir := filepath.Dir(tm.configPath)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(tm.token, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(tm.configPath, data, 0600)
}
