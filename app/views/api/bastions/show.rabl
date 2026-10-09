object false

node :bastion do
  partial "api/bastions/bastion", object: @bastion
end

# Set by reset_password: the rebuild event.
node(:event_id) { @event.id } if @event
