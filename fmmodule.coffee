fs 			= require "fs"
path 		= require "path"
express 	= require "express"
async		= require "async"
mongoose 	= require "mongoose"

module.exports = (basePath, @extension) ->

	#check specified directory
	if not fs.existsSync basePath
		console.log "[fmmodule] Specified path not found"
		return
	if not fs.lstatSync(basePath).isDirectory()
		console.log "[fmmodule] Provided path is not a directory"
		return

	mongoose.connect "mongodb://localhost/file_manager"

	mongoose.connection.on "error", (err) ->
		console.error "connection error: #{err.message}"
		process.exit()
	mongoose.connection.once "open", () ->
		console.log "Connected to DB!"

		# Init server here to prevent incoming requests before connetion to DB established
		app = express()

		app.get "/favicon.ico", (req, res) ->
			res.status(500).send "Zadolbal etot favicon"

		app.get "/*", (req, res) ->
			console.log "[GET] to " + req.path
			handleRequest req, res
		
		app.listen 3600
		console.log "[fmmodule] listening port " + 3600

	FSItemHtmlSchema = mongoose.Schema { html: String, url: String }

	@FSItemHtmlModel = mongoose.model 'FSItem', FSItemHtmlSchema

	# Get top level directory and add / at the end if necessary
	basePathNormalize = path.normalize basePath
	# Chech basePath on / at the end of the string
	@targetDirPath = if basePathNormalize.search(/.*[\\\/]$/) isnt -1 then basePathNormalize else basePathNormalize + path.sep

	console.log "[fmmodule] Top level directory #{@targetDirPath}"
	console.log "[fmmodule] Target extension #{@extension}"

################################################################################################################################
	handleRequest = (req, res) ->

		# calculate path of requested directory
		requestedPath = path.normalize(@targetDirPath + req.path)

		# check is requested path exists
		fs.exists requestedPath, (exists) ->

			if not exists
				msg = "Requested path not found: #{requestedPath}"
				console.log "[handleRequest] #{msg}"
				res.status(500).send msg
				return

			fs.lstat requestedPath, (err, stats) ->
				if err?
					msg = "Failed to get stats of #{requestedPath} due to error - #{err}"
					console.error "[handleRequest] #{msg}"
					res.status(500).send msg
					return
				
				# if requested path is file then send it
				if stats.isFile()
					res.status(200).download requestedPath

				# if directory - read structure
				else

					# if directory and request without / then redirect to path + /
					if req.path.search(/.*\/$/) is -1
						console.log "[handleRequest] Redirect to " + req.path + "/"
						res.redirect req.path + "/"
						return

					# how to sort files and sub directories
					sortby = req.param "sortby"
					sortorder = req.param "sortorder"

					# Check is request result is cashed already
					@FSItemHtmlModel.findOne { "url":req.url }, (err, fsItem) ->

						# if object found then send it back
						if fsItem?
							console.log "[handleRequest] Found cashed object"
							res.status 200
							res.send fsItem.html
							return

						# if failed to read from DB print the error and go forward to read dir structure
						if err? 
							console.error "[handleRequest] Failed to get cashed info from DB: #{err}"

						# read directory structure and send back
						console.log "[handleRequest] read #{requestedPath}"
						getDirStat requestedPath, true, (err, params) ->

							if err?
								msg = "Failed to get stats of #{requestedPath} due to error - #{err}"
								console.error "[handleRequest] #{msg}"
								res.status(500).send msg
								return

							sortAndRenderResult	req.path, requestedPath, params
								, (result) ->
									# Save request result
									htmlToSend = new @FSItemHtmlModel {html: result, url: req.url}
									htmlToSend.save (err) ->
										if err?
											console.log "[handleRequest] Failed to save request result (url:#{req.path})"
											console.log err
											return
										console.log "[handleRequest] Request result cashed"

									res.status 200
									res.send result

								, sortby
								, sortorder

