package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/happydez/sj-wr-sender/internal/data"
	"github.com/happydez/sj-wr-sender/internal/validator"

	"github.com/gofiber/fiber/v3"
)

func (app *application) sourcejumpSendWR(c fiber.Ctx) error {
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
	v.Check(validator.NotBlank(req.ReplayPath), "replay_path", "replay file path is required")
	v.Check(validator.PermittedValue(filepath.Ext(req.ReplayPath), ".replay", ".rec", ".txt"), "replay_path", "unsupported file extension")
	if !v.Valid() {
		return c.Status(fiber.StatusUnprocessableEntity).JSON(fiber.Map{
			"error":  "validation failed",
			"fields": v.Errors,
		})
	}

	var base64Replay *string
	fileInfo, err := os.Stat(req.ReplayPath)
	if err != nil {
		app.logger.Warn("could not read replay file", "path", req.ReplayPath, "err", err)
	} else if fileInfo.Size() > app.config.SourceJump.MaxFileSize {
		app.logger.Info("replay file skipped: too large", "path", req.ReplayPath, "size_mb", float64(fileInfo.Size())/1024/1024)
	} else {
		fileContent, err := os.ReadFile(req.ReplayPath)
		if err != nil {
			app.logger.Error("failed to read replay file", "path", req.ReplayPath, "err", err)
		} else {
			encoded := base64.StdEncoding.EncodeToString(fileContent)
			base64Replay = &encoded
			app.logger.Debug("replay file encoded", "path", req.ReplayPath, "size_mb", float64(fileInfo.Size())/1024/1024)
		}
	}

	payload := data.SourceJumpPayload{
		PublicIP:    app.config.SourceJump.PublicIP,
		Hostname:    app.config.SourceJump.Hostname,
		PrivateKey:  app.config.SourceJump.PrivateKey,
		TimerPlugin: "shavit",
		Map:         req.Map,
		SteamID:     req.SteamID,
		Name:        req.Name,
		Time:        req.Time,
		Sync:        req.Sync,
		Strafes:     req.Strafes,
		Jumps:       req.Jumps,
		Date:        req.Date,
		Tickrate:    req.Tickrate,
		ReplayFile:  base64Replay,
	}

	app.logger.Debug("sourcejump payload", "payload", payload)

	go func(payload data.SourceJumpPayload) {
		client := &http.Client{
			Timeout: 30 * time.Second,
		}

		jsonData, _ := json.Marshal(payload)
		resp, err := client.Post(app.config.SourceJump.Receiver, "application/json", bytes.NewBuffer(jsonData))
		if err != nil {
			app.logger.Error("failed to send WR to SourceJump", "error", err)
			return
		}
		defer func() {
			_ = resp.Body.Close()
		}()

		if (resp.StatusCode != http.StatusCreated) && (resp.StatusCode != http.StatusOK) {
			respBody, err := io.ReadAll(resp.Body)
			if err != nil {
				app.logger.Error("could not read response body", "status", resp.Status, "error", err)
				return
			}

			if len(respBody) > 0 {
				app.logger.Error("SourceJump returned error status", "status", resp.Status, "body", string(respBody))
			} else {
				app.logger.Error("SourceJump returned error status with empty body", "status", resp.Status)
			}

			return
		}

		app.logger.Debug("WR successfully sent to SourceJump", "map", payload.Map, "player", payload.Name)
	}(payload)

	return c.SendStatus(fiber.StatusAccepted)
}
