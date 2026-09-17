package storage

import "time"

type ShareRecord struct {
	ID         int64     `json:"id"`
	ShareKey   string    `json:"share_key"`
	ShareURL   string    `json:"share_url"`
	Pwd        string    `json:"pwd"`
	Title      string    `json:"title"`
	CoverURL   string    `json:"cover_url"`
	TotalFiles int       `json:"total_files"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

type VideoCacheRecord struct {
	ID             int64      `json:"id"`
	ShareKey       string     `json:"share_key"`
	ShareFsID      uint64     `json:"share_fsid"`
	VideoName      string     `json:"video_name"`
	FileSize       int64      `json:"file_size"`
	RemoteUserFsID uint64     `json:"remote_user_fsid"`
	RemotePath     string     `json:"remote_path"`
	IsTransferred  bool       `json:"is_transferred"`
	TransferredAt  *time.Time `json:"transferred_at"`
}

type PlaybackProgress struct {
	VideoID         string    `json:"video_id"` // share_key + "_" + share_fsid
	ShareKey        string    `json:"share_key"`
	ShareFsID       uint64    `json:"share_fsid"`
	VideoName       string    `json:"video_name"`
	CurrentTime     float64   `json:"current_time"` // in seconds
	Duration        float64   `json:"duration"`     // in seconds
	ProgressPercent float64   `json:"progress_percent"`
	IsFinished      bool      `json:"is_finished"` // > 90%
	LastPlayedAt    time.Time `json:"last_played_at"`
}

type FavoriteRecord struct {
	ID        int64     `json:"id"`
	ShareKey  string    `json:"share_key"`
	SharePwd  string    `json:"share_pwd"`
	FsID      uint64    `json:"fs_id"`
	Name      string    `json:"name"`
	IsDir     bool      `json:"is_dir"`
	Path      string    `json:"path"`
	Size      int64     `json:"size"`
	CreatedAt time.Time `json:"created_at"`
}

