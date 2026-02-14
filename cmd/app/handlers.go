package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/akanora/odb-wr-sender/internal/data"
	"github.com/akanora/odb-wr-sender/internal/validator"

	"github.com/gofiber/fiber/v3"
)

func (app *application) offstyleDBSendWR(c fiber.Ctx) error {
	var req data.WRRequest
	if err := c.Bind().JSON(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid request",
		})
	}

	v := validator.New()
	v.Check(validator.NotBlank(req.Map), "map", "map name must be provided")
	v.Check(validator.NotBlank(req.SteamID), "steamid", "steamid must be provided")
	v.Check(req.Time > 0, "time", "time must be greater than zero")
	v.Check(req.Tickrate == 100, "tickrate", "only 100 tickrate records are accepted")
	v.Check(req.Strafes >= 0, "strafes", "strafes count cannot be negative")
	v.Check(req.Jumps >= 0, "jumps", "jumps count cannot be negative")
	v.Check(req.Style >= 0, "style", "style must be zero or higher")
	v.Check(req.Date > 0, "date", "date must be a unix timestamp")
	v.Check(validator.NotBlank(req.ReplayPath), "replay_path", "replay file path is required")
	v.Check(validator.PermittedValue(filepath.Ext(req.ReplayPath), ".replay", ".rec", ".txt"), "replay_path", "unsupported file extension")
	if !v.Valid() {
		return c.Status(fiber.StatusUnprocessableEntity).JSON(fiber.Map{
			"error":  "validation failed",
			"fields": v.Errors,
		})
	}

	fileInfo, fileStatErr := os.Stat(req.ReplayPath)
	if fileStatErr != nil {
		app.logger.Warn("could not read replay file", "path", req.ReplayPath, "err", fileStatErr)
	}

	payload := data.OffstyleDBPayload{
		Map:      req.Map,
		SteamID:  req.SteamID,
		Name:     req.Name,
		Time:     req.Time,
		Sync:     req.Sync,
		Strafes:  req.Strafes,
		Jumps:    req.Jumps,
		Date:     req.Date,
		Tickrate: req.Tickrate,
		Style:    req.Style,
	}

	app.logger.Debug("offstyledb payload", "payload", payload)

	go func(payload data.OffstyleDBPayload, replayPath string, replayInfo os.FileInfo, replayStatErr error) {
		client := &http.Client{
			Timeout: 30 * time.Second,
		}

		baseURL := strings.TrimRight(app.config.OffstyleDB.Receiver, "/")
		submitURL := baseURL + "/submit_record_nr"
		uploadURL := baseURL + "/upload_replay"

		jsonData, _ := json.Marshal(payload)
		request, err := http.NewRequest(http.MethodPost, submitURL, bytes.NewBuffer(jsonData))
		if err != nil {
			app.logger.Error("failed to build OffstyleDB request", "error", err)
			return
		}
		request.Header.Set("Content-Type", "application/json")
		request.Header.Set("auth", req.PrivateKey)
		request.Header.Set("public_ip", req.PublicIP)
		request.Header.Set("hostname", req.Hostname)
		request.Header.Set("timer_plugin", "shavit")

		resp, err := client.Do(request)
		if err != nil {
			app.logger.Error("failed to send record to OffstyleDB", "error", err)
			return
		}
		defer func() {
			_ = resp.Body.Close()
		}()

		if (resp.StatusCode != http.StatusCreated) && (resp.StatusCode != http.StatusOK) {
			respBody, err := io.ReadAll(resp.Body)
			if err != nil {
				app.logger.Error("could not read OffstyleDB response body", "status", resp.Status, "error", err)
				return
			}

			if len(respBody) > 0 {
				app.logger.Error("OffstyleDB returned error status", "status", resp.Status, "body", string(respBody))
			} else {
				app.logger.Error("OffstyleDB returned error status with empty body", "status", resp.Status)
			}

			return
		}

		app.logger.Debug("record submitted to OffstyleDB", "map", payload.Map, "player", payload.Name)

		var submitResponse struct {
			ReplayKey string `json:"replay_key"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&submitResponse); err != nil {
			app.logger.Debug("OffstyleDB submit response did not contain JSON", "error", err)
			return
		}

		if submitResponse.ReplayKey == "" {
			app.logger.Debug("OffstyleDB submit response missing replay_key")
			return
		}

		if replayStatErr != nil {
			app.logger.Warn("replay file missing, skipping upload", "path", replayPath)
			return
		}

		if replayInfo.Size() > app.config.OffstyleDB.MaxFileSize {
			app.logger.Info("replay file skipped: too large", "path", replayPath, "size_mb", float64(replayInfo.Size())/1024/1024)
			return
		}

		file, err := os.Open(replayPath)
		if err != nil {
			app.logger.Error("failed to open replay file", "path", replayPath, "err", err)
			return
		}
		defer func() {
			_ = file.Close()
		}()

		uploadRequest, err := http.NewRequest(http.MethodPut, uploadURL, file)
		if err != nil {
			app.logger.Error("failed to build replay upload request", "err", err)
			return
		}
		uploadRequest.ContentLength = replayInfo.Size()
		uploadRequest.Header.Set("Content-Type", "application/octet-stream")
		uploadRequest.Header.Set("auth", req.PrivateKey)
		uploadRequest.Header.Set("public_ip", req.PublicIP)
		uploadRequest.Header.Set("hostname", req.Hostname)
		uploadRequest.Header.Set("timer_plugin", "shavit")
		uploadRequest.Header.Set("replay_key", submitResponse.ReplayKey)

		uploadResp, err := client.Do(uploadRequest)
		if err != nil {
			app.logger.Error("failed to upload replay to OffstyleDB", "error", err)
			return
		}
		defer func() {
			_ = uploadResp.Body.Close()
		}()

		if uploadResp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(uploadResp.Body)
			if len(body) > 0 {
				app.logger.Error("OffstyleDB replay upload failed", "status", uploadResp.Status, "body", string(body))
			} else {
				app.logger.Error("OffstyleDB replay upload failed", "status", uploadResp.Status)
			}
			return
		}

		app.logger.Debug("replay uploaded to OffstyleDB", "map", payload.Map, "player", payload.Name, "filename", filepath.Base(replayPath))
	}(payload, req.ReplayPath, fileInfo, fileStatErr)

	return c.SendStatus(fiber.StatusAccepted)
}
