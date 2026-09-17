package service

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/http"
	"share-player/pkg/auth"
	"share-player/pkg/panapi"
	"share-player/pkg/player"
	"share-player/pkg/storage"
	"share-player/pkg/streamproxy"
	"strings"
	"sync"
	"time"
)

type AppService struct {
	mu           sync.RWMutex
	tokenMgr     *auth.TokenManager
	panClient    *panapi.Client
	streamProxy  *streamproxy.StreamProxy
	db           *storage.Database
	activeDlinks map[string]string // sessionID -> dlink
}

func NewAppService(clientID string, dbPath, authPath string) (*AppService, error) {
	db, err := storage.Open(dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize db: %w", err)
	}

	tokenMgr := auth.NewTokenManager(clientID, authPath)
	// Try decrypting bdpan token on launch
	if at, rt, err := panapi.GetBDPANCli().DecryptTokens(); err == nil && at != "" {
		_ = tokenMgr.SetToken(&auth.TokenInfo{AccessToken: at, RefreshToken: rt, ExpiresIn: 86400 * 30})
	}
	panClient := panapi.NewClient(tokenMgr)
	proxy := streamproxy.NewStreamProxy()

	return &AppService{
		tokenMgr:     tokenMgr,
		panClient:    panClient,
		streamProxy:  proxy,
		db:           db,
		activeDlinks: make(map[string]string),
	}, nil
}

func (s *AppService) SetBaseURL(baseURL string) {
	s.streamProxy.SetBaseURL(baseURL)
}

func (s *AppService) GetStreamHandler() http.Handler {
	return s.streamProxy
}

func (s *AppService) Close() {
	if s.db != nil {
		_ = s.db.Close()
	}
}

// 1. Auth APIs
func (s *AppService) GetLoginStatus() (bool, string) {
	token, err := s.tokenMgr.GetAccessToken()
	if err == nil && token != "" {
		return true, "百度网盘用户"
	}
	// Also check bdpan CLI status
	if isAuth, _ := panapi.GetBDPANCli().Whoami(); isAuth {
		if at, rt, err := panapi.GetBDPANCli().DecryptTokens(); err == nil && at != "" {
			_ = s.tokenMgr.SetToken(&auth.TokenInfo{AccessToken: at, RefreshToken: rt, ExpiresIn: 86400 * 30})
		}
		return true, "百度网盘用户"
	}
	return false, ""
}

func (s *AppService) StartDeviceLogin() (*auth.DeviceCodeResponse, error) {
	qrURL, userCode, err := panapi.GetBDPANCli().StartDeviceLogin()
	if err != nil {
		return nil, err
	}
	return &auth.DeviceCodeResponse{
		QrcodeURL:       qrURL,
		UserCode:        userCode,
		VerificationURL: "https://openapi.baidu.com/device",
		Interval:        2,
	}, nil
}

func (s *AppService) PollDeviceLogin(deviceCode string) (bool, error) {
	isAuth, err := panapi.GetBDPANCli().Whoami()
	if err != nil {
		return false, nil
	}
	if isAuth {
		if at, rt, err := panapi.GetBDPANCli().DecryptTokens(); err == nil && at != "" {
			_ = s.tokenMgr.SetToken(&auth.TokenInfo{AccessToken: at, RefreshToken: rt, ExpiresIn: 86400 * 30})
		}
		return true, nil
	}
	return false, nil
}

func (s *AppService) Logout() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	_ = s.tokenMgr.Clear()
	_ = panapi.GetBDPANCli().Logout()
	return nil
}

// 2. Share APIs
type ShareItemDTO struct {
	storage.ShareRecord
}

func (s *AppService) ListShares() ([]storage.ShareRecord, error) {
	return s.db.ListShares()
}

func (s *AppService) DeleteShare(shareKey string) error {
	return s.db.DeleteShare(shareKey)
}

func (s *AppService) UpdateShareTitle(shareKey, title string) error {
	return s.db.UpdateShareTitle(shareKey, title)
}

func (s *AppService) AddShare(rawInput string) (*storage.ShareRecord, error) {
	info, err := panapi.ParseShareInput(rawInput)
	if err != nil {
		return nil, err
	}

	title := "分享资源 " + info.ShortURL
	totalFiles := 0

	// Test list to fetch title and file count
	items, _, err := s.GetShareFiles(info.ShortURL, info.Pwd, "", 1)
	if err == nil && len(items) > 0 {
		totalFiles = len(items)
		title = items[0].Name
		if len(items) > 1 {
			title = fmt.Sprintf("%s 等 %d 项", items[0].Name, len(items))
		}
	}

	record := &storage.ShareRecord{
		ShareKey:   info.ShortURL,
		ShareURL:   info.OriginalURL,
		Pwd:        info.Pwd,
		Title:      title,
		TotalFiles: totalFiles,
	}

	if err := s.db.SaveShare(record); err != nil {
		return nil, err
	}
	return record, nil
}

func (s *AppService) GetShareFiles(shortURL, pwd, sourceDir string, page int) ([]panapi.ShareFileItem, bool, error) {
	// First try bdpan CLI TransferList as it supports all share links and passwords seamlessly
	items, err := panapi.GetBDPANCli().TransferList(shortURL, pwd, sourceDir)
	if err == nil && len(items) > 0 {
		return items, false, nil
	}

	// Fallback to OpenAPI panClient
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	openAPIItems, hasMore, apiErr := s.panClient.ListShareFiles(ctx, shortURL, pwd, sourceDir, page, 100)
	if apiErr == nil && len(openAPIItems) > 0 {
		return openAPIItems, hasMore, nil
	}
	if err != nil {
		return nil, false, err
	}
	return nil, false, apiErr
}

