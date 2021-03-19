# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

module OpenTelemetry
  module Instrumentation
    module Sidekiq
      module Middlewares
        module Server
          # TracerMiddleware propagates context and instruments Sidekiq requests
          # by way of its middleware system
          class TracerMiddleware
            # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Lint/RescueException
            def call(_worker, msg, _queue)
              parent_context = OpenTelemetry.propagation.extract(msg)
              tracer.in_span(
                span_name(msg),
                attributes: {
                  'messaging.system' => 'sidekiq',
                  'messaging.sidekiq.job_class' => msg['wrapped']&.to_s || msg['class'],
                  'messaging.message_id' => msg['jid'],
                  'messaging.destination' => msg['queue'],
                  'messaging.destination_kind' => 'queue'
                },
                with_parent: parent_context,
                kind: :consumer
              ) do |span|
                span.add_event('created_at', timestamp: msg['created_at'])
                span.add_event('enqueued_at', timestamp: msg['enqueued_at'])
                yield

                span.set_attribute('success', 'true')
              rescue Exception => e
                span.set_attribute('error.message', e.message)
                span.set_attribute('error.backtrace', e.backtrace.join("\n"))
                span.set_attribute('success', 'false')
                span.finish

                raise
              end
            end
            # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Lint/RescueException

            private

            def span_name(msg)
              if config[:enable_job_class_span_names]
                "#{msg['wrapped']&.to_s || msg['class']} process"
              else
                "#{msg['queue']} process"
              end
            end

            def config
              Sidekiq::Instrumentation.instance.config
            end

            def tracer
              Sidekiq::Instrumentation.instance.tracer
            end
          end
        end
      end
    end
  end
end
