require "aws-sdk"
require "reaper"

# Make sure we don't accidentally make calls to AWS during tests
Aws.config[:stub_responses] = true
