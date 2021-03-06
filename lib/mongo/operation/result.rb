# Copyright (C) 2009-2014 MongoDB, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module Mongo
  module Operation

    # Result wrapper for operations.
    #
    # @since 2.0.0
    class Result
      extend Forwardable
      include Enumerable

      # The number of documents updated in the write.
      #
      # @since 2.0.0
      N = 'n'.freeze

      # The ok status field in the result.
      #
      # @since 2.0.0
      OK = 'ok'.freeze

      # @return [ Array<Protocol::Reply> ] replies The wrapped wire protocol replies.
      attr_reader :replies

      # Is the result acknowledged?
      #
      # @note On MongoDB 2.6 and higher all writes are acknowledged since the
      #   driver uses write commands for all write operations. On 2.4 and
      #   lower, the result is acknowledged if the GLE has been executed after
      #   the command. If not, no replies will be specified. Reads will always
      #   return true here since a replies is always provided.
      #
      # @return [ true, false ] If the result is acknowledged.
      #
      # @since 2.0.0
      def acknowledged?
        !!@replies
      end

      # Determine if this result is a collection of multiple replies from the
      # server.
      #
      # @example Is the result for multiple replies?
      #   result.multiple?
      #
      # @return [ true, false ] If the result is for multiple replies.
      #
      # @since 2.0.0
      def multiple?
        replies.size > 1
      end

      # Get the cursor id if the response is acknowledged.
      #
      # @note Cursor ids of 0 indicate there is no cursor on the server.
      #
      # @example Get the cursor id.
      #   result.cursor_id
      #
      # @return [ Integer ] The cursor id.
      #
      # @since 2.0.0
      def cursor_id
        acknowledged? ? replies.last.cursor_id : 0
      end

      # Get the documents in the result.
      #
      # @example Get the documents.
      #   result.documents
      #
      # @return [ Array<BSON::Document> ] The documents.
      #
      # @since 2.0.0
      def documents
        if acknowledged?
          replies.flat_map{ |reply| reply.documents }
        else
          []
        end
      end

      # Iterate over the documents in the replies.
      #
      # @example Iterate over the documents.
      #   result.each do |doc|
      #     p doc
      #   end
      #
      # @return [ Enumerator ] The enumerator.
      #
      # @since 2.0.0
      #
      # @yieldparam [ BSON::Document ] Each document in the result.
      def each(&block)
        documents.each(&block)
      end

      # Initialize a new result result.
      #
      # @example Instantiate the result.
      #   Result.new(replies)
      #
      # @param [ Protocol::Reply ] replies The wire protocol replies.
      #
      # @since 2.0.0
      def initialize(replies)
        @replies = replies.is_a?(Protocol::Reply) ? [ replies ] : replies
      end

      # Get the pretty formatted inspection of the result.
      #
      # @example Inspect the result.
      #   result.inspect
      #
      # @return [ String ] The inspection.
      #
      # @since 2.0.0
      def inspect
        "#<Mongo::Operation::Result:#{object_id} documents=#{documents}>"
      end

      # Get the first reply from the result.
      #
      # @example Get the first reply.
      #   result.reply
      #
      # @return [ Protocol::Reply ] The first reply.
      #
      # @since 2.0.0
      def reply
        if acknowledged?
          replies.first
        else
          nil
        end
      end

      # Get the count of documents returned by the server.
      #
      # @example Get the number returned.
      #   result.returned_count
      #
      # @return [ Integer ] The number of documents returned.
      #
      # @since 2.0.0
      def returned_count
        if acknowledged?
          multiple? ? aggregate_returned_count : reply.number_returned
        else
          0
        end
      end

      # If the result was a command then determine if it was considered a
      # success.
      #
      # @note If the write was unacknowledged, then this will always return
      #   true.
      #
      # @example Was the command successful?
      #   result.successful?
      #
      # @return [ true, false ] If the command was successful.
      #
      # @since 2.0.0
      def successful?
        acknowledged? ? first[OK] == 1 : true
      end

      # Validate the result by checking for any errors.
      #
      # @note This only checks for errors with writes since authentication is
      #   handled at the connection level and any authentication errors would
      #   be raised there, before a Result is ever created.
      #
      # @example Validate the result.
      #   result.validate!
      #
      # @raise [ Write::Failure ] If an error is in the result.
      #
      # @return [ Result ] The result if verification passed.
      #
      # @since 2.0.0
      def validate!
        write_failure? ? raise(Write::Failure.new(first)) : self
      end

      # Get the number of documents written by the server.
      #
      # @example Get the number of documents written.
      #   result.written_count
      #
      # @return [ Integer ] The number of documents written.
      #
      # @since 2.0.0
      def written_count
        if acknowledged?
          multiple? ? aggregate_written_count : (first[N] || 0)
        else
          0
        end
      end
      alias :n :written_count

      # Whether there was a write failure.
      #
      # @example Determine if there was a write failure.
      #   result.write_failure?
      #
      # @return [ true, false ] If there was a write failure.
      #
      # @since 2.0.0
      def write_failure?
        acknowledged? && (command_failure? || write_errors? || write_concern_errors?)
      end

      private

      def aggregate_returned_count
        replies.reduce(0) do |n, reply|
          n += reply.number_returned
          n
        end
      end

      def aggregate_written_count
        documents.reduce(0) do |n, document|
          n += (document[N] || 0)
          n
        end
      end

      def command_failure?
        acknowledged? && (!successful? || errors?)
      end

      def errors?
        first[Operation::ERROR] && first[Operation::ERROR_CODE]
      end

      def first
        @first ||= documents[0] || {}
      end

      def write_concern_errors
        first[Write::WRITE_CONCERN_ERROR] || []
      end

      def write_concern_errors?
        !write_concern_errors.empty?
      end

      def write_errors
        first[Write::WRITE_ERRORS] || []
      end

      def write_errors?
        !write_errors.empty?
      end
    end
  end
end
