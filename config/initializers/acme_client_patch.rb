# acme-client 2.0.21 bug: when an ACME server (e.g. pebble) omits the Location header from
# the finalize response, Acme::Client#finalize builds an Order without url:, causing
# Order#assign_attributes to raise ArgumentError: missing keyword: :url.
#
# Fix 1: Acme::Client#finalize — fall back to the finalize URL when Location is absent.
# Fix 2: Acme::Client::Resources::Order#finalize — restore the original order URL after
#         assign_attributes (the finalize_url != the order URL; reload must use the order URL).
Acme::Client.prepend(Module.new do
  def finalize(url:, csr:)
    unless csr.respond_to?(:to_der)
      raise ArgumentError, "csr must respond to `#to_der`"
    end
    base64_der_csr = Acme::Client::Util.urlsafe_base64(csr.to_der)
    response = post(url, payload: {csr: base64_der_csr})
    arguments = send(:attributes_from_order_response, response)
    Acme::Client::Resources::Order.new(self, **arguments.merge(url: arguments[:url] || url))
  end
end)

Acme::Client::Resources::Order.prepend(Module.new do
  def finalize(csr:)
    original_url = url
    assign_attributes(**@client.finalize(url: finalize_url, csr: csr).to_h)
    @url = original_url
    true
  end
end)
