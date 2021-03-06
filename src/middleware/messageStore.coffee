transactions = require "../model/transactions"
logger = require "winston"

transactionStatus = 
	PROCESSING: 'Processing'
	SUCCESSFUL: 'Successful'
	COMPLETED: 'Completed'
	COMPLETED_W_ERR: 'Completed with error(s)'
	FAILED: 'Failed'

exports.storeTransaction = (ctx, done) -> 
	logger.info 'Storing request metadata for inbound transaction'

	tx = new transactions.Transaction
		status: transactionStatus.PROCESSING
		clientID: ctx.authenticated._id
		channelID: ctx.authorisedChannel._id
		request:
			path: ctx.path
			headers: ctx.header
			querystring: ctx.querystring
			body: ctx.body
			method: ctx.method
			timestamp: new Date()

	if ctx.parentID && ctx.taskID
		tx.parentID = ctx.parentID
		tx.taskID = ctx.taskID

	tx.save (err, tx) ->
		if err
			logger.error 'Could not save transaction metadata: ' + err
			return done err
		else
			ctx.transactionId = tx._id
			return done null, tx

exports.storeResponse = (ctx, done) ->
	logger.info 'Storing response for transaction: ' + ctx.transactionId

	routeFailures = false
	routeSuccess = true
	if ctx.routes
		for route in ctx.routes
			if 500 <= route.response.status <= 599
				routeFailures = true
			if not (200 <= route.response.status <= 299)
				routeSuccess = false

	if (500 <= ctx.response.status <= 599)
		status = transactionStatus.FAILED
	else
		if routeFailures
			status = transactionStatus.COMPLETED_W_ERR
		if (200 <= ctx.response.status <= 299) && routeSuccess
			status = transactionStatus.SUCCESSFUL

	# In all other cases mark as completed
	if status is null or status is undefined
		status = transactionStatus.COMPLETED
	
	res =
		status: ctx.response.status
		headers: ctx.response.header
		body: if not ctx.response.body then "" else ctx.response.body.toString()
		timestamp: ctx.response.timestamp

	# assign new transactions status to ctx object
	ctx.transactionStatus = status

	# Rename header -> headers
	if ctx.routes
		for route in ctx.routes
			route.response.headers = route.response.header
			delete route.response.header

	transactions.Transaction.findOneAndUpdate { _id: ctx.transactionId }, { response: res, status: status, routes: ctx.routes }, (err, tx) ->
		if err
			logger.error 'Could not save response metadata for transaction: ' + ctx.transactionId + '. ' + err
			return done err
		if tx is undefined or tx is null
			logger.error 'Could not find transaction: ' + ctx.transactionId
			return done err
		return done()

exports.koaMiddleware =  `function *storeMiddleware(next) {
		exports.storeTransaction(this, function(){});
		yield next;
		exports.storeResponse(this, function(){});
	}`
