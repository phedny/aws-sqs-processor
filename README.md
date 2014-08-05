AWS SQS processor
=================

Processing messages from an Amazon AWS SQS queue basically boils down to a loop that receives messages that are ready to be processed, process the messages and delete those message that have been processed. This library offers a nice API to do this loop.

Simply install the library using `npm`:

```sh
npm install --save aws-sqs-processor
```

The module exports a function that can be used to instantiate a processor. The functions accepts a set of configuration options and after calling `start()` on the processor it will emit any message to be processed using a `message` event.

The event listener for the `message` event is passed two arguments for each message. The first argument is the message in the format it is returned by the [aws-sdk] package. The second argument is a function that must be called to inform the processor when processing has finished.

Configuration options
---------------------

| Key                           | Description                                                                                                |
|-------------------------------|------------------------------------------------------------------------------------------------------------|
| accessKeyId                   | Amazon AWS Access Key ID                                                                                   |
| secretAccessKey               | Amazon AWS Secret Access Key                                                                               |
| region                        | Region in which the queue exists                                                                           |
| queueUrl                      | URL of the SQS queue                                                                                       |
| maxNumberOfMessagesProcessing | Maximum number of messages that is acceptable to being processed concurrently, default = 50                |
| maxNumberOfMessagesPerBatch   | Maximum number of messages to retrieve in a single `retrieveMessage` request; value = 1 - 10, default = 10 |
| visibilityTimeout             | Visibility timeout argument for the `retrieveMessage` request; value = 1 - 43200, default = 30             |
| waitTimeSeconds               | Number of seconds a long polling `retrieveMessage` request should wait; value = 1 - 20, default = 20       |

Processor behaviour
-------------------

The processor will try to retrieve up to `maxNumberOfMessagesPerBatch` per `retrieveMessage` request. Multiple `retrieveMessage` requests will be performed, up to the point where the number of messages that are being processed reaches `maxNumberOfMessagesProcessing`. At that point, the processor will wait until processing completes or failes for already dispatched messages.

When processing a message takes too long, the processor will automatically send a request to change the visibility of a message one second before the expected visibility deadline. You need to mark the processing of a message as completed or failed to notify the processor that the visibility of the message doesn't need to be updated anymore.

To mark a message a completed, call the function that is passed as the second argument to your `message` event handler without any argument. The processor will automatically request Amazon to delete the message.

A message will be marked as failed in the following cases:
* You call the function that is passed as the second argument to your `message` event handler with an argument
* You throw an error from your `message` event handler
* No `message` event handler is registered (so the message won't even be processed) 

When a message is marked as failed, the processor will no longer change the visibility of the message, so it will become visible after the visibility timeout. After that moment, Amazon will return the message to this or another processor.

Example usage
-------------

```javascript
var sqs = require('aws-sqs-processor')({
  accessKeyId: 'akid',
  secretAccessKey: 'secret',
  region: 'eu-west-1',
  queueUrl: 'https://sqs.eu-west-1.amazonaws.com/123456789012/example-queue'
});

sqs.on('message', function(message, done) {
  console.log('-----');
  console.log('Received message ' + message.MessageId);
  console.log('Message body:');
  console.log(message.Body);
  console.log('-----');
  setTimeout(function() {
    /*  I hope you're going to do some real work,
        but I'm going to pretend, because I'm lazy.
    */
    done();
  }, 5000);
});

sqs.start();
```

[aws-sdk]: https://www.npmjs.org/package/aws-sdk