################################################################################################################################
	sortAndRenderResult = (path, requestedPath, {children, size, fileCount, fileExtensionCount, fileExtensionSize}, callback, sortby = "name", sortorder = "asc") ->

		result = switch sortby
			when "name"
				children.sort (a, b) ->
					res = sortByName a, b
					if sortorder is "asc" then res*1 else res*-1
			when "time"
				children.sort (a, b) ->
					res = a.time.getDate() - b.time.getDate()
					# if time is equal then sort by name
					res = if res is 0 then sortByName a, b else res
					if sortorder is "asc" then res*1 else res*-1
			when "size"
				children.sort (a, b) ->
					res = a.size - b.size
					# if size is equal then sort by name
					res = if res is 0 then sortByName a, b else res
					if sortorder is "asc" then res*1 else res*-1
		
		sortToSend = if sortorder is "asc" then "desc" else "asc"

		# this will be returned to client
		toSend = """
				<html><head><title>qwer</title></head><body>
					<table border=1>
						<tr>
							<th><a href=\"#{path}?sortby=name&sortorder=#{sortToSend}\">File name</a></th>
							<th><a href=\"#{path}?sortby=size&sortorder=#{sortToSend}\">Size</a></th>
							<th><a href=\"#{path}?sortby=time&sortorder=#{sortToSend}\">Creation time</a></th>
						</tr>
				"""

		# if top dir then skip .. element
		if requestedPath isnt @targetDirPath
			toSend += "<tr><td><a href=\"../\">..</a></td><td></td><td></td></tr>"

		# Order is important here, so each is not selected
		async.mapSeries result
			, (instance, next) ->
				itemHtml = ""
				if instance.isFile
					itemHtml = "<tr><td><a href=\"#{instance.name}\">#{instance.name}</a></td><td>#{instance.size}</td><td>#{convertTime(instance.time)}</td></tr>"
				else
					itemHtml = "<tr><td><a href=\"#{instance.name}/\">#{instance.name}/..</a></td><td>#{instance.size}</td><td>#{convertTime(instance.time)}</td></tr>"
				next null, itemHtml
			, (err, results) ->
				toSend += results.join ""
				toSend += "<tr><td colspan=\"3\">Total files count is #{fileCount}</td></tr>"
				toSend += "<tr><td colspan=\"3\">Total directory size is #{size}</td></tr>"
				toSend += "<tr><td colspan=\"3\">Total #{@extension} files count is #{fileExtensionCount}</td></tr>"
				toSend += "<tr><td colspan=\"3\">Total Size of  #{@extension} files is #{fileExtensionSize}</td></tr>"
				toSend += "</table></body></html>"
				callback toSend
################################################################################################################################
	sortByName = (a, b) ->
		keyA = a.name.toLowerCase()
		keyB = b.name.toLowerCase()
		if keyA > keyB then 1 else if keyA < keyB then -1 else 0
################################################################################################################################
	getDirStat = (dirPath, saveChildren, callback) ->

		fileCount = 0
		fileExtensionCount = 0
		fileExtensionSize = 0
		size = 0
		time = 0
		isFile = false
		instCalculated = 0
		children = []
		envokeCallback = (err) ->
			if err? then callback err else callback(null, {isFile, children, size, time, fileCount, fileExtensionCount, fileExtensionSize})

		fs.lstat dirPath, (err, dirPathStat) ->
			
			time = dirPathStat.mtime

			if dirPathStat.isFile()
				# if file has expected extension, then calculate size and count
				if path.extname(dirPath) is @extension
					fileExtensionCount++
					fileExtensionSize += dirPathStat.size
				fileCount++
				size += dirPathStat.size
				isFile = true

				envokeCallback()
			else

				# read directory structure
				fs.readdir dirPath, (err, dir) ->

					if err?
						console.log "[getDirStat] Failed to read directory #{dirPath} due to error - #{err}"
						envokeCallback err
						return

					if dir.length is 0
						envokeCallback()
						return

					async.each dir
						# Iterator function of each statement
						, (instance, next) ->
							# get absolute instance path to get stat
							instPath = path.join dirPath, instance
							# get stat
							getDirStat instPath, false, (err, stat) ->

								if err?
									console.log "[getDirStat] Failed to get stats of #{instPath} due to error - #{err}"
									next(err)
									return

								# calculate directory params
								fileExtensionCount += stat.fileExtensionCount
								fileExtensionSize += stat.fileExtensionSize
								fileCount += stat.fileCount
								size += stat.size
								isFile = false

								if saveChildren
									children.push
										isFile: stat.isFile
										name: path.basename instPath
										size: stat.size
										time: stat.time

								next()
						# callback function of each statement
						, (err) ->
							if err?
								console.log "[getDirStat] Failed to get stats of #{dirPath} due to error - #{err}"
								envokeCallback err
								return
							# All data is collected without an error	
							envokeCallback()

################################################################################################################################

	convertTime = (date) ->

		day = toStringLength2 date.getDay()
		month = toStringLength2 date.getMonth()
		year = date.getFullYear()
		hour = toStringLength2 date.getHours()
		min = toStringLength2 date.getMinutes()
		return day + "-" + month + "-" + year +  "&nbsp;&nbsp;&nbsp;&nbsp;" + hour + ":" + min

	toStringLength2 = (number) ->
		if number < 10 then "0" + number else number
