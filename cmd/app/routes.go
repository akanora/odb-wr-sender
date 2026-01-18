package main

func (app *application) routes() {
	// healthcheck
	app.healthcheck()

	// sourcejump wr sender
	sj := app.server.Group("/sourcejump")
	sj.Post("send-wr", app.sourcejumpSendWR)
}
