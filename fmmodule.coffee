fs 			= require "fs"
path 		= require "path"
express 	= require "express"
async		= require "async"
mongoose 	= require "mongoose"

module.exports = (basePath, @extension) ->
	self = this
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

	FSItemSchema = new mongoose.Schema {
		isFile: Boolean,
		name: String,
		size: Number,
		time: Date,
		url: {type: String, unique: true},
		fileCount: Number,
		fileExtensionCount: Number,
		fileExtensionSize: Number,
		children: [String]
		createdAt: { type: Date, expires: 180, default: Date.now }
	}

	@FSItemModel = mongoose.model 'FSItem', FSItemSchema

	# Get top level directory and add / at the end if necessary
	basePathNormalize = path.normalize basePath
	# Chech basePath on / at the end of the string
	@targetDirPath = if basePathNormalize.search(/.*[\\\/]$/) isnt -1 then basePathNormalize else basePathNormalize + path.sep

	console.log "[fmmodule] Top level directory #{@targetDirPath}"
	console.log "[fmmodule] Target extension #{@extension}"

	# Init server here to prevent incoming requests before connetion to DB established
	app = express()

	app.get "/favicon.ico", (req, res) ->
		res.status(500).send "Zadolbal etot favicon"

	app.get "/*", (req, res) ->
		console.log "[GET] to " + req.path
		handleRequest req, res
	
	app.listen 3600
	console.log "[fmmodule] listening port " + 3600

################################################################################################################################
	handleRequest = (req, res) ->

		# calculate path of requested directory
		requestedPath = path.normalize(@targetDirPath + req.path)
		# exclude last /
		requestedPath = path.join path.dirname(requestedPath), path.basename(requestedPath)

		# how to sort files and sub directories
		sortby = req.param "sortby"
		sortorder = req.param "sortorder"

		sortRenderSend = (params) ->
			sortAndRenderResult	req.path, requestedPath, params
				, (result) ->
					res.status 200
					res.send result

				, sortby
				, sortorder

		# Check is request result cached
		FSItemModel.findOne { url : requestedPath }, (err, fsItem) ->
			if fsItem?
				console.log "[handleRequest] FS item found in DB (url:#{req.path})"
				# if fs item is file then send it
				if fsItem.isFile
					res.status(200).download requestedPath
				else
					# Get all children from DB
					FSItemModel.find { url : { $in : fsItem.children } }, (err, chFSItems) ->
						if err?
							console.log "[handleRequest] Failed to get children from DB (url:#{req.path})"
							return
						console.log "[handleRequest] Children found in DB (url:#{req.path})"

						# create array of found children's urls
						foundChildrenUrls = chFSItems.map (chFSItem) ->
							chFSItem.url

						# and get the difference between expected and found
						notFoundChildren = []
						fsItem.children.forEach (child) ->
							if foundChildrenUrls.indexOf(child) is -1 then notFoundChildren.push child

						# For each not found in DB children 
						async.map notFoundChildren
							, (child, next) ->
								getDirStat child
									, (err, params, next) ->
										if err?
											next err
											return
										next null, params
									, next

							, (err, updatedChildren) ->
								if err?
									res.status(500).send msg
									return
								# join found in DB children with just fetched
								allChildren = chFSItems.concat updatedChildren
								sortRenderSend {
									children:allChildren,
									size:fsItem.size,
									fileCount:fsItem.fileCount,
									fileExtensionCount:fsItem.fileExtensionCount,
									fileExtensionSize:fsItem.fileExtensionSize
								}
			else
				console.log "[handleRequest] cached object not found"

				# check is requested path exists
				fs.exists requestedPath, (exists) ->

					if not exists
						msg = "Requested path not found: #{req.path}"
						console.log "[handleRequest] #{msg}"
						res.status(500).send msg
						return

					fs.lstat requestedPath, (err, stats) ->
						if err?
							msg = "Failed to get stats of #{req.path} due to error - #{err}"
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

							# read directory structure
							console.log "[handleRequest] read #{req.path}"
							getDirStat requestedPath, (err, params) ->

								if err?
									msg = "Failed to get stats of #{req.path} due to error - #{err}"
									console.error "[handleRequest] #{msg}"
									res.status(500).send msg
									return

								sortRenderSend params

								
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
		if requestedPath + path.sep isnt @targetDirPath
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
	getDirStat = (dirPath, callback, next) ->

		fileCount = 0
		fileExtensionCount = 0
		fileExtensionSize = 0
		size = 0
		time = 0
		isFile = false
		instCalculated = 0
		children = []
		name = path.basename dirPath
		url = dirPath

		envokeCallback = (err) ->
			if err? then callback err else callback(null, {isFile, name, url, children, size, time, fileCount, fileExtensionCount, fileExtensionSize}, next)

		saveToDb = () ->
			cacheData {isFile, name, url, children, size, time, fileCount, fileExtensionCount, fileExtensionSize}

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

				saveToDb()
				envokeCallback()
			else

				# read directory structure
				fs.readdir dirPath, (err, dir) ->

					if err?
						console.log "[getDirStat] Failed to read directory #{dirPath} due to error - #{err}"
						envokeCallback err
						return

					if dir.length is 0
						saveToDb()
						envokeCallback()
						return

					async.each dir
						# Iterator function of each statement
						, (instance, next) ->
							# get absolute instance path to get stat
							instPath = path.join dirPath, instance
							# get stat
							getDirStat instPath, (err, stat) ->

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

								children.push
									isFile: stat.isFile
									name: stat.name
									url: stat.url
									size: stat.size
									time: stat.time
									fileCount: stat.fileCount
									fileExtensionCount: stat.fileExtensionCount
									fileExtensionSize: stat.fileExtensionSize
									children: stat.children

								next()
						# callback function of each statement
						, (err) ->
							if err?
								console.log "[getDirStat] Failed to get stats of #{dirPath} due to error - #{err}"
								envokeCallback err
								return
							# All data is collected without an error
							saveToDb()
							envokeCallback()

################################################################################################################################
	cacheData = (params) ->
		# change real children objects by links
		childrenLinks = params.children.map (child)->
			child.url
		
		params.children = childrenLinks
		params.createdAt = Date.now()

		self.FSItemModel.findOneAndUpdate { url: params.url }, params, { upsert: true }, (err, fsItem)->
			if err?
				console.log "[handleRequest] Failed to save object (url:#{params.url})"
				console.log err
				return
			console.log "[handleRequest] Object cached (url:#{params.url})"


################################################################################################################################
	convertTime = (date) ->

		day = toStringLength2 date.getDay()
		month = toStringLength2 date.getMonth()
		year = date.getFullYear()
		hour = toStringLength2 date.getHours()
		min = toStringLength2 date.getMinutes()
		return day + "-" + month + "-" + year +  "&nbsp;&nbsp;&nbsp;&nbsp;" + hour + ":" + min
################################################################################################################################
	toStringLength2 = (number) ->
		if number < 10 then "0" + number else number
################################################################################################################################