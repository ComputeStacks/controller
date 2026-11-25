require "test_helper"

# Adding or removing a load balancer address re-checks the LB's domain.
class LoadBalancerAddrTest < ActiveSupport::TestCase
  setup do
    LoadBalancerWorkers::ValidateDomainWorker.clear
  end

  def create_lb(domain:)
    lb = LoadBalancer.new(region: Region.first, public_ip: "127.0.0.1", ext_ip: ["127.0.0.1"], domain: domain)
    lb.save!
    LoadBalancerWorkers::ValidateDomainWorker.clear
    lb
  end

  def jobs
    LoadBalancerWorkers::ValidateDomainWorker.jobs
  end

  test "creating an address enqueues domain validation" do
    lb = create_lb(domain: "addr.example.com")
    lb.ipaddrs.create!(ip_addr: "192.0.2.10", role: "public", label: "t")
    assert_equal [lb.id], jobs.map { |j| j["args"].first }
  end

  test "creating an internal or connect address enqueues nothing" do
    lb = create_lb(domain: "addr.example.com")
    lb.ipaddrs.create!(ip_addr: "10.0.0.5", role: "internal", label: "t")
    lb.ipaddrs.create!(ip_addr: "10.0.0.6", role: "connect", label: "t")
    assert_empty jobs
  end

  test "changing an internal address's ip enqueues nothing" do
    lb = create_lb(domain: "addr.example.com")
    addr = lb.ipaddrs.create!(ip_addr: "10.0.0.7", role: "internal", label: "t")
    addr.update!(ip_addr: "10.0.0.8")
    assert_empty jobs
  end

  test "creating a proxy address enqueues domain validation" do
    lb = create_lb(domain: "addr.example.com")
    lb.ipaddrs.create!(ip_addr: "192.0.2.0/24", role: "proxy", label: "t")
    assert_equal [lb.id], jobs.map { |j| j["args"].first }
  end

  test "changing an address's role to or from public enqueues domain validation" do
    lb = create_lb(domain: "addr.example.com")
    addr = lb.ipaddrs.create!(ip_addr: "192.0.2.20", role: "public", label: "t")
    LoadBalancerWorkers::ValidateDomainWorker.clear
    addr.update!(role: "internal")
    assert_equal 1, jobs.size
  end

  test "destroying an address enqueues domain validation" do
    lb = create_lb(domain: "addr.example.com")
    addr = lb.ipaddrs.create!(ip_addr: "192.0.2.11", role: "public", label: "t")
    LoadBalancerWorkers::ValidateDomainWorker.clear
    addr.destroy!
    assert_equal [lb.id], jobs.map { |j| j["args"].first }
  end

  test "changing an address's ip enqueues domain validation" do
    lb = create_lb(domain: "addr.example.com")
    addr = lb.ipaddrs.create!(ip_addr: "192.0.2.12", role: "public", label: "t")
    LoadBalancerWorkers::ValidateDomainWorker.clear
    addr.update!(ip_addr: "192.0.2.13")
    assert_equal [lb.id], jobs.map { |j| j["args"].first }
  end

  test "changing only an address's label enqueues nothing" do
    lb = create_lb(domain: "addr.example.com")
    addr = lb.ipaddrs.create!(ip_addr: "192.0.2.14", role: "public", label: "t")
    LoadBalancerWorkers::ValidateDomainWorker.clear
    addr.update!(label: "renamed")
    assert_empty jobs
  end

  test "destroying the load balancer enqueues nothing for its addresses" do
    lb = create_lb(domain: "addr.example.com")
    lb.ipaddrs.create!(ip_addr: "192.0.2.15", role: "public", label: "t")
    LoadBalancerWorkers::ValidateDomainWorker.clear
    lb.destroy!
    assert_empty jobs
  end
end
