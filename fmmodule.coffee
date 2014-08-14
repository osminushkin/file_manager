fs = require "fs"
path = require "path"
express = require "express"

module.exports = (basePath, @extension) ->

	#check specified directory
	if not fs.existsSync basePath
		console.log "[fmmodule] Specified path not found"
		return
	if not fs.statSync(basePath).isDirectory()
		console.log "[fmmodule] Provided path is not a directory"
		return

	# Get top level directory and add / at the end if necessary
	basePathNormalize = path.normalize basePath
	# Chech basePath on / at the end of the string
	@targetDirPath = if basePathNormalize.search(new RegExp ".*[\\\\/]$") isnt -1 then basePathNormalize else basePathNormalize + path.sep
	lastDir = path.basename(@targetDirPath)

	console.log "[fmmodule] Top level directory #{@targetDirPath}"
	console.log "[fmmodule] Target extension #{@extension}"

	app = express()

	app.get "/" + lastDir + "*", (req, res, next) ->
		console.log "[GET] " + req.path
		next()

	app.get "/" + lastDir + "*", (req, res, next) ->
		res.set "Access-Control-Allow-Origin", "*"
		next()

	app.get "/index", (req, res, next) ->
		res.redirect "/" + lastDir + "/"

	app.get "/" + lastDir + "*", (req, res) ->
		handleRequest req, res
	
	app.listen 3600
	console.log "[fmmodule] listening port " + 3600


	handleRequest = (req, res) ->
		# in case of such requests - dirname/..
		# and replace all \ on /
		resolved = path.join(req.path).replace new RegExp("\\\\",'g'), "/"
		# calculate path of requested directory
		requestedPath = path.normalize(path.dirname(@targetDirPath) + resolved)

		# how to sort files and sub directories
		sortby = req.query.sortby
		sortorder = req.query.sortorder

		console.log "[handleRequest] #{req.path}"

		# if requested path is file then send it
		if fs.statSync(requestedPath).isFile()
			res.status(200).download(requestedPath)
			return
		else
			if req.path.search(new RegExp ".*/$") is -1
				console.log "Add slash"
				res.redirect req.path + "/"

		# this will be returned to client
		# TODO: add href to table header for sorting
		toSend = "<html><head><title>qwer</title></head><body><table border=1><tr><th>File name</th><th>Size</th><th>Creation time</th></tr>"
		# if top dir then skip .. element
		if requestedPath isnt @targetDirPath
			toSend += "<tr><td><a href=\"../\">..</a></td><td></td><td></td></tr>"
		# get all from directory
		toSend += readDirectory requestedPath, sortby, sortorder

		toSend += "</table></body></html>"
		res.status 200
		res.send toSend
		

	convertTime = (date) ->
		data = if date.getDay() < 10 then "0" + date.getDay() else date.getDay()
		mon = if date.getMonth() < 10 then "0" + date.getMonth() else date.getMonth()
		year = date.getFullYear()
		hour = if date.getHours() < 10 then "0" + date.getHours() else date.getHours()
		min = if date.getMinutes() < 10 then "0" + date.getMinutes() else date.getMinutes()
		return data + "-" + mon + "-" + year +  "&nbsp;&nbsp;&nbsp;&nbsp;" + hour + ":" + min


	readDirectory = (requestedPath, sortby, sortorder) ->
		toSend = ""
		# read directory structure
		dir = fs.readdirSync requestedPath
		# TODO: sort dir as requested before use
		# for each internal file or directory
		for instance in dir
			# get absolute instance path to get stat
			instPath = path.normalize requestedPath + "/" + instance
			# get stat
			instStat = fs.statSync instPath
			# get path for request
			if instStat.isDirectory()
				toSend += "<tr><td><a href=\"#{instance}/\">#{instance}/..</a></td><td>-</td><td>#{convertTime(instStat.mtime)}</td></tr>"
			else
				toSend += "<tr><td><a href=#{instance}>#{instance}</a></td><td>#{instStat.size}</td><td>#{convertTime(instStat.mtime)}</td></tr>"

		# get files count and files size
		dirStat = getDirStat requestedPath
		toSend += "<tr><td colspan=\"3\">Total files count is #{dirStat.tfc}</td></tr>"
		toSend += "<tr><td colspan=\"3\">Total #{@extension} files count is #{dirStat.fec}</td></tr>"
		toSend += "<tr><td colspan=\"3\">Total Size of  #{@extension} files is #{dirStat.fes}</td></tr>"

		return toSend


	getDirStat = (dirPath) ->
		fileCount = 0
		fileExtensionCount = 0
		fileExtensionSize = 0
		console.log "[getDirStat] Get stat of " + dirPath
		# read directory structure
		dir = fs.readdirSync dirPath
		# for each internal file or directory
		for instance in dir
			# get absolute instance path to get stat
			instPath = path.normalize dirPath + "/" + instance
			# get stat
			instStat = fs.statSync instPath

			if instStat.isDirectory()
				# if directory, lets take a look inside
				res = getDirStat instPath
				fileCount += res.tfc
				fileExtensionCount += res.fec
				fileExtensionSize += res.fes
			else
				# if file has expected extension, then calculate size and count
				if path.extname(instance) is @extension
					fileExtensionCount++
					fileExtensionSize += instStat.size
				fileCount++

		return fec: fileExtensionCount, fes: fileExtensionSize, tfc: fileCount

