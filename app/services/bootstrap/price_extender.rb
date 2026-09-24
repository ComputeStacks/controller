module Bootstrap
  ##
  # Extend existing billing prices to regions this apply created.
  #
  # +load_products+ attaches prices to +Region.all+ *as of the moment it runs*.
  # A region added to a live controller therefore has no prices at all, and
  # every product silently bills at 0.0 there. Nothing else in the application
  # repairs that, so the apply owns it.
  #
  # The rule, deliberately conservative:
  #
  #   A BillingResourcePrice is extended to a new region ONLY if it already
  #   covers every region that existed before this apply.
  #
  # A price that covers only some of the pre-existing regions is region-specific
  # pricing somebody built by hand; widening it would change what customers are
  # charged, so it is left alone and reported.
  #
  # Before linking, we check explicitly that no *other* price in the same
  # billing phase with the same currency and the same max_qty already covers the
  # new region. +BillingResourcePrice#ensure_unique_max_qty+ enforces that, but
  # it is a +before_validation+ on the price — and +price.regions << region+ is
  # a direct join insert that runs no parent validation at all. Without this
  # check the apply could create exactly the duplicate the model forbids.
  class PriceExtender
    def initialize(recorder, writer, preexisting_region_ids)
      @recorder = recorder
      @writer = writer
      @preexisting_region_ids = preexisting_region_ids.map(&:to_i).to_set
    end

    # @param regions [Array<Region>] regions created by this apply
    def perform(regions)
      return if regions.empty?
      return if @preexisting_region_ids.empty? # greenfield: load_products already covered them
      return unless BillingResourcePrice.exists?

      regions.each { |region| extend_to(region) }
    end

    private

    def extend_to(region)
      BillingResourcePrice.includes(:regions, :billing_resource).find_each do |price|
        label = price_label(price)
        covered = price.regions.map(&:id).to_set

        next if covered.include?(region.id)

        unless @preexisting_region_ids.subset?(covered)
          @recorder.skip(label, "region-specific pricing — does not cover every pre-existing region")
          next
        end

        if duplicate_coverage?(price, region)
          @recorder.skip(label, "#{region.name} already priced at max_qty=#{price.max_qty.inspect} #{price.currency} in this phase")
          next
        end

        @writer.link!(price.regions, region, label: label, detail: region.name)
      end
    end

    # Would linking this price to this region produce two prices in the same
    # phase covering the same region at the same currency + max_qty?
    def duplicate_coverage?(price, region)
      siblings = BillingResourcePrice
        .where(billing_phase_id: price.billing_phase_id, currency: price.currency)
        .where.not(id: price.id)
      siblings = if price.max_qty.nil?
        siblings.where(max_qty: nil)
      else
        siblings.where(max_qty: price.max_qty)
      end
      siblings.joins(:regions).where(regions: {id: region.id}).exists?
    end

    def price_label(price)
      product = price.billing_resource&.product
      "BillingResourcePrice ##{price.id} (#{product&.name || "unknown product"}, max_qty=#{price.max_qty.inspect})"
    end
  end
end
