package panapi

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"strings"
)

type FileMetaInfo struct {
	FsID     uint64 `json:"fs_id"`
	Filename string `json:"filename"`
	Size     int64  `json:"size"`
	Path     string `json:"path"`
	Category int    `json:"category"`
	Dlink    string `json:"dlink"`
	Duration int    `json:"duration,omitempty"` // in seconds
	Width    int    `json:"width,omitempty"`
	Height   int    `json:"height,omitempty"`
}

type FileMetasResponse struct {
	Errno  int    `json:"errno"`
	ErrMsg string `json:"errmsg"`
	List   []struct {
		FsID       uint64 `json:"fs_id"`
		Filename   string `json:"filename"`
		Size       int64  `json:"size"`
		Path       string `json:"path"`
		Category   int    `json:"category"`
		Dlink      string `json:"dlink"`
		Duration   int    `json:"duration"`
		MediaInfo  struct {
			Duration   int `json:"duration"`
			Width      int `json:"width"`
			Height     int `json:"height"`
		} `json:"media_info"`
	} `json:"list"`
}

func (c *Client) GetFileDlink(ctx context.Context, fsid uint64) (*FileMetaInfo, error) {
	token, err := c.getAccessToken()
	if err != nil {
		return nil, err
	}

	u := "https://pan.baidu.com/rest/2.0/xpan/multimedia"
	fsidsJSON := fmt.Sprintf("[%d]", fsid)

	params := url.Values{
		"method":       {"filemetas"},
		"access_token": {token},
		"fsids":        {fsidsJSON},
		"dlink":        {"1"},
		"needmedia":    {"1"},
		"detail":       {"1"},
	}

	fullURL := fmt.Sprintf("%s?%s", u, params.Encode())
	data, err := c.doRequest(ctx, "GET", fullURL, nil, map[string]string{
		"User-Agent": "pan.baidu.com",
	})
	if err != nil {
		return nil, err
	}

	var resp FileMetasResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		return nil, fmt.Errorf("failed to decode filemetas response: %w", err)
	}

	if resp.Errno != 0 {
		return nil, fmt.Errorf("filemetas api error %d: %s", resp.Errno, resp.ErrMsg)
	}

	if len(resp.List) == 0 {
		return nil, fmt.Errorf("no file info returned for fsid %d", fsid)
	}

	raw := resp.List[0]
	if raw.Dlink == "" {
		return nil, fmt.Errorf("file exists but dlink is empty for fsid %d", fsid)
	}

	finalDlink := raw.Dlink
	if !strings.Contains(finalDlink, "access_token=") {
		if strings.Contains(finalDlink, "?") {
			finalDlink = fmt.Sprintf("%s&access_token=%s", finalDlink, token)
		} else {
			finalDlink = fmt.Sprintf("%s?access_token=%s", finalDlink, token)
		}
	}

	duration := raw.Duration
	if duration <= 0 && raw.MediaInfo.Duration > 0 {
		duration = raw.MediaInfo.Duration
	}

	return &FileMetaInfo{
		FsID:     raw.FsID,
		Filename: raw.Filename,
		Size:     raw.Size,
		Path:     raw.Path,
		Category: raw.Category,
		Dlink:    finalDlink,
		Duration: duration,
		Width:    raw.MediaInfo.Width,
		Height:   raw.MediaInfo.Height,
	}, nil
}
