# v7.1 LetsEncrypt Changes

We now support placing a single domain onto a certificate, rather than adding domains to an existing certificate. You may enable this in the Settings, under Lets Encrypt.

***

**NOTE:** It's important to understand Lets Encrypt [Rate Limits](https://letsencrypt.org/docs/rate-limits/) and ensure that you will not exceed them. Otherwise, you could prevent both renewals and new certificate generation.

If you still wish to proceed with this option, but you know you will exceed their limits, at the bottom of that link you will find a form where you can request an exemption.

***

## Migrating existing domains to their own certificate

Here is an example to move domains, 10 at a time.

```ruby
max = 30
regenerate = []
Deployment::ContainerDomain.where(system_domain: false).joins(:lets_encrypt).each do |domain|
  next if domain.lets_encrypt&.common_name == domain.domain
  regenerate << domain
  domain.update lets_encrypt: nil
  break if regenerate.count >= max
end
```
