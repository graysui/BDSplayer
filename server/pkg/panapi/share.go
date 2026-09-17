package panapi

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"path/filepath"
	"regexp"
	"strings"
)

type ShareURLInfo struct {
	OriginalURL string `json:"original_url"`
	ShortURL    string `json:"short_url"`
	Pwd         string `json:"pwd"`
}

var (
	shareRegex1 = regexp.MustCompile(`https?://pan\.baidu\.com/s/1([a-zA-Z0-9_-]+)`)
	shareRegex2 = regexp.MustCompile(`https?://pan\.baidu\.com/s/([a-zA-Z0-9_-]+)`)
	shareRegex3 = regexp.MustCompile(`surl=([a-zA-Z0-9_-]+)`)
	pwdRegex1   = regexp.MustCompile(`pwd=([a-zA-Z0-9]{4})`)
	pwdRegex2   = regexp.MustCompile(`(?:提取码|密码)[：:\s]*([a-zA-Z0-9]{4})`)
)

func ParseShareInput(input string) (*ShareURLInfo, error) {
	info := &ShareURLInfo{OriginalURL: strings.TrimSpace(input)}

	if m := shareRegex1.FindStringSubmatch(input); len(m) > 1 {
		info.ShortURL = m[1]
	} else if m := shareRegex3.FindStringSubmatch(input); len(m) > 1 {
		info.ShortURL = m[1]
	} else if m := shareRegex2.FindStringSubmatch(input); len(m) > 1 {
		info.ShortURL = m[1]
	}

	if info.ShortURL == "" {
		return nil, fmt.Errorf("no valid Baidu Pan share link found in input")
	}

	if m := pwdRegex1.FindStringSubmatch(input); len(m) > 1 {
		info.Pwd = m[1]
	} else if m := pwdRegex2.FindStringSubmatch(input); len(m) > 1 {
		info.Pwd = m[1]
	}

	return info, nil
}

type ShareFileItem struct {
	FsID     uint64 `json:"fs_id"`
	Name     string `json:"name"`
	IsDir    bool   `json:"is_dir"`
	Size     int64  `json:"size"`
	Path     string `json:"path"`
	Category int    `json:"category"`
	IsVideo  bool   `json:"is_video"`
}

type ShareListResponse struct {
	Errno     int    `json:"errno"`
	ErrMsg    string `json:"errmsg"`
	RequestID string `json:"request_id"`
	Data      struct {
		Count   int `json:"count"`
		HasMore int `json:"has_more"`
		Items   []struct {
			FsID     uint64 `json:"fs_id"`
			Name     string `json:"name"`
			IsDir    int    `json:"is_dir"`
			Size     int64  `json:"size"`
			Path     string `json:"path"`
			Category int    `json:"category"`
		} `json:"items"`
	} `json:"data"`
}

var videoExtensions = map[string]bool{
	".mp4":  true,
	".mkv":  true,
	".avi":  true,
	".flv":  true,
	".mov":  true,
	".wmv":  true,
	".ts":   true,
	".rmvb": true,
	".webm": true,
	".m4v":  true,
	".iso":  true,
}

func IsVideoFile(filename string) bool {
	ext := strings.ToLower(filepath.Ext(filename))
	return videoExtensions[ext]
}

func (c *Client) ListShareFiles(ctx context.Context, shortURL, pwd, sourceDir string, page, pageSize int) ([]ShareFileItem, bool, error) {
	token, err := c.getAccessToken()
	if err != nil {
		return nil, false, err
	}

	if pageSize <= 0 || pageSize > 100 {
		pageSize = 100
	}
	if page <= 0 {
		page = 1
	}

	u := "https://pan.baidu.com/apaas/1.0/share/list"
	params := url.Values{
		"product":      {"netdisk"},
		"access_token": {token},
		"short_url":    {shortURL},
		"page":         {fmt.Sprintf("%d", page)},
		"page_size":    {fmt.Sprintf("%d", pageSize)},
	}
	if pwd != "" {
		params.Set("pwd", pwd)
	}
	if sourceDir != "" {
		if !strings.HasPrefix(sourceDir, "/") {
			sourceDir = "/" + sourceDir
		}
		params.Set("source_dir", sourceDir)
	}

	fullURL := fmt.Sprintf("%s?%s", u, params.Encode())
	data, err := c.doRequest(ctx, "GET", fullURL, nil, nil)
	if err != nil {
		return nil, false, err
	}

	var resp ShareListResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		return nil, false, fmt.Errorf("failed to decode share list response: %w", err)
	}

	if resp.Errno != 0 {
		return nil, false, fmt.Errorf("share list api error code %d: %s", resp.Errno, resp.ErrMsg)
	}

	items := make([]ShareFileItem, 0, len(resp.Data.Items))
	for _, it := range resp.Data.Items {
		isDir := it.IsDir == 1
		isVideo := !isDir && (it.Category == 1 || IsVideoFile(it.Name))
		items = append(items, ShareFileItem{
			FsID:     it.FsID,
			Name:     it.Name,
			IsDir:    isDir,
			Size:     it.Size,
			Path:     it.Path,
			Category: it.Category,
			IsVideo:  isVideo,
		})
	}

	hasMore := resp.Data.HasMore == 1
	return items, hasMore, nil
}
