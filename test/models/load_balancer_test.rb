require 'test_helper'

class LoadBalancerTest < ActiveSupport::TestCase

  include AcmeTestContainerConcern # Only enable when you need to refresh VCR.
  include PdnsTestContainerConcern

  setup do
    @lb = load_balancers(:default)
  end

  test 'has shared certificate' do
    assert_not_nil @lb.shared_certificate
    assert @lb.has_shared_cert?
    assert @lb.has_ssl_certs?
  end

  test 'has shared url' do
    refute @lb.domain.blank?
  end

  test 'has sftp containers' do
    assert_not_empty @lb.sftp_containers
  end

  test 'has services with custom ssl certificates' do
    # None of our fixtures have a cert right now, so this should be false.
    assert !@lb.has_custom_ssl?
  end

  test 'can find Lb by node' do
    service = Deployment::ContainerService.web_only.first
    container = service.containers.first
    assert_kind_of LoadBalancer, LoadBalancer.find_by_node(container.node)
  end

  test 'validate shared certificate' do

    valid_cert = "-----BEGIN PRIVATE KEY-----\nMIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQDa75w08SOOBein\ncybGBX/zGtZfdNHAD5SiIw7200aqUI0Mi6JBRfKbWsacWRRGeP/dF0Pd4LY4p77o\nZs49iW+r6nvDaSxn9NmGklZ13c3MIp80LE0O6j15p+0lt9zdwz0cV0aPyyzFGJ3Q\n6+nTOO/yH1sryCZSxmpZqamPxUu/G0zQmQwRQpLg56w0Cjt8Rr9fE/jOTUrfAjAA\nQu8sly4gpfSZ8vVKfA8yXJF33pOLa91PSd24yX9SKqaaGoLFKT6HRGm0XCeo3MFI\n6HH6ezyO/idmv55yaSw8TL1yFtZt7UwdvsvrrqtGC5NKRJ3+umT9J1wYzCZZspUU\nw3D3z0c/AgMBAAECggEALmepQWN3OMwx0wRKTKCvzRR8KcF2D/J9e5xYuKJxkPn/\n24/hNVqhIKKuBEexT3qoKPGcdfQCS6HqihH4VvzBibvqvbGWMvaoAKkV4GfCDims\nev+E2ct2eknIrzz4eJzAYDhzgVj8RU6BbN4EMrwXx8czqOUEknjx481dXlbgRkIb\niF5C+DtHBFHXnPY1Ph5ohStbSfLUY2k68yZOJDb5vLXTB/I7yoh75Dy1L202fywt\nM6SHtjrBYlyRLYWk2oJdDQd838qqeN6wiccQFoXZN6i+sHjk/xfPDZnpadHMR5m4\nz6kERTRnEmVac8Ws4OZK+tOEqJmvnKVrQJ6MJSdNeQKBgQD8Cp/7SwClBLU0tG/k\nxacLTEuVlQKV1oM0KQxHyKnPfh8nn5MFChhrLRXtANBlZTQPgXN2GQ1ls2juRdta\nyvg6CjRLXTYudaJnSwqpoAnvLsB6IBICMaeP6YZcVY09ln6z1aGdEz/pnJwySn8I\n9dLBicdQQ+d0OlrtERFkN6eugwKBgQDeX+ECWo2AsWg52zx05PYWdMqgpId2Rv8Y\nzeukRCczjZ4U3+MamyqYMbdURvKmAXUvR4fMNwemAvnA13v76Qem70b3MRBLvA/P\nNhB3JLj/IneJwk8UD7hDq9zAivYbOIRaJlrZLrSr+XJiuqjzGvGhG6ScwbPDKc9D\ngDmstABnlQKBgQC0GC96k3xRbczBbVEq6iTTiN/VcZVYVeCIq/APdw4Hqro+SOL3\nzd/m7V9ma5d9bFRH5BsJvxr4mbsXzyjPdorqhhIZ6+/kQMAcCN4EmMugcgqs+S+F\nC9AMoDQW1DbJVDkS7Uq+/1tC5VojAWJGl8jR7E5UR0EipvQDw5dmwfH6WwKBgQCs\ndxf/x1MvmGgJVytQTbM+P15XsMMOzIlUJ4C2adUteow8DFgKboVefFB/IHdYoJDO\nFmAP1i4sZupk0brq6RRyN+mGFZtZ4YUxY/DpNqXz2jtzsCu8l2SFt2kCO8Qb4H1l\nnZGgF0Uwi8pXIAWgZik4lkPY/7H3jxmcdHpGo2Qc8QKBgQCW8uO74X3EM6aOFfX3\nQwB2Lrz7jAVeOE3tyVGbIxdsXTjXupNy1bDvy7HImNCE1HWF3bEHp8bVXLLWte/E\niF93WU8S1x5T2u9BFe/Cpq3x3ocTB6RB+4M8TYyds5oXwNvn2DmFD2RuEuIpPiKY\nUzVxJNQeMZIRB9QD/LN/t5oGtg==\n-----END PRIVATE KEY-----\n-----BEGIN CERTIFICATE-----\nMIIDqTCCApGgAwIBAgIJAJCBuLXfgD0+MA0GCSqGSIb3DQEBCwUAMHIxCzAJBgNV\nBAYTAlVTMQswCQYDVQQIDAJPUjERMA8GA1UEBwwIUG9ydGxhbmQxFDASBgNVBAoM\nC0NTIEN1c3RvbWVyMRMwEQYDVQQLDApEZXBsb3ltZW50MRgwFgYDVQQDDA9sb2Nh\nbC51c3IuY2xvdWQwHhcNMTgxMjE1MDE0NjA4WhcNMjgxMjEyMDE0NjA4WjByMQsw\nCQYDVQQGEwJVUzELMAkGA1UECAwCT1IxETAPBgNVBAcMCFBvcnRsYW5kMRQwEgYD\nVQQKDAtDUyBDdXN0b21lcjETMBEGA1UECwwKRGVwbG95bWVudDEYMBYGA1UEAwwP\nbG9jYWwudXNyLmNsb3VkMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA\n2u+cNPEjjgXop3MmxgV/8xrWX3TRwA+UoiMO9tNGqlCNDIuiQUXym1rGnFkURnj/\n3RdD3eC2OKe+6GbOPYlvq+p7w2ksZ/TZhpJWdd3NzCKfNCxNDuo9eaftJbfc3cM9\nHFdGj8ssxRid0Ovp0zjv8h9bK8gmUsZqWampj8VLvxtM0JkMEUKS4OesNAo7fEa/\nXxP4zk1K3wIwAELvLJcuIKX0mfL1SnwPMlyRd96Ti2vdT0nduMl/UiqmmhqCxSk+\nh0RptFwnqNzBSOhx+ns8jv4nZr+ecmksPEy9chbWbe1MHb7L666rRguTSkSd/rpk\n/SdcGMwmWbKVFMNw989HPwIDAQABo0IwQDALBgNVHQ8EBAMCBDAwEwYDVR0lBAww\nCgYIKwYBBQUHAwEwHAYDVR0RBBUwE4IRKi5sb2NhbC51c3IuY2xvdWQwDQYJKoZI\nhvcNAQELBQADggEBAACWFdCu0KvdiLy0MqdMhS8KHNNZLGsJQ8U9X9sYlutt/yjf\n/l1oAsLqT4QxY02vvaaQqFzQn6Fg8deLrtu3/GjUTfrXzsPsU08Jqcp39tMnwOpz\nzqqc7KgiEddu19SLoYLxxxAmiUpvHMoQj8BENw7GwfSL1MTRSJqTeFCx+nTeRnVr\nJQUWGj3v+ZfYrSTu/cMso+3i1nDIYgSVQThjHX0373Btf1mWJ9X5ouIjnH/ozCVx\nDf+cMEKkGdadCSYEVvw3n4H1m8RmExWlNsVEJoXQCXuYWdY1pvDFQIy7JmbKJgsj\ntozJVxPGKwmvvSIEDjcAJgyfU0eGz+QTmEc8k10=\n-----END CERTIFICATE-----\n"

    lb = LoadBalancer.new(
      public_ip: '127.0.0.1',
      ext_ip: '127.0.0.1',
      domain: 'foobar.com',
      region: Region.first
    )

    # Valid without custom cert
    assert lb.valid?

    assert !lb.has_ssl_certs?
    assert !lb.has_shared_cert?
    assert_nil lb.shared_certificate

    lb.shared_certificate = valid_cert

    # Still valid with shared cert
    assert lb.valid?

    assert lb.has_ssl_certs?
    assert lb.has_shared_cert?

    # Invalid cert, this should fail!
    lb.shared_certificate = valid_cert[0..-3]
    assert !lb.valid?

  end

  ##
  # Domain Validation

  test 'domain: valid' do

    VCR.use_cassette('load_balancers/validate_domain_0') do
      fake_location = Location.create!(name: "fake00")
      region = Region.create!(location: fake_location, name: "fake000")
      Sidekiq::Testing.inline! do
        LoadBalancer.create!(
          label: 'test00',
          region: region,
          public_ip: '192.168.173.10',
          ext_ip: ['192.168.173.10'],
          le: false,
          internal_ip: ['192.168.173.10'],
          domain_valid: false,
          domain: 'app.sharedurl.com'
        )
      end
    end

    lb = LoadBalancer.find_by(label: 'test00')
    refute_nil lb

    # These are created when A record is wrong
    refute lb.event_details.where(event_code: '510806d5621c97d5').exists?
    refute lb.event_details.where(event_code: 'afda9ae32934c1d8').exists?

    # CNAME
    refute lb.event_details.where(event_code: '2721edc59787a807').exists?
    refute lb.event_details.where(event_code: '635285f7f2889009').exists?

    # EventLog created when invalid CAA record is found
    refute lb.event_details.where(event_code: '87744f149e2ed5ad').exists?
    refute lb.event_details.where(event_code: '47f76d011a0cc587').exists?

    # Ensure no failed events
    refute lb.event_logs.where(status: 'failed').exists?

    assert lb.domain_valid

  end

  test 'domain: invalid a record' do

    VCR.use_cassette('load_balancers/validate_domain_1') do
      fake_location = Location.create!(name: "fake01")
      region = Region.create!(location: fake_location, name: "fake001")
      Sidekiq::Testing.inline! do
        LoadBalancer.create!(
          label: 'test01',
          region: region,
          public_ip: '192.168.173.10',
          ext_ip: ['192.168.173.10'],
          le: false,
          internal_ip: ['192.168.173.10'],
          domain_valid: false,
          domain: 'app.sharedurl.us'
        )
      end
    end

    lb = LoadBalancer.find_by(label: 'test01')
    refute_nil lb

    # These are created when A record is wrong
    assert lb.event_details.where(event_code: '510806d5621c97d5').exists?
    refute lb.event_details.where(event_code: 'afda9ae32934c1d8').exists?

    # CNAME
    refute lb.event_details.where(event_code: '2721edc59787a807').exists?
    refute lb.event_details.where(event_code: '635285f7f2889009').exists?

    # EventLog created when invalid CAA record is found
    refute lb.event_details.where(event_code: '87744f149e2ed5ad').exists?
    refute lb.event_details.where(event_code: '47f76d011a0cc587').exists?

    # Ensure failed events
    assert lb.event_logs.where(status: 'failed').exists?

    refute lb.domain_valid

  end

  test 'domain: invalid CAA' do

    VCR.use_cassette('load_balancers/validate_domain_2') do
      fake_location = Location.create!(name: "fake02")
      region = Region.create!(location: fake_location, name: "fake002")
      Sidekiq::Testing.inline! do
        LoadBalancer.create!(
          label: 'test02',
          region: region,
          public_ip: '192.168.173.10',
          ext_ip: ['192.168.173.10'],
          le: false,
          internal_ip: ['192.168.173.10'],
          domain_valid: false,
          domain: 'app.sharedurl.net'
        )
      end
    end

    lb = LoadBalancer.find_by(label: 'test02')
    refute_nil lb

    # These are created when A record is wrong
    refute lb.event_details.where(event_code: '510806d5621c97d5').exists?
    refute lb.event_details.where(event_code: 'afda9ae32934c1d8').exists?

    # CNAME
    refute lb.event_details.where(event_code: '2721edc59787a807').exists?
    assert lb.event_details.where(event_code: '635285f7f2889009').exists?

    # EventLog created when invalid CAA record is found
    assert lb.event_details.where(event_code: '87744f149e2ed5ad').exists?
    assert lb.event_details.where(event_code: '47f76d011a0cc587').exists?

    # Ensure failed events
    assert lb.event_logs.where(status: 'failed').exists?

    refute lb.domain_valid

  end

  test 'domain: no caa record' do

    VCR.use_cassette('load_balancers/validate_domain_3') do
      fake_location = Location.create!(name: "fake03")
      region = Region.create!(location: fake_location, name: "fake003")
      Sidekiq::Testing.inline! do
        LoadBalancer.create!(
          label: 'test03',
          region: region,
          public_ip: '192.168.173.10',
          ext_ip: ['192.168.173.10'],
          le: false,
          internal_ip: ['192.168.173.10'],
          domain_valid: false,
          domain: 'app.sharedurl.org'
        )
      end
    end

    lb = LoadBalancer.find_by(label: 'test03')
    refute_nil lb

    # These are created when A record is wrong
    refute lb.event_details.where(event_code: '510806d5621c97d5').exists?
    refute lb.event_details.where(event_code: 'afda9ae32934c1d8').exists?

    # CNAME
    refute lb.event_details.where(event_code: '2721edc59787a807').exists?
    refute lb.event_details.where(event_code: '635285f7f2889009').exists?

    # EventLog created when invalid CAA record is found
    refute lb.event_details.where(event_code: '87744f149e2ed5ad').exists?
    refute lb.event_details.where(event_code: '47f76d011a0cc587').exists?

    # Ensure no failed events
    refute lb.event_logs.where(status: 'failed').exists?

    assert lb.domain_valid

  end

  test 'domain: missing wildcard caa' do

    VCR.use_cassette('load_balancers/validate_domain_4') do
      fake_location = Location.create!(name: "fake04")
      region = Region.create!(location: fake_location, name: "fake004")
      Sidekiq::Testing.inline! do
        LoadBalancer.create!(
          label: 'test04',
          region: region,
          public_ip: '192.168.173.10',
          ext_ip: ['192.168.173.10'],
          le: false,
          internal_ip: ['192.168.173.10'],
          domain_valid: false,
          domain: 'app.sharedurl.app'
        )
      end
    end

    lb = LoadBalancer.find_by(label: 'test04')
    refute_nil lb

    # These are created when A record is wrong
    refute lb.event_details.where(event_code: '510806d5621c97d5').exists?
    refute lb.event_details.where(event_code: 'afda9ae32934c1d8').exists?

    # CNAME
    refute lb.event_details.where(event_code: '2721edc59787a807').exists?
    refute lb.event_details.where(event_code: '635285f7f2889009').exists?

    # EventLog created when invalid CAA record is found
    refute lb.event_details.where(event_code: '87744f149e2ed5ad').exists?
    assert lb.event_details.where(event_code: '47f76d011a0cc587').exists?

    # Ensure failed events
    assert lb.event_logs.where(status: 'failed').exists?

    refute lb.domain_valid

  end

end
