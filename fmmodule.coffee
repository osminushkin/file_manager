fs = require "fs"
path = require "path"
express = require "express"

module.exports = (basePath, @extension) ->

	#check specified directory
	if not fs.existsSync basePath
		console.log "[fmmodule] Specified path not found"
		return
	if not fs.lstatSync(basePath).isDirectory()
		console.log "[fmmodule] Provided path is not a directory"
		return

	# Get top level directory and add / at the end if necessary
	basePathNormalize = path.normalize basePath
	# Chech basePath on / at the end of the string
	@targetDirPath = if basePathNormalize.search(/.*[\\\/]$/) isnt -1 then basePathNormalize else basePathNormalize + path.sep

	console.log "[fmmodule] Top level directory #{@targetDirPath}"
	console.log "[fmmodule] Target extension #{@extension}"

	app = express()
	# fu, ne krasivo
	# app.use express.logger()

	# redirect to path + /
	app.get /[^\/]$/, (req, res) ->
		console.log "[fmmodule] Redirect to " + req.path + "/"
		res.redirect req.path + "/"

	app.get "/*", (req, res) ->
		console.log "[GET] to " + req.path
		handleRequest req, res
	
	app.listen 3600
	console.log "[fmmodule] listening port " + 3600

################################################################################################################################
	handleRequest = (req, res) ->

		# calculate path of requested directory
		requestedPath = path.normalize(@targetDirPath + req.path)

		# check is requested path exists
		if not fs.existsSync requestedPath
			console.log "[handleRequest] Requested path not found: #{requestedPath}"
			res.status(500).send "Requested path not found"
			return

		fs.lstat requestedPath, (err, stats) ->
			if err?
				console.log "[handleRequest] Failed to get stats of #{requestedPath} due to error - #{err}"
				res.status(500).send "Failed to get stats of #{requestedPath} due to error - #{err}"
				return
			
			# if requested path is file then send it
			if stats.isFile()
				res.status(200).download requestedPath

			# if directory - read structure
			else

				children = []
				fileCount = 0
				fileExtensionCount = 0
				fileExtensionSize = 0

				# how to sort files and sub directories
				sortby = req.param "sortby"
				sortorder = req.param "sortorder"

				console.log "[readDirectory] read #{requestedPath}"
				# read directory structure
				getDirStat requestedPath, true, (params, err) ->

					if err?
						console.log "[readDirectory] Failed to get stats of #{requestedPath} due to error - #{err}"
						res.status 500
						res.send err
						return

					result = sortAndRenderResult params, sortby, sortorder, requestedPath, req.path

					res.status 200
					res.send result

################################################################################################################################
	sortAndRenderResult = ({children, size, fileCount, fileExtensionCount, fileExtensionSize}, sortby = "name", sortorder = "asc", requestedPath, path) ->

		result = switch sortby
			when "name"
				children.sort (a, b) ->
					sortByName a, b
			when "time"
				children.sort (a, b) ->
					res = a.time.getDate() - b.time.getDate()
					# if time is equal then sort by name
					if res is 0 then sortByName a, b else res
			when "size"
				children.sort (a, b) ->
					res = a.size - b.size
					# if size is equal then sort by name
					if res is 0 then sortByName a, b else res

		resultOrdered = if sortorder is "asc" then result else result.reverse()
		
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

		for instance in resultOrdered
			if instance.isFile
				toSend += "<tr><td><a href=\"#{instance.name}\">#{instance.name}</a></td><td>#{instance.size}</td><td>#{convertTime(instance.time)}</td></tr>"
			else
				toSend += "<tr><td><a href=\"#{instance.name}/\">#{instance.name}/..</a></td><td>#{instance.size}</td><td>#{convertTime(instance.time)}</td></tr>"

		toSend += "<tr><td colspan=\"3\">Total files count is #{fileCount}</td></tr>"
		toSend += "<tr><td colspan=\"3\">Total directory size is #{size}</td></tr>"
		toSend += "<tr><td colspan=\"3\">Total #{@extension} files count is #{fileExtensionCount}</td></tr>"
		toSend += "<tr><td colspan=\"3\">Total Size of  #{@extension} files is #{fileExtensionSize}</td></tr>"
		toSend += "</table></body></html>"

		return toSend
################################################################################################################################
	sortByName = (a, b) ->
		keyA = a.name
		keyB = b.name
		if keyA > keyB then 1 else if keyA < keyB then -1 else 0
################################################################################################################################
	getDirStat = (dirPath, saveChildren, callback) ->

		fileCount = 0
		fileExtensionCount = 0
		fileExtensionSize = 0
		size = 0
		instCalculated = 0
		children = []

		# read directory structure
		fs.readdir dirPath, (err, dir) ->

			if err?
				console.log "[getDirStat] Failed to read directory #{dirPath} due to error - #{err}"
				callback(null, err)
				return

			# for each internal file or directory
			for instance in dir
				# get absolute instance path to get stat
				instPath = path.join dirPath, instance
				# get stat
				do (instPath) ->
					fs.lstat instPath, (err, instStat) ->
						if err?
							console.log "[getDirStat] Failed to get stats of #{instPath} due to error - #{err}"
							callback(null, err)
							return

						if instStat.isDirectory()
							# if directory, lets take a look inside
							getDirStat instPath, false, (stat, err) ->

								if err?
									console.log "[getDirStat] Failed to get stats of #{instPath} due to error - #{err}"
									callback(null, err)
									isFailed = true
									return

								fileExtensionCount += stat.fileExtensionCount
								fileExtensionSize += stat.fileExtensionSize
								fileCount += stat.fileCount
								size += stat.size

								if saveChildren
									children.push
										isFile: false
										name: path.basename instPath
										size: stat.size
										time: instStat.mtime

								# check if all data is collected then return the result
								instCalculated++
								if instCalculated is dir.length
									callback({children, size, fileCount, fileExtensionCount, fileExtensionSize})

						else

							# if file has expected extension, then calculate size and count
							if path.extname(instPath) is @extension
								fileExtensionCount++
								fileExtensionSize += instStat.size
							fileCount++
							size += instStat.size

							if saveChildren
								children.push
									isFile: true
									name: path.basename instPath
									size: instStat.size
									time: instStat.mtime

							# check if all data is collected then return the result
							instCalculated++
							if instCalculated is dir.length
								callback({children, size, fileCount, fileExtensionCount, fileExtensionSize})


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