// 3. Playback & JIT Transfer
type PlayResult struct {
	SessionID   string  `json:"session_id"`
	StreamURL   string  `json:"stream_url"`
	RawDlink    string  `json:"raw_dlink"`
	VideoID     string  `json:"video_id"`
	VideoName   string  `json:"video_name"`
	Duration    float64 `json:"duration"`
	CurrentTime float64 `json:"current_time"` // from playback history
}

func (s *AppService) PreparePlay(shortURL, pwd, videoName string, shareFsID uint64) (*PlayResult, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	var userFsID uint64

	// Step 1: Check cache mapping
	cached, err := s.db.GetCacheMapping(shortURL, shareFsID)
	if err == nil && cached != nil && cached.IsTransferred && cached.RemoteUserFsID > 0 {
		userFsID = cached.RemoteUserFsID
	} else {
		// Step 2: JIT Transfer this single video
		transPath := "/apps/bdpan/stream_cache/" + videoName
		transFile, err := s.panClient.TransferSingleVideoSynchronous(ctx, shortURL, pwd, shareFsID, "/apps/bdpan/stream_cache")
		if err != nil {
			// Fallback to bdpan CLI
			cliErr := panapi.GetBDPANCli().TransferSelect(shortURL, pwd, shareFsID, "/apps/bdpan/stream_cache")
			if cliErr != nil {
				return nil, fmt.Errorf("即点即存失败 (API: %v, CLI: %v)", err, cliErr)
			}
			foundFsID, findErr := panapi.GetBDPANCli().FindTransferredFile("/apps/bdpan/stream_cache", videoName)
			if findErr == nil && foundFsID > 0 {
				userFsID = foundFsID
			} else {
				userFsID = shareFsID
			}
		} else {
			userFsID = transFile.FsID
			transPath = transFile.Path
		}

		now := time.Now()
		_ = s.db.SaveCacheMapping(&storage.VideoCacheRecord{
			ShareKey:       shortURL,
			ShareFsID:      shareFsID,
			VideoName:      videoName,
			RemoteUserFsID: userFsID,
			RemotePath:     transPath,
			IsTransferred:  true,
			TransferredAt:  &now,
		})
	}

	// Step 3: Get Dlink
	meta, err := s.panClient.GetFileDlink(ctx, userFsID)
	if err != nil {
		return nil, fmt.Errorf("获取直链失败: %w", err)
	}

	// Step 4: Register with local StreamProxy
	sessionID := generateSessionID()
	s.streamProxy.RegisterStream(sessionID, meta.Dlink, meta.Size)
	streamURL := s.streamProxy.GetStreamURL(sessionID)

	s.mu.Lock()
	s.activeDlinks[sessionID] = meta.Dlink
	s.mu.Unlock()

	// Step 5: Read last progress
	videoID := fmt.Sprintf("%s_%d", shortURL, shareFsID)
	prog, _ := s.db.GetProgress(videoID)
	lastTime := 0.0
	if prog != nil {
		if prog.ProgressPercent < 95 && prog.CurrentTime > 0 {
			lastTime = prog.CurrentTime
		}
	}

	duration := float64(meta.Duration)
	if duration <= 0 && prog != nil && prog.Duration > 0 {
		duration = prog.Duration
	}

	return &PlayResult{
		SessionID:   sessionID,
		StreamURL:   streamURL,
		RawDlink:    meta.Dlink,
		VideoID:     videoID,
		VideoName:   videoName,
		Duration:    duration,
		CurrentTime: lastTime,
	}, nil
}

func (s *AppService) SaveProgress(videoID, shareKey string, shareFsID uint64, videoName string, currTime, duration float64) error {
	return s.db.SaveProgress(&storage.PlaybackProgress{
		VideoID:     videoID,
		ShareKey:    shareKey,
		ShareFsID:   shareFsID,
		VideoName:   videoName,
		CurrentTime: currTime,
		Duration:    duration,
	})
}

func (s *AppService) GetProgress(videoID string) (*storage.PlaybackProgress, error) {
	return s.db.GetProgress(videoID)
}

func (s *AppService) ListHistory(limit int) ([]storage.PlaybackProgress, error) {
	return s.db.ListProgress(limit)
}

func (s *AppService) ClearHistory() error {
	return s.db.ClearProgress()
}

// 4. Favorites APIs
func (s *AppService) ListFavorites() ([]storage.FavoriteRecord, error) {
	return s.db.ListFavorites()
}

func (s *AppService) SaveFavorite(f *storage.FavoriteRecord) error {
	return s.db.SaveFavorite(f)
}

func (s *AppService) DeleteFavorite(shareKey string, fsID uint64) error {
	return s.db.DeleteFavorite(shareKey, fsID)
}

// 5. External Player
func (s *AppService) DetectPlayers() []player.InstalledPlayer {
	return player.DetectInstalledPlayers()
}

func (s *AppService) LaunchExternal(sessionID string, playerType string) error {
	s.mu.RLock()
	dlink, ok := s.activeDlinks[sessionID]
	s.mu.RUnlock()

	if !ok || dlink == "" {
		return fmt.Errorf("session dlink not found")
	}

	players := player.DetectInstalledPlayers()
	var target player.InstalledPlayer
	for _, p := range players {
		if string(p.Type) == strings.ToLower(playerType) {
			target = p
			break
		}
	}

	if target.Path == "" {
		if len(players) > 0 {
			target = players[0]
		} else {
			return fmt.Errorf("未在系统中检测到支持的播放器 (PotPlayer/VLC/MPV)")
		}
	}

	return player.LaunchWithDirectLink(target.Path, target.Type, dlink)
}

func generateSessionID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
