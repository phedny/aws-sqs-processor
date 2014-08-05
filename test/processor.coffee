expect = require 'expect.js'
sinon = require 'sinon'

Processor = require '../src/processor'

describe 'Processor', ->

    clock = null
    sqs = null
    processor = null
    beforeEach ->
        clock = sinon.useFakeTimers()
        sqs =
            receiveMessage: sinon.stub().callsArgWithAsync 1, null,
                Messages: [
                    MessageId: ':id1'
                    ReceiptHandle: ':rpt1'
                    Body: 'Message 1'
                ,
                    MessageId: ':id2'
                    ReceiptHandle: ':rpt2'
                    Body: 'Message 2'
                ]
            changeMessageVisibilityBatch: sinon.stub().callsArgWithAsync 1, null,
                Successful: [
                    Id: '0'
                ,
                    Id: '1'
                ]
                Failed: []
            deleteMessageBatch: sinon.stub().callsArgWithAsync 1, null,
                Successful: [
                    Id: '0'
                ,
                    Id: '1'
                ]
                Failed: []
        processor = Processor
            _sqs: sqs
            queueUrl: '/queueUrl/'
            maxNumberOfMessagesProcessing: 5
            maxNumberOfMessagesPerBatch: 2
    afterEach ->
        clock.restore()

    it 'requests first two messages one second after start', ->
        # given
        processor.start()
        # when
        clock.tick 1000
        # then
        expectedQuery =
            QueueUrl: '/queueUrl/'
            MaxNumberOfMessages: 2
            VisibilityTimeout: 30
            WaitTimeSeconds: 20
        expect(sqs.receiveMessage.calledWith expectedQuery).to.be true

    it 'requests first two messages two seconds after start', ->
        # given
        processor.start()
        # when
        clock.tick 2000
        # then
        expect(sqs.receiveMessage.callCount).to.be 2

    it 'requests fifth single message three seconds after start', ->
        # given
        processor.start()
        # when
        clock.tick 3000
        # then
        expectedQuery =
            QueueUrl: '/queueUrl/'
            MaxNumberOfMessages: 1
            VisibilityTimeout: 30
            WaitTimeSeconds: 20
        expect(sqs.receiveMessage.calledWith expectedQuery).to.be true

    it 'does not request any more messages afterwards', ->
        # given
        processor.start()
        # when
        clock.tick 10000
        # then
        expect(sqs.receiveMessage.callCount).to.be 3

    it 'emits the received messages', (done) ->
        # given
        receivedMessages = []
        processor.on 'message', (message) -> receivedMessages.push message
        processor.start()
        # when
        clock.tick 1000
        # then
        process.nextTick ->
            expect(receivedMessages).to.eql [
                    MessageId: ':id1'
                    ReceiptHandle: ':rpt1'
                    Body: 'Message 1'
                ,
                    MessageId: ':id2'
                    ReceiptHandle: ':rpt2'
                    Body: 'Message 2'
                ]
            done()

    it 'changes the visibility of unfinished messages', (done) ->
        # given
        processor.on 'message', ->
        processor.start()
        # when
        clock.tick 5000
        process.nextTick ->
            clock.tick 30000
            # then
            expectedQuery =
                QueueUrl: '/queueUrl/'
                Entries: [
                    Id: '0'
                    ReceiptHandle: ':rpt1'
                    VisibilityTimeout: 30
                ,
                    Id: '1'
                    ReceiptHandle: ':rpt2'
                    VisibilityTimeout: 30
                ]
            expect(sqs.changeMessageVisibilityBatch.callCount).to.be 1 * 3
            expect(sqs.changeMessageVisibilityBatch.calledWith expectedQuery).to.be true
            done()

    it 'changes the visibility of unfinished messages multiple times', (done) ->
        # given
        processor.on 'message', ->
        processor.start()
        # when
        clock.tick 5000
        process.nextTick ->
            clock.tick 120000
            # then
            expect(sqs.changeMessageVisibilityBatch.callCount).to.be 4 * 3
            done()

    it 'deletes finished messages', (done) ->
        # given
        processor.start()
        processor.on 'message', (message, done) -> done()
        # when
        clock.tick 1000
        process.nextTick ->
            clock.tick 1000
            # then
            expectedQuery =
                QueueUrl: '/queueUrl/'
                Entries: [
                    Id: '0'
                    ReceiptHandle: ':rpt1'
                ,
                    Id: '1'
                    ReceiptHandle: ':rpt2'
                ]
            expect(sqs.deleteMessageBatch.callCount).to.be 1
            expect(sqs.deleteMessageBatch.calledWith expectedQuery).to.be true
            done()

    it 'does not change visibility on deleted messages', (done) ->
        # given
        processor.start()
        processor.on 'message', (message, done) ->
            done() unless message.ReceiptHandle is ':rpt1'
        # when
        clock.tick 5000
        process.nextTick ->
            clock.tick 30000
            # then
            expectedQuery =
                QueueUrl: '/queueUrl/'
                Entries: [
                    Id: '0'
                    ReceiptHandle: ':rpt1'
                    VisibilityTimeout: 30
                ]
            expect(sqs.changeMessageVisibilityBatch.callCount).to.be 1 * 3
            expect(sqs.changeMessageVisibilityBatch.calledWith expectedQuery).to.be true
            done()
