package storage

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"
)

type Database struct {
	db *sql.DB
}

func Open(dbPath string) (*Database, error) {
	if dbPath == "" {
		home, _ := os.UserHomeDir()
		dbPath = filepath.Join(home, ".config", "share-player", "player.db")
	}

	if err := os.MkdirAll(filepath.Dir(dbPath), 0755); err != nil {
		return nil, fmt.Errorf("failed to create db directory: %w", err)
	}

	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open sqlite db: %w", err)
	}

	// Set connection pool limits
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)

	d := &Database{db: db}
	if err := d.migrate(); err != nil {
		db.Close()
		return nil, fmt.Errorf("migration failed: %w", err)
	}

	return d, nil
}

func (d *Database) Close() error {
	return d.db.Close()
}

func (d *Database) migrate() error {
	queries := []string{
		`CREATE TABLE IF NOT EXISTS shares (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			share_key TEXT UNIQUE NOT NULL,
			share_url TEXT NOT NULL,
			pwd TEXT DEFAULT '',
			title TEXT NOT NULL,
			cover_url TEXT DEFAULT '',
			total_files INTEGER DEFAULT 0,
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
			updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE TABLE IF NOT EXISTS video_cache_mapping (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			share_key TEXT NOT NULL,
			share_fsid INTEGER NOT NULL,
			video_name TEXT NOT NULL,
			file_size INTEGER NOT NULL,
			remote_user_fsid INTEGER DEFAULT 0,
			remote_path TEXT DEFAULT '',
			is_transferred INTEGER DEFAULT 0,
			transferred_at DATETIME,
			UNIQUE(share_key, share_fsid)
		);`,
		`CREATE TABLE IF NOT EXISTS playback_progress (
			video_id TEXT PRIMARY KEY,
			share_key TEXT NOT NULL,
			share_fsid INTEGER NOT NULL,
			video_name TEXT NOT NULL,
			position_sec REAL DEFAULT 0.0,
			duration REAL DEFAULT 0.0,
			progress_percent REAL DEFAULT 0.0,
			is_finished INTEGER DEFAULT 0,
			last_played_at DATETIME DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE INDEX IF NOT EXISTS idx_progress_last_played ON playback_progress(last_played_at DESC);`,
		`CREATE INDEX IF NOT EXISTS idx_cache_share_key ON video_cache_mapping(share_key);`,
		`CREATE TABLE IF NOT EXISTS favorites (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			share_key TEXT NOT NULL,
			share_pwd TEXT DEFAULT '',
			fs_id INTEGER NOT NULL,
			name TEXT NOT NULL,
			is_dir INTEGER DEFAULT 0,
			path TEXT DEFAULT '',
			size INTEGER DEFAULT 0,
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
			UNIQUE(share_key, fs_id)
		);`,
		`CREATE INDEX IF NOT EXISTS idx_fav_share_key ON favorites(share_key);`,
	}

	for _, q := range queries {
		if _, err := d.db.Exec(q); err != nil {
			return err
		}
	}
	return nil
}

// Progress operations
func (d *Database) SaveProgress(p *PlaybackProgress) error {
	if p.Duration > 0 {
		p.ProgressPercent = (p.CurrentTime / p.Duration) * 100
		if p.ProgressPercent > 90 {
			p.IsFinished = true
		}
	}
	p.LastPlayedAt = time.Now()

	query := `INSERT INTO playback_progress (
		video_id, share_key, share_fsid, video_name, position_sec, duration, progress_percent, is_finished, last_played_at
	) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	ON CONFLICT(video_id) DO UPDATE SET
		position_sec=excluded.position_sec,
		duration=excluded.duration,
		progress_percent=excluded.progress_percent,
		is_finished=excluded.is_finished,
		last_played_at=excluded.last_played_at;`

	isFin := 0
	if p.IsFinished {
		isFin = 1
	}

	_, err := d.db.Exec(query,
		p.VideoID, p.ShareKey, p.ShareFsID, p.VideoName, p.CurrentTime, p.Duration, p.ProgressPercent, isFin, p.LastPlayedAt,
	)
	return err
}

func (d *Database) GetProgress(videoID string) (*PlaybackProgress, error) {
	query := `SELECT video_id, share_key, share_fsid, video_name, position_sec, duration, progress_percent, is_finished, last_played_at
	          FROM playback_progress WHERE video_id = ?`

	row := d.db.QueryRow(query, videoID)
	var p PlaybackProgress
	var isFin int

	err := row.Scan(
		&p.VideoID, &p.ShareKey, &p.ShareFsID, &p.VideoName, &p.CurrentTime, &p.Duration, &p.ProgressPercent, &isFin, &p.LastPlayedAt,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // not found
		}
		return nil, err
	}

	p.IsFinished = isFin == 1
	return &p, nil
}

// Share operations
func (d *Database) SaveShare(s *ShareRecord) error {
	now := time.Now()
	query := `INSERT INTO shares (share_key, share_url, pwd, title, cover_url, total_files, created_at, updated_at)
	          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	          ON CONFLICT(share_key) DO UPDATE SET
	          pwd=excluded.pwd, title=excluded.title, cover_url=excluded.cover_url, total_files=excluded.total_files, updated_at=excluded.updated_at;`

	res, err := d.db.Exec(query, s.ShareKey, s.ShareURL, s.Pwd, s.Title, s.CoverURL, s.TotalFiles, now, now)
	if err != nil {
		return err
	}
	id, _ := res.LastInsertId()
	s.ID = id
	return nil
}

