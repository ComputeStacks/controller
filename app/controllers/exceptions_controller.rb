class ExceptionsController < ApplicationController

	def internal_server_error
		@sentry_event_id = Raven.last_event_id
		render layout: 'devise', status: 500
	end

end
