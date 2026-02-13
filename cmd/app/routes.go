package main

func (app *application) routes() {
	// healthcheck
	app.healthcheck()

	// offstyledb wr sender
	odb := app.server.Group("/offstyledb")
	odb.Post("send-wr", app.offstyleDBSendWR)
}