func (d *Database) ListShares() ([]ShareRecord, error) {
	query := `SELECT id, share_key, share_url, pwd, title, cover_url, total_files, created_at, updated_at
	          FROM shares ORDER BY updated_at DESC`

	rows, err := d.db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []ShareRecord
	for rows.Next() {
		var s ShareRecord
		if err := rows.Scan(&s.ID, &s.ShareKey, &s.ShareURL, &s.Pwd, &s.Title, &s.CoverURL, &s.TotalFiles, &s.CreatedAt, &s.UpdatedAt); err != nil {
			return nil, err
		}
		result = append(result, s)
	}
	return result, nil
}

func (d *Database) DeleteShare(shareKey string) error {
	_, err := d.db.Exec("DELETE FROM shares WHERE share_key = ?", shareKey)
	return err
}

func (d *Database) UpdateShareTitle(shareKey, title string) error {
	_, err := d.db.Exec("UPDATE shares SET title = ?, updated_at = CURRENT_TIMESTAMP WHERE share_key = ?", title, shareKey)
	return err
}

// Cache mapping operations
func (d *Database) GetCacheMapping(shareKey string, shareFsID uint64) (*VideoCacheRecord, error) {
	query := `SELECT id, share_key, share_fsid, video_name, file_size, remote_user_fsid, remote_path, is_transferred, transferred_at
	          FROM video_cache_mapping WHERE share_key = ? AND share_fsid = ?`

	row := d.db.QueryRow(query, shareKey, shareFsID)
	var r VideoCacheRecord
	var isTrans int
	var transAt sql.NullTime

	err := row.Scan(&r.ID, &r.ShareKey, &r.ShareFsID, &r.VideoName, &r.FileSize, &r.RemoteUserFsID, &r.RemotePath, &isTrans, &transAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	r.IsTransferred = isTrans == 1
	if transAt.Valid {
		r.TransferredAt = &transAt.Time
	}
	return &r, nil
}

func (d *Database) SaveCacheMapping(r *VideoCacheRecord) error {
	query := `INSERT INTO video_cache_mapping (
		share_key, share_fsid, video_name, file_size, remote_user_fsid, remote_path, is_transferred, transferred_at
	) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	ON CONFLICT(share_key, share_fsid) DO UPDATE SET
		remote_user_fsid=excluded.remote_user_fsid,
		remote_path=excluded.remote_path,
		is_transferred=excluded.is_transferred,
		transferred_at=excluded.transferred_at;`

	isTrans := 0
	if r.IsTransferred {
		isTrans = 1
	}

	res, err := d.db.Exec(query,
		r.ShareKey, r.ShareFsID, r.VideoName, r.FileSize, r.RemoteUserFsID, r.RemotePath, isTrans, r.TransferredAt,
	)
	if err != nil {
		return err
	}
	id, _ := res.LastInsertId()
	r.ID = id
	return nil
}

func (d *Database) ListProgress(limit int) ([]PlaybackProgress, error) {
	if limit <= 0 {
		limit = 50
	}
	query := `SELECT video_id, share_key, share_fsid, video_name, position_sec, duration, progress_percent, is_finished, last_played_at
	          FROM playback_progress ORDER BY last_played_at DESC LIMIT ?`

	rows, err := d.db.Query(query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []PlaybackProgress
	for rows.Next() {
		var p PlaybackProgress
		var isFin int
		if err := rows.Scan(&p.VideoID, &p.ShareKey, &p.ShareFsID, &p.VideoName, &p.CurrentTime, &p.Duration, &p.ProgressPercent, &isFin, &p.LastPlayedAt); err != nil {
			return nil, err
		}
		p.IsFinished = isFin == 1
		list = append(list, p)
	}
	return list, nil
}

func (d *Database) ClearProgress() error {
	_, err := d.db.Exec("DELETE FROM playback_progress")
	return err
}

func (d *Database) ListFavorites() ([]FavoriteRecord, error) {
	query := `SELECT id, share_key, share_pwd, fs_id, name, is_dir, path, size, created_at
	          FROM favorites ORDER BY created_at DESC`

	rows, err := d.db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []FavoriteRecord
	for rows.Next() {
		var f FavoriteRecord
		var isDir int
		if err := rows.Scan(&f.ID, &f.ShareKey, &f.SharePwd, &f.FsID, &f.Name, &isDir, &f.Path, &f.Size, &f.CreatedAt); err != nil {
			return nil, err
		}
		f.IsDir = isDir == 1
		list = append(list, f)
	}
	return list, nil
}

func (d *Database) SaveFavorite(f *FavoriteRecord) error {
	isDir := 0
	if f.IsDir {
		isDir = 1
	}
	query := `INSERT INTO favorites (share_key, share_pwd, fs_id, name, is_dir, path, size, created_at)
	          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	          ON CONFLICT(share_key, fs_id) DO UPDATE SET
	          name=excluded.name, path=excluded.path, size=excluded.size;`

	res, err := d.db.Exec(query, f.ShareKey, f.SharePwd, f.FsID, f.Name, isDir, f.Path, f.Size, time.Now())
	if err != nil {
		return err
	}
	id, _ := res.LastInsertId()
	f.ID = id
	return nil
}

func (d *Database) DeleteFavorite(shareKey string, fsID uint64) error {
	query := `DELETE FROM favorites WHERE share_key = ? AND fs_id = ?`
	_, err := d.db.Exec(query, shareKey, fsID)
	return err
}
