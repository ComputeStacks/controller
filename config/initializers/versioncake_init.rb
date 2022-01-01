#%r{/api/admin/containers/[0-9a-z]*/logs}.match uri
VersionCake.setup do |config|

  config.resources do |r|

    # r.resource uri_regex, obsolete, deprecated, supported

    ##
    # ADMIN
    # r.resource %r{/api/admin/projects}, [40,41], [51..54], [60]

    r.resource %r{.*}, [40,50], [51,52,53,54], [60,61,62,65]
  end

  config.extraction_strategy = :http_accept_parameter
  config.missing_version = 65

end
