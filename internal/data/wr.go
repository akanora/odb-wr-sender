package data

// WRRequest - what the odb-wr-sender.smx plugin will send
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
	Style      int     `json:"style"`
	ReplayPath string  `json:"replay_path"`
	Hostname   string  `json:"hostname"`
	PublicIP   string  `json:"public_ip"`
	PrivateKey string  `json:"private_key"`
}

// OffstyleDBPayload - what will be sent to OffstyleDB
type OffstyleDBPayload struct {
	Map         string  `json:"map"`
	SteamID     string  `json:"steamid"`
	Name        string  `json:"name"`
	Time        float64 `json:"time"`
	Sync        float64 `json:"sync"`
	Strafes     int     `json:"strafes"`
	Jumps       int     `json:"jumps"`
	Date        string  `json:"date"`
	Tickrate    int     `json:"tickrate"`
	Style       int     `json:"style"`
}
