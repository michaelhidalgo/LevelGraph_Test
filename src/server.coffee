express = require 'express'
server  = express()

server.get('/', (req, res) -> res.send('hello 123 another test') )


module.exports = server

