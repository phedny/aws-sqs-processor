AWS SQS processor
=================

Processing messages from an Amazon AWS SQS queue basically boils down to a loop that receives messages that are ready to be processed, process the messages and delete those message that have been processed. This library offers a nice API to do this loop.

Simply install the library using `npm`:

```sh
npm install --save aws-sqs-processor
```
