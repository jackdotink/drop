local callbacks = require("@self/callbacks")
local schema = require("@self/schema")
local store = require("@self/store")

export type Schema<T> = schema.Schema<T>
export type Store<T> = store.Store<T>

return {
	callbacks = callbacks,

	schema = schema.create,
	migrate = schema.migrate,

	store = store.create,
	startrt = store.startrt,
	waitforrt = store.waitforrt,
	stoprtasync = store.stoprtasync,
	view = store.view,
	update = store.update,
	observe = store.observe,
	viewasync = store.viewasync,
	updateasync = store.updateasync,
	txasync = store.txasync,
}