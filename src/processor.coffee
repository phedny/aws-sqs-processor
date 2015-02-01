{EventEmitter} = require 'events'
util = require 'util'

AWS = require 'aws-sdk'

class Processor extends EventEmitter

    constructor: (options) ->
        @_options = util._extend
            maxNumberOfMessagesProcessing: 50
            maxNumberOfMessagesPerBatch: 10
            visibilityTimeout: 30
            waitTimeSeconds: 20
        , options

        # The AWS SDK SQS object for communication
        @_sqs = @_options._sqs or new AWS.SQS options

        # The number of messages we may receive from currently active requests
        @_receiving = 0

        # The messages we're currently processing
        @_processing = []

        # Flag to prevent have multiple start() loops running
        @_running = false

    _receive: =>

        # Determine the number of messages to request
        numberOfMessagesToRequest = Math.min @_options.maxNumberOfMessagesPerBatch, @_options.maxNumberOfMessagesProcessing - @_processing.length - @_receiving
        return false if numberOfMessagesToRequest < 1

        # Account that we're requesting a certain amount of messages
        @_receiving += numberOfMessagesToRequest
        @_sqs.receiveMessage
            QueueUrl: @_options.queueUrl
            MaxNumberOfMessages: numberOfMessagesToRequest
            VisibilityTimeout: @_options.visibilityTimeout
            WaitTimeSeconds: @_options.waitTimeSeconds

        , (err, data) =>

            # Account that we're no longer receiving those messages
            @_receiving -= numberOfMessagesToRequest

            # If the request failed, emit the error
            # Note that @_receiving has been decreased and no @_processing is updated
            return @emit 'error', err if err?

            # Handle the message (initiates processing)
            # statusFunctions is an array holding status functions for messages
            statusFunctions = (@_handleMessage message for message in data.Messages || [])
            @_processing = @_processing.concat statusFunctions

            iValObject = setInterval =>
                # Determine which messages have not completed or failed yet
                visibilityList = (i for f, i in statusFunctions when (status = f()) and not (status.completed or status.failed))

                # We don't need to check up anymore if no message need to be changed
                return clearInterval iValObject unless visibilityList.length

                @_sqs.changeMessageVisibilityBatch
                    QueueUrl: @_options.queueUrl
                    Entries: for i in visibilityList
                        Id: i.toString()
                        ReceiptHandle: data.Messages[i].ReceiptHandle
                        VisibilityTimeout: @_options.visibilityTimeout
                , (err, data) =>
                    # If the request failed, emit the error
                    return @emit 'error', err if err?

                    # Emit errors for failed updates
                    for failed in data.Failed
                        error = new Error failed.Message
                        error.failedMessage = data.Messages[i]
                        error.senderFault = failed.SenderFault
                        error.code = failed.Code
                        @emit 'error', error

            , 1000 * (@_options.visibilityTimeout - 1)

        return true

    _handleMessage: (message) =>

        # Processing has neither completed nor failed and has not been deleted yet
        completed = false
        failed = false
        deleted = false

        # Callback to notify processor has finished
        done = (err) =>
            # Emit an error when the state of this message has already been determined
            return @emit 'error', new Error 'done() called on finished message' if completed or failed

            # Mark the message as failed if there is an error argument or mark it completed otherwise
            if err?
                failed = true
            else
                completed = true

        try
            # Handle the message
            # When there are no listeners (@emit returned false), mark a failure to allow reprocessing of the message
            failed = true unless @emit 'message', message, done
        catch err
            # An error occured while handling the message
            failed = true

        # Return a function to query the status of this message
        (setDeleted = false) ->
            deleted = true if setDeleted
            messageId: message.MessageId
            receiptHandle: message.ReceiptHandle
            completed: completed
            failed: failed
            deleted: deleted

    _deleteCompletedMessages: =>
        # Determine which messages have completed
        statusFunctions = @_processing
        totalDeleteList = (i for f, i in statusFunctions when (status = f()) and status.completed)
        return unless totalDeleteList.length

        batchIndex = 0
        batchSize = @_options.maxNumberOfMessagesPerBatch
        
        while (deleteList = totalDeleteList[batchIndex...batchIndex+batchSize]).length
            @_sqs.deleteMessageBatch
                QueueUrl: @_options.queueUrl
                Entries: for i in deleteList
                    Id: i.toString()
                    ReceiptHandle: statusFunctions[i]().receiptHandle
            , (err, data) =>
                # If the request failed, emit the error
                return @emit 'error', err if err?

                # Emit errors for failed updates
                for failed in data.Failed
                    error = new Error failed.Message
                    error.failedMessage = data.Messages[i]
                    error.senderFault = failed.SenderFault
                    error.code = failed.Code
                    @emit 'error', error

                # Mark messages deleted when successful
                statusFunctions[success.Id] true for success in data.Successful
            batchIndex += batchSize


    start: =>
        return if @_running
        @_running = true
        setInterval =>
            # Remove deleted and failed messages from the processing list
            @_processing = @_processing.filter (f) -> (status = f()) and not (status.deleted or status.failed)

            # Delete the messages that are completed
            @_deleteCompletedMessages()

            # Receive new set of messages
            @_receive()
        , 1000

module.exports = (options) -> new Processor options
