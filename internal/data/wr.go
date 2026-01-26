package data

// WRRequest - what the sj-wr-sender.smx plugin will send
type WRRequest struct {
	Map        string  `json:"map"`
	SteamID    string  `json:"steamid"`
	Name       string  `json:"name"`
	Time       float64 `json:"time"`
	Sync       float64 `json:"sync"`
	Strafes    int     `json:"strafes"`
	Jumps      int     `json:"jumps"`
	Date       string  `json:"date"`
	Tickrate   int     `json:"tickrate"`
	ReplayPath string  `json:"replay_path"`
	Hostname   string  `json:"hostname"`
	PublicIP   string  `json:"public_ip"`
	PrivateKey string  `json:"private_key"`
}

// SourceJumpPayload - what will be sent to sourcejump (or another receiver)
type SourceJumpPayload struct {
	PublicIP    string  `json:"public_ip"`
	PrivateKey  string  `json:"private_key"`
	Hostname    string  `json:"hostname"`
	TimerPlugin string  `json:"timer_plugin"`
	Map         string  `json:"map"`
	SteamID     string  `json:"steamid"`
	Name        string  `json:"name"`
	Time        float64 `json:"time"`
	Sync        float64 `json:"sync"`
	Strafes     int     `json:"strafes"`
	Jumps       int     `json:"jumps"`
	Date        string  `json:"date"`
	Tickrate    int     `json:"tickrate"`
	ReplayFile  *string `json:"replayfile"`
}
