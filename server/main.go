package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"share-player/pkg/nativeweb"
	"share-player/pkg/panapi"
	"share-player/pkg/service"
	"share-player/pkg/storage"
	"strconv"
	"strings"
	"time"

	"github.com/jchv/go-webview2"
)


func main() {
	serverOnly := flag.Bool("server-only", false, "仅启动 Web 服务，不打开桌面窗口")
	port := flag.Int("port", 18900, "本地服务端口")
	flag.Parse()

	home, _ := os.UserHomeDir()
	dataDir := filepath.Join(home, ".config", "BDSplayer")
	_ = os.MkdirAll(dataDir, 0755)

	dbPath := filepath.Join(dataDir, "player.db")
	authPath := filepath.Join(dataDir, "auth.json")
	bdpanConfigPath := filepath.Join(dataDir, "bdpan.json")

	// Set custom isolated config path for bdpan CLI
	panapi.GetBDPANCli().SetConfigPath(bdpanConfigPath)

	// Initialize AppService (with Baidu Netdisk AppKey)
	appSvc, err := service.NewAppService("zF5kkNsCvckX4aIpRdHxpFkcSMxnGZky", dbPath, authPath)
	if err != nil {
		fmt.Printf("Error initializing service: %v\n", err)
		os.Exit(1)
	}
	defer appSvc.Close()

	mux := http.NewServeMux()

	// 1. API Endpoints
	mux.HandleFunc("/api/status", func(w http.ResponseWriter, r *http.Request) {
		isLogged, userStr := appSvc.GetLoginStatus()
		players := appSvc.DetectPlayers()
		jsonResponse(w, http.StatusOK, map[string]any{
			"logged_in": isLogged,
			"user_info": userStr,
			"players":   players,
		})
	})

	mux.HandleFunc("/api/auth/logout", func(w http.ResponseWriter, r *http.Request) {
		err := appSvc.Logout()
		if err != nil {
			jsonResponse(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"success": true})
	})

	mux.HandleFunc("/api/exit", func(w http.ResponseWriter, r *http.Request) {
		jsonResponse(w, http.StatusOK, map[string]any{"ok": true})
		go func() {
			panapi.GetBDPANCli().CancelLogin()
			time.Sleep(50 * time.Millisecond)
			os.Exit(0)
		}()
	})

	mux.HandleFunc("/api/auth/cancel_login", func(w http.ResponseWriter, r *http.Request) {
		panapi.GetBDPANCli().CancelLogin()
		jsonResponse(w, http.StatusOK, map[string]any{"success": true})
	})

	mux.HandleFunc("/api/auth/device_code", func(w http.ResponseWriter, r *http.Request) {
		resp, err := appSvc.StartDeviceLogin()
		if err != nil {
			jsonResponse(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		jsonResponse(w, http.StatusOK, resp)
	})

	// Proxy the short-lived QR image through localhost. WebView2 installations
	// with restrictive image/network policies can otherwise leave the modal
	// spinning even though the device-code request itself succeeded.
	mux.HandleFunc("/api/auth/qrcode", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		data, contentType, err := panapi.FetchDeviceQRCode(r.URL.Query().Get("url"))
		if err != nil {
			jsonResponse(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Type", contentType)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(data)
	})

	mux.HandleFunc("/api/auth/poll", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			DeviceCode string `json:"device_code"`
		}
		_ = json.NewDecoder(r.Body).Decode(&req)
		success, err := appSvc.PollDeviceLogin(req.DeviceCode)
		if err != nil {
			jsonResponse(w, http.StatusBadRequest, map[string]any{"success": false, "error": err.Error()})
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"success": success})
	})

	mux.HandleFunc("/api/auth/submit_code", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req struct {
			Code string `json:"code"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.Code) == "" {
			jsonResponse(w, http.StatusBadRequest, map[string]string{"error": "请提供有效的授权码"})
			return
		}
		if err := appSvc.SubmitAuthCode(req.Code); err != nil {
			jsonResponse(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"success": true})
	})

	mux.HandleFunc("/api/auth/auth_url", func(w http.ResponseWriter, r *http.Request) {
		jsonResponse(w, http.StatusOK, map[string]string{
			"url": panapi.BaiduOAuthURL,
		})
	})

	mux.HandleFunc("/api/shares", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet {
			list, err := appSvc.ListShares()
			if err != nil {
				jsonResponse(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
				return
			}
			jsonResponse(w, http.StatusOK, list)
			return
		}

		if r.Method == http.MethodPost {
			var req struct {
				Input string `json:"input"`
			}
			_ = json.NewDecoder(r.Body).Decode(&req)
			record, err := appSvc.AddShare(req.Input)
			if err != nil {
				jsonResponse(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
				return
			}
			jsonResponse(w, http.StatusOK, record)
			return
		}

		if r.Method == http.MethodDelete {
			var req struct {
				ShareKey string `json:"share_key"`
			}
			_ = json.NewDecoder(r.Body).Decode(&req)
			if req.ShareKey == "" {
				req.ShareKey = r.URL.Query().Get("share_key")
			}
			if err := appSvc.DeleteShare(req.ShareKey); err != nil {
				jsonResponse(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
				return
			}
			jsonResponse(w, http.StatusOK, map[string]bool{"ok": true})
			return
		}

		if r.Method == http.MethodPut {
			var req struct {
				ShareKey string `json:"share_key"`
				Title    string `json:"title"`
			}
			_ = json.NewDecoder(r.Body).Decode(&req)
			if err := appSvc.UpdateShareTitle(req.ShareKey, req.Title); err != nil {
				jsonResponse(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
				return
			}
			jsonResponse(w, http.StatusOK, map[string]bool{"ok": true})
			return
		}

		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	})

	// /api/shares/{key}/files
	mux.HandleFunc("/api/shares/", func(w http.ResponseWriter, r *http.Request) {
		parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/api/shares/"), "/")
		if len(parts) >= 2 && parts[1] == "files" {
			shareKey := parts[0]
			pwd := r.URL.Query().Get("pwd")
			sourceDir := r.URL.Query().Get("source_dir")
			page, _ := strconv.Atoi(r.URL.Query().Get("page"))
			if page <= 0 {
				page = 1
			}

			items, hasMore, err := appSvc.GetShareFiles(shareKey, pwd, sourceDir, page)
			if err != nil {
				jsonResponse(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
				return
			}
			jsonResponse(w, http.StatusOK, map[string]any{
				"items":    items,
				"has_more": hasMore,
			})
			return
		}
		http.NotFound(w, r)
	})

	mux.HandleFunc("/api/play", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			ShareKey  string `json:"share_key"`
			Pwd       string `json:"pwd"`
			VideoName string `json:"video_name"`
			ShareFsID uint64 `json:"share_fsid"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			jsonResponse(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}

		res, err := appSvc.PreparePlay(req.ShareKey, req.Pwd, req.VideoName, req.ShareFsID)
		if err != nil {
			jsonResponse(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		jsonResponse(w, http.StatusOK, res)
	})

	mux.HandleFunc("/api/progress", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet {
			videoID := r.URL.Query().Get("video_id")
			prog, err := appSvc.GetProgress(videoID)
			if err != nil {
				jsonResponse(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
				return
			}
			jsonResponse(w, http.StatusOK, prog)
			return
		}

		if r.Method == http.MethodPost {
			var req struct {
				VideoID     string  `json:"video_id"`
				ShareKey    string  `json:"share_key"`
				ShareFsID   uint64  `json:"share_fsid"`
				VideoName   string  `json:"video_name"`
				CurrentTime float64 `json:"current_time"`
				Duration    float64 `json:"duration"`
			}
			_ = json.NewDecoder(r.Body).Decode(&req)
			_ = appSvc.SaveProgress(req.VideoID, req.ShareKey, req.ShareFsID, req.VideoName, req.CurrentTime, req.Duration)
			jsonResponse(w, http.StatusOK, map[string]bool{"ok": true})
			return
		}
	})

	mux.HandleFunc("/api/history", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet {
			list, err := appSvc.ListHistory(50)
			if err != nil {
				jsonResponse(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
				return
			}
			jsonResponse(w, http.StatusOK, list)
			return
		}
		if r.Method == http.MethodDelete {
			err := appSvc.ClearHistory()
			if err != nil {
				jsonResponse(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
				return
			}
			jsonResponse(w, http.StatusOK, map[string]bool{"ok": true})
			return
		}
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	})

	mux.HandleFunc("/api/favorites", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet {
			favs, err := appSvc.ListFavorites()
			if err != nil {
				jsonResponse(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
				return
			}
			jsonResponse(w, http.StatusOK, favs)
			return
		}
		if r.Method == http.MethodPost {
			var fav storage.FavoriteRecord
			if err := json.NewDecoder(r.Body).Decode(&fav); err != nil {
				jsonResponse(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
				return
			}
			if err := appSvc.SaveFavorite(&fav); err != nil {
				jsonResponse(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
				return
			}
			jsonResponse(w, http.StatusOK, fav)
			return
		}
		if r.Method == http.MethodDelete {
			var req struct {
				ShareKey string `json:"share_key"`
				FsID     uint64 `json:"fs_id"`
			}
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				jsonResponse(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
				return
			}
			if err := appSvc.DeleteFavorite(req.ShareKey, req.FsID); err != nil {
				jsonResponse(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
				return
			}
			jsonResponse(w, http.StatusOK, map[string]bool{"ok": true})
			return
		}
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	})

	mux.HandleFunc("/api/launch_external", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			SessionID  string `json:"session_id"`
			PlayerType string `json:"player_type"`
		}
		_ = json.NewDecoder(r.Body).Decode(&req)
		err := appSvc.LaunchExternal(req.SessionID, req.PlayerType)
		if err != nil {
			jsonResponse(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		jsonResponse(w, http.StatusOK, map[string]bool{"ok": true})
	})

	// 2. Stream Proxy Handler
	mux.Handle("/stream", appSvc.GetStreamHandler())

	// 3. Status Index Handler
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = w.Write([]byte("BDSplayer Service Running"))
	})

	serverAddr := fmt.Sprintf("127.0.0.1:%d", *port)
	ln, err := net.Listen("tcp", serverAddr)
	if err != nil {
		// Port in use: attempt to evict old instance by sending exit request
		client := &http.Client{Timeout: 500 * time.Millisecond}
		_, _ = client.Post(fmt.Sprintf("http://127.0.0.1:%d/api/exit", *port), "application/json", nil)
		time.Sleep(350 * time.Millisecond)
		ln, err = net.Listen("tcp", serverAddr)
		if err != nil {
			// Fallback to random available port if specified port remains in use
			ln, err = net.Listen("tcp", "127.0.0.1:0")
			if err != nil {
				fmt.Printf("启动 HTTP 监听失败: %v\n", err)
				os.Exit(1)
			}
		}
	}
	actualAddr := ln.Addr().String()
	appSvc.SetBaseURL(fmt.Sprintf("http://%s", actualAddr))

	go func() {
		fmt.Printf("服务已就绪: http://%s\n", actualAddr)
		_ = http.Serve(ln, mux)
	}()

	// 4. Desktop GUI Mode
	if !*serverOnly {
		// Use stable GPU acceleration while disabling problematic DirectComposition video overlays that cause cadence glitches
		_ = os.Setenv("WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS",
			"--enable-gpu-rasterization --ignore-gpu-blocklist --disable-direct-composition-video-overlays")

		w := webview2.NewWithOptions(webview2.WebViewOptions{
			Debug:     false,
			AutoFocus: true,
			WindowOptions: webview2.WindowOptions{
				Title:  "百度网盘分享视频播放器",
				Width:  1280,
				Height: 800,
			},
		})
		if w != nil {
			defer w.Destroy()

			// Enable native direct stream interception for Baidu Netdisk CDN
			nativeweb.EnableBaiduDirectStreamInterception(w)

			w.Navigate(fmt.Sprintf("http://%s/", actualAddr))
			w.Run()
			return
		}
	}

	// Fallback or server-only mode
	fmt.Printf("按 Ctrl+C 退出。请在浏览器访问: http://%s\n", actualAddr)
	select {}
}

func jsonResponse(w http.ResponseWriter, code int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(data)
}
